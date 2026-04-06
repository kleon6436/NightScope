import Foundation
import Combine

@MainActor
final class LLMService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var activeKind: LLMBackendKind

    var availableBackends: [LLMBackendKind] {
        LLMBackendKind.allCases
    }

    // MARK: - Backends

    private let foundationModelsBackend: FoundationModelsBackend
    let mlxBackend: MLXBackend

    private var currentSystemPrompt: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var terminationHandlerID: UUID?
    private var isTerminationInProgress = false

    private var activeBackend: LLMBackend {
        switch activeKind {
        case .appleIntelligence: return foundationModelsBackend
        case .mlx:               return mlxBackend
        }
    }

    // MARK: - Init

    init() {
        self.foundationModelsBackend = FoundationModelsBackend()
        self.mlxBackend = MLXBackend()

        let saved = UserDefaults.standard.string(forKey: "llm_backend") ?? ""
        self.activeKind = LLMBackendKind(rawValue: saved) ?? .appleIntelligence

        terminationHandlerID = AppTerminationCoordinator.shared.registerHandler { [weak self] in
            await self?.prepareForTermination()
        }

        // Settings 変更を反映
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let raw = UserDefaults.standard.string(forKey: "llm_backend") ?? ""
                let newKind = LLMBackendKind(rawValue: raw) ?? .appleIntelligence
                if newKind != self.activeKind {
                    self.switchBackend(to: newKind)
                }
            }
            .store(in: &cancellables)

        // 起動時に選択済みの MLX モデルをロード
        Task { [weak self] in
            await self?.mlxBackend.loadIfNeeded()
        }
    }

    deinit {
        let handlerID = terminationHandlerID
        Task { @MainActor in
            if let handlerID {
                AppTerminationCoordinator.shared.unregisterHandler(id: handlerID)
            }
        }
    }

    // MARK: - Public

    var isAvailable: Bool { activeBackend.isAvailable }

    var activeModelLabel: String {
        switch activeKind {
        case .appleIntelligence: return "Apple Intelligence"
        case .mlx:               return mlxBackend.selectedModel?.displayName ?? "ローカル LLM"
        }
    }

    var unavailableDescription: String {
        if isTerminationInProgress {
            return "アプリ終了処理中です…"
        }

        switch activeKind {
        case .appleIntelligence:
            return foundationModelsBackend.unavailableReason ?? "Apple Intelligence を利用できません"
        case .mlx:
            if mlxBackend.selectedModel == nil {
                return "設定からモデルを選択してください"
            }
            if case .downloading(let p) = mlxBackend.modelState {
                return String(format: "モデルをダウンロード中… %.0f%%", p * 100)
            }
            if case .loading = mlxBackend.modelState {
                return "モデルを読み込み中…"
            }
            if case .error(let msg) = mlxBackend.modelState {
                return msg
            }
            return "ローカル LLM を利用できません"
        }
    }

    func configure(systemPrompt: String) {
        guard !isTerminationInProgress else { return }
        currentSystemPrompt = systemPrompt
        activeBackend.resetSession(systemPrompt: systemPrompt)
    }

    func switchBackend(to kind: LLMBackendKind) {
        guard !isTerminationInProgress else { return }
        // バックエンド切替時は旧バックエンドの推論残留を避けるため、両方を同期的にリセットする。
        foundationModelsBackend.resetSession(systemPrompt: currentSystemPrompt)
        mlxBackend.resetSession(systemPrompt: currentSystemPrompt)
        activeKind = kind
    }

    func send(userMessage: String) -> AsyncThrowingStream<String, Error> {
        guard !isTerminationInProgress else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CancellationError())
            }
        }
        return activeBackend.send(userMessage: userMessage)
    }

    /// 実行中の推論をキャンセルし完全停止を待機する。
    /// バックエンド切替直後でも取りこぼしがないよう、両バックエンドの停止処理を実行する。
    func cancelInference() async {
        await foundationModelsBackend.cancelInference()
        await mlxBackend.cancelInference()
    }

    /// アプリ終了時の安全停止シーケンス。
    /// `AppDelegate -> AppTerminationCoordinator -> AssistantViewModel` から呼び出される。
    func prepareForTermination() async {
        guard !isTerminationInProgress else {
            await cancelInference()
            return
        }

        isTerminationInProgress = true
        foundationModelsBackend.beginTerminationMode()
        mlxBackend.beginTerminationMode()
        await cancelInference()
    }
}
