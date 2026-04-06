import Foundation
import MLXLMCommon
import MLXLLM
import OSLog

/// MLX-Swift を使ったローカル LLM バックエンド実装
@MainActor
final class MLXBackend: ObservableObject, LLMBackend {

    private static var terminationRetainedObjects: [Any] = []
    private static var terminationRetainedTasks: [Task<Void, Never>] = []
    private let logger = Logger(subsystem: "com.kleon.NightScope", category: "MLXBackend")

    private actor StreamTerminationGate {
        private var isTerminated = false

        func canEmit() -> Bool {
            !isTerminated
        }

        func markTerminatedIfNeeded() -> Bool {
            guard !isTerminated else { return false }
            isTerminated = true
            return true
        }

        func markTerminated() {
            isTerminated = true
        }
    }

    // MARK: - LLMBackend

    var kind: LLMBackendKind { .mlx }

    var isAvailable: Bool {
        guard selectedModel != nil else { return false }
        return modelState == .loaded
    }

    // MARK: - Model State

    enum ModelState: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var modelState: ModelState = .idle
    @Published private(set) var selectedModel: MLXModelSpec?
    @Published var downloadProgress: Double = 0

    // MARK: - Private

    private static let selectedModelKey = "mlx_selected_model_id"

    private var container: ModelContainer?
    private var chatSession: ChatSession?
    private var currentSystemPrompt: String = ""
    /// 実行中の生成タスク（KV キャッシュ競合防止のため逐次実行を保証する）
    private var activeStreamTask: Task<Void, Never>?
    /// `activeStreamTask` の識別子。
    private var activeStreamID: UUID?
    /// 直前の生成タスク。active が待機中にキャンセルされた場合でも孤児化させないため保持する。
    private var previousStreamTask: Task<Void, Never>?
    /// `previousStreamTask` の識別子。
    private var previousStreamID: UUID?
    /// 推論停止処理の再入を防ぐフラグ。
    private var isCancellingInference = false
    /// アプリ終了処理開始後の新規推論を遮断するフラグ。
    private var isTerminationModeEnabled = false
    /// 実行中推論に対する協調停止要求フラグ。
    private var isCooperativeStopRequested = false

    // MARK: - Init

    init() {
        if let savedID = UserDefaults.standard.string(forKey: Self.selectedModelKey),
           let spec = MLXModelSpec.builtinModels.first(where: { $0.id == savedID }) {
            selectedModel = spec
        }
    }

    // MARK: - LLMBackend Methods

    func beginTerminationMode() {
        logger.notice("beginTerminationMode invoked")
        isTerminationModeEnabled = true
    }

    /// 実行中の MLX 推論タスクをキャンセルし、完全終了まで待機する。
    /// アプリ終了前に呼び出すことで、C++ forward pass が解放済みメモリにアクセスする
    /// `__next_prime overflow` クラッシュを防ぐ。
    func cancelInference() async {
        logger.notice("cancelInference start: terminationMode=\(self.isTerminationModeEnabled, privacy: .public)")
        if isCancellingInference {
            logger.notice("cancelInference re-entry detected; waiting for in-flight cancellation")
            while isCancellingInference {
                await Task.yield()
            }
            return
        }

        isCancellingInference = true
        defer {
            isCancellingInference = false
            if !isTerminationModeEnabled {
                isCooperativeStopRequested = false
            }
        }

        // 通常キャンセル時のみ協調停止要求を有効化する。
        // 終了モード中は安全性を優先し、既存の自然終了待ちフローを維持する。
        if !isTerminationModeEnabled {
            isCooperativeStopRequested = true
        }

        let tasks = [activeStreamTask, previousStreamTask].compactMap { $0 }

        if isTerminationModeEnabled {
            logger.notice("cancelInference in termination mode: retain objects and wait for natural task completion")
            retainForTerminationLifetime(tasks: tasks, container: container, session: chatSession)

            // 終了モード中は MLX の cancel 経路を通さず、
            // 参照を固定したまま自然終了を待つ。
            activeStreamTask = nil
            activeStreamID = nil
            previousStreamTask = nil
            previousStreamID = nil

            for task in tasks {
                await task.value
            }

            logger.notice("cancelInference termination mode done")
            return
        }

        // 先に参照を外し、新規 send と競合しないようにする。
        activeStreamTask = nil
        activeStreamID = nil
        previousStreamTask = nil
        previousStreamID = nil

        guard !tasks.isEmpty else { return }

        for task in tasks {
            task.cancel()
        }

        for task in tasks {
            await task.value
        }
        logger.notice("cancelInference completed with active cancellation")
    }

    func resetSession(systemPrompt: String) {
        if isTerminationModeEnabled {
            logger.notice("resetSession ignored due to termination mode")
            currentSystemPrompt = systemPrompt
            return
        }

        if isCancellingInference {
            logger.notice("resetSession deferred because cancellation is in progress")
            currentSystemPrompt = systemPrompt
            return
        }

        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeStreamID = nil
        previousStreamTask?.cancel()
        previousStreamTask = nil
        previousStreamID = nil
        isCooperativeStopRequested = false
        currentSystemPrompt = systemPrompt
        guard let container else { return }
        chatSession = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(
                maxTokens: 2048,
                temperature: 0.7
            )
        )
    }

    func send(userMessage: String) -> AsyncThrowingStream<String, Error> {
        if isTerminationModeEnabled {
            logger.notice("send rejected due to termination mode")
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CancellationError())
            }
        }

        // 新しい生成開始時は停止要求をクリアする。
        isCooperativeStopRequested = false

        // 前回の生成タスクを保持し、完全終了を待ってから新生成を開始する
        let previousTask = activeStreamTask
        let previousID = activeStreamID
        previousTask?.cancel()
        previousStreamTask = previousTask
        previousStreamID = previousID
        let (output, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let streamID = UUID()
        let terminationGate = StreamTerminationGate()

        let task = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.clearStreamReferences(activeID: streamID, previousID: previousID)
                }
            }

            // 前回の生成が完全に終了するまで最大10秒待機（KV キャッシュ競合防止）
            if let prev = previousTask {
                await self?.waitUntilTaskFinishesOrTimeout(prev, timeout: .seconds(10))
            }

            if let self, self.isTerminationModeEnabled {
                self.logger.notice("stream task detected termination mode and exits with cancellation")
                if await terminationGate.markTerminatedIfNeeded() {
                    continuation.finish(throwing: CancellationError())
                }
                return
            }

            guard !Task.isCancelled else {
                if await terminationGate.markTerminatedIfNeeded() {
                    continuation.finish()
                }
                return
            }
            guard let self, let session = self.chatSession else {
                if await terminationGate.markTerminatedIfNeeded() {
                    continuation.finish(throwing: MLXBackendError.modelNotLoaded)
                }
                return
            }

            do {
                let responseStream = session.streamResponse(to: userMessage)
                for try await token in responseStream {
                    try Task.checkCancellation()
                    guard await terminationGate.canEmit() else { break }

                    if self.isCooperativeStopRequested {
                        self.logger.notice("cooperative stop requested; finish continuation and drain stream safely")
                        if await terminationGate.markTerminatedIfNeeded() {
                            continuation.finish(throwing: CancellationError())
                        }
                        continue
                    }

                    continuation.yield(token)
                }
                if await terminationGate.markTerminatedIfNeeded() {
                    continuation.finish()
                }
            } catch {
                if await terminationGate.markTerminatedIfNeeded() {
                    continuation.finish(throwing: error)
                }
            }
        }

        activeStreamTask = task
        activeStreamID = streamID
        continuation.onTermination = { [weak self] _ in
            Task {
                await terminationGate.markTerminated()
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isTerminationModeEnabled else { return }
                self.logger.notice("continuation terminated; cancelling underlying stream task")
                task.cancel()
            }
        }
        return output
    }

    // MARK: - Model Management

    /// モデルを選択してダウンロード・ロードを開始する
    func selectAndLoad(model spec: MLXModelSpec) async {
        selectedModel = spec
        UserDefaults.standard.set(spec.id, forKey: Self.selectedModelKey)

        // メモリチェック
        let physicalMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        if physicalMemoryGB < spec.minRAMGB {
            modelState = .error("このモデルには \(spec.minRAMGB)GB 以上の RAM が推奨されます（現在 \(physicalMemoryGB)GB）")
        }

        await loadModel(spec: spec)
    }

    /// 選択済みモデルが存在すればロードする（起動時に呼ぶ）
    func loadIfNeeded() async {
        guard !isTerminationModeEnabled else { return }
        guard let spec = selectedModel, modelState == .idle else { return }
        await loadModel(spec: spec)
    }

    // MARK: - Private

    private func waitUntilTaskFinishesOrTimeout(_ task: Task<Void, Never>, timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: timeout) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func clearStreamReferences(activeID: UUID, previousID: UUID?) {
        if activeStreamID == activeID {
            activeStreamTask = nil
            activeStreamID = nil
        }
        if previousStreamID == previousID {
            previousStreamTask = nil
            previousStreamID = nil
        }
    }

    private func retainForTerminationLifetime(
        tasks: [Task<Void, Never>],
        container: ModelContainer?,
        session: ChatSession?
    ) {
        if !tasks.isEmpty {
            Self.terminationRetainedTasks.append(contentsOf: tasks)
        }
        if let container {
            Self.terminationRetainedObjects.append(container)
        }
        if let session {
            Self.terminationRetainedObjects.append(session)
        }
    }

    private func loadModel(spec: MLXModelSpec) async {
        guard !isTerminationModeEnabled else { return }
        modelState = .loading
        do {
            let newContainer = try await loadModelContainer(id: spec.id) { [weak self] progress in
                Task { @MainActor [weak self] in
                    let fraction = progress.fractionCompleted
                    if fraction < 1.0 {
                        self?.modelState = .downloading(progress: fraction)
                        self?.downloadProgress = fraction
                    }
                }
            }
            container = newContainer
            chatSession = ChatSession(
                newContainer,
                instructions: currentSystemPrompt.isEmpty ? nil : currentSystemPrompt,
                generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.7)
            )
            modelState = .loaded
        } catch {
            modelState = .error(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum MLXBackendError: LocalizedError {
    case modelNotLoaded
    case insufficientMemory(required: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "モデルがロードされていません。設定からモデルを選択してください。"
        case .insufficientMemory(let required, let available):
            return "RAM が不足しています（必要: \(required)GB、搭載: \(available)GB）"
        }
    }
}
