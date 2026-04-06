import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AssistantViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var summary: String = ""
    @Published private(set) var advices: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var modelLabel: String = ""

    // MARK: - Dependencies

    private let llmService: LLMService
    private let appController: AppController
    private let logger = Logger(subsystem: "com.kleon.NightScope", category: "AssistantViewModel")
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?
    private var generationID = 0
    private static let generationTimeout: Duration = .seconds(30)

    // MARK: - Init

    init(llmService: LLMService, appController: AppController) {
        self.llmService = llmService
        self.appController = appController
        setupObservers()
        updateModelLabel()
        generateContent()
    }

    deinit {
        generationTask?.cancel()
    }

    // MARK: - Public

    var isLLMAvailable: Bool { llmService.isAvailable }
    var unavailableDescription: String { llmService.unavailableDescription }

    /// アクティブなバックエンドとモデルサイズから最適なプロンプトスタイルを返す
    private var currentPromptStyle: PromptStyle {
        switch llmService.activeKind {
        case .appleIntelligence:
            return .appleIntelligence
        case .mlx:
            let ramGB = llmService.mlxBackend.selectedModel?.minRAMGB ?? 4
            return ramGB <= 2 ? .mlxSmall : .mlxLarge
        }
    }
    /// 現在選択中の日付に対してサマリー＋アドバイス 2 件を生成する
    /// - Parameter targetDate: 生成対象の日付。nil の場合は `appController.selectedDate` を使用する。
    ///   `@Published` の willSet タイミング問題を回避するため、Combine sink からは
    ///   受け取った新しい日付を明示的に渡すこと。
    func generateContent(for targetDate: Date? = nil) {
        cancelCurrentGenerationTask()
        summary = ""
        advices = []
        isLoading = true
        generationID += 1
        let currentID = generationID

        let date = targetDate ?? appController.selectedDate
        let (nightSummary, starGazingIndex) = resolveNightData(for: date)
        let weather = appController.weatherService.summary(for: date)

        let systemPrompt = AssistantContextBuilder.buildSystemPrompt(
            nightSummary: nightSummary,
            starGazingIndex: starGazingIndex,
            weather: weather,
            bortleClass: appController.lightPollutionService.bortleClass,
            locationName: appController.locationController.locationName,
            date: date,
            promptStyle: currentPromptStyle
        )
        llmService.configure(systemPrompt: systemPrompt)

        guard llmService.isAvailable else {
            applyFallback(nightSummary: nightSummary, starGazingIndex: starGazingIndex, weather: weather, date: date)
            isLoading = false
            return
        }

        let prompt = AssistantContextBuilder.buildCardPrompt(weather: weather, promptStyle: currentPromptStyle)

        // ここは MainActor 上。send() を Task 外で同期的に呼び
        // ストリームを確保してから Task へ渡す。
        // Task 内の child task から await で呼ぶと、MainActor ホップ待ちの間に
        // 別日の generateContent() が configure() でセッションを差し替えてしまい
        // 前の日付のセッションが混入するレース条件が発生する。
        let stream = llmService.send(userMessage: prompt)

        generationTask = Task { [weak self] in
            guard let self else { return }

            let fullResponse = await collectResponseWithTimeout(stream: stream, timeout: Self.generationTimeout)

            guard !Task.isCancelled, generationID == currentID else { return }

            let parsed = AssistantContextBuilder.parseCardResponse(fullResponse)
            let rawText = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            debugLogModelOutput(rawText: rawText, parsedSummary: parsed.summary, parsedAdvices: parsed.advices)
            let hasModelOutput = !rawText.isEmpty || !parsed.summary.isEmpty || !parsed.advices.isEmpty
            if hasModelOutput {
                summary = parsed.summary.isEmpty
                    ? (rawText.isEmpty
                        ? AssistantContextBuilder.buildProactiveMessage(starGazingIndex: starGazingIndex)
                        : rawText)
                    : parsed.summary

                let templateAdvices = AssistantContextBuilder.buildTemplateAdvices(
                    nightSummary: nightSummary,
                    tier: starGazingIndex?.tier,
                    weather: weather
                )
                var mergedAdvices = parsed.advices
                if mergedAdvices.count < 2 {
                    for advice in templateAdvices where mergedAdvices.count < 2 {
                        guard !mergedAdvices.contains(advice) else { continue }
                        mergedAdvices.append(advice)
                    }
                }
                advices = Array(mergedAdvices.prefix(2))
            } else {
                applyFallback(nightSummary: nightSummary, starGazingIndex: starGazingIndex, weather: weather, date: date)
            }
            isLoading = false
        }
    }

    // MARK: - Private

    private func resolveNightData(for date: Date) -> (NightSummary?, StarGazingIndex?) {
        // upcomingNights は起動時・位置変更時に計算済み（today = offset 0 を含む）
        // selectedDate 変更ごとに呼ばれる recalculate() の非同期更新を待たずに
        // 安定したキャッシュデータを使うことで stale データの表示を防ぐ
        let nightSummary = appController.upcomingNights.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let index = appController.upcomingIndexes[startOfDay]

        // upcoming に今日が含まれていない場合（計算完了前など）は fallback
        if nightSummary != nil || index != nil {
            return (nightSummary, index)
        }
        if Calendar.current.isDateInToday(date) {
            return (appController.nightSummary, appController.starGazingIndex)
        }
        return (nil, nil)
    }

    private func applyFallback(
        nightSummary: NightSummary?,
        starGazingIndex: StarGazingIndex?,
        weather: DayWeatherSummary?,
        date: Date
    ) {
        summary = AssistantContextBuilder.buildProactiveMessage(
            starGazingIndex: starGazingIndex
        )
        advices = AssistantContextBuilder.buildTemplateAdvices(
            nightSummary: nightSummary,
            tier: starGazingIndex?.tier,
            weather: weather
        )
    }

    private func setupObservers() {
        // アプリ終了時に生成タスクをキャンセルして LanguageModelSession を安全に解放する
        // （MLX の安全停止は LLMService が AppTerminationCoordinator 経由で実施）
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.cancelCurrentGenerationTask()
            }
            .store(in: &cancellables)

        // 日付変更時に自動で再生成
        // @Published は willSet タイミングで通知するため、appController.selectedDate を
        // sink 内で読むと古い値になる。受け取った newDate を直接渡して stale 読み取りを防ぐ。
        appController.$selectedDate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newDate in
                self?.generateContent(for: newDate)
            }
            .store(in: &cancellables)

        // バックエンド切替時にモデルラベルを更新し、即時再生成する
        // @Published は willSet タイミングで通知するため、sink 内で llmService.activeKind を読むと
        // まだ旧値になる。受け取った newKind を直接使ってラベルを設定する。
        llmService.$activeKind
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newKind in
                guard let self else { return }
                self.modelLabel = self.resolveModelLabel(for: newKind)
                self.generateContent()
            }
            .store(in: &cancellables)

        // MLX モデル変更時にモデルラベルを更新し、即時再生成する
        // 同様に willSet タイミング問題を避けるため、受け取った newModel を直接使う。
        llmService.mlxBackend.$selectedModel
            .dropFirst()
            .map { ($0?.displayName, $0 != nil) }
            .sink { [weak self] displayName, hasSelectedModel in
                guard let self else { return }
                if self.llmService.activeKind == .mlx {
                    self.modelLabel = displayName ?? "ローカル LLM"
                }
                guard hasSelectedModel else { return }
                self.generateContent()
            }
            .store(in: &cancellables)

        // MLX モデルのロード完了時に再生成する（ダウンロード・ロード完了後に反映）
        llmService.mlxBackend.$modelState
            .dropFirst()
            .sink { [weak self] state in
                guard case .loaded = state else { return }
                guard let self, self.llmService.activeKind == .mlx else { return }
                self.generateContent()
            }
            .store(in: &cancellables)
    }

    private func updateModelLabel() {
        modelLabel = resolveModelLabel(for: llmService.activeKind)
    }

    /// `@Published` の willSet 問題を回避するため、activeKind の確定前でも正しいラベルを返す
    private func resolveModelLabel(for kind: LLMBackendKind) -> String {
        switch kind {
        case .appleIntelligence: return "Apple Intelligence"
        case .mlx: return llmService.mlxBackend.selectedModel?.displayName ?? "ローカル LLM"
        }
    }

    private func collectResponseWithTimeout(
        stream: AsyncThrowingStream<String, Error>,
        timeout: Duration
    ) async -> String {
        let logger = self.logger

        enum CollectionResult {
            case stream(String)
            case timeout
        }

        return await withTaskGroup(of: CollectionResult.self, returning: String.self) { group in
            group.addTask {
                var result = ""
                do {
                    for try await token in stream {
                        try Task.checkCancellation()
                        result += token
                    }
                } catch {
#if DEBUG
                    logger.debug("LLM stream finished with error after \(result.count, privacy: .public) chars: \(error.localizedDescription, privacy: .public)")
#endif
                }
                return .stream(result)
            }

            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timeout
                } catch {
                    return .timeout
                }
            }

            guard let first = await group.next() else { return "" }

            switch first {
            case .stream(let text):
                group.cancelAll()
                while await group.next() != nil {}
                return text
            case .timeout:
#if DEBUG
                logger.debug("LLM stream timed out after \(String(describing: timeout), privacy: .public)")
#endif
                group.cancelAll()
                var partial = ""
                while let next = await group.next() {
                    if case .stream(let text) = next, text.count > partial.count {
                        partial = text
                    }
                }
                return partial
            }
        }
    }

    private func cancelCurrentGenerationTask() {
        generationTask?.cancel()
        generationTask = nil
    }

    private func debugLogModelOutput(rawText: String, parsedSummary: String, parsedAdvices: [String]) {
#if DEBUG
        logger.debug("LLM raw output (\(rawText.count, privacy: .public) chars): \(rawText, privacy: .public)")
        logger.debug("LLM parsed summary (\(parsedSummary.count, privacy: .public) chars): \(parsedSummary, privacy: .public)")
        for (index, advice) in parsedAdvices.enumerated() {
            logger.debug("LLM parsed advice\(index + 1, privacy: .public) (\(advice.count, privacy: .public) chars): \(advice, privacy: .public)")
        }
#endif
    }
}
