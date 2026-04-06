import AppKit
import Combine
import Foundation

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
            date: date
        )
        llmService.configure(systemPrompt: systemPrompt)

        guard llmService.isAvailable else {
            applyFallback(nightSummary: nightSummary, starGazingIndex: starGazingIndex, weather: weather, date: date)
            isLoading = false
            return
        }

        let prompt = AssistantContextBuilder.buildCardPrompt(weather: weather)

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
            if !parsed.summary.isEmpty && !parsed.advices.isEmpty {
                summary = parsed.summary
                advices = parsed.advices
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
            nightSummary: nightSummary,
            starGazingIndex: starGazingIndex,
            weather: weather,
            date: date
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

        // バックエンド切替時にモデルラベルを更新
        llmService.$activeKind
            .sink { [weak self] _ in self?.updateModelLabel() }
            .store(in: &cancellables)

        llmService.mlxBackend.$selectedModel
            .sink { [weak self] _ in self?.updateModelLabel() }
            .store(in: &cancellables)
    }

    private func updateModelLabel() {
        modelLabel = llmService.activeModelLabel
    }

    private func collectResponseWithTimeout(
        stream: AsyncThrowingStream<String, Error>,
        timeout: Duration
    ) async -> String {
        do {
            return try await withThrowingTaskGroup(of: String?.self, returning: String.self) { group in
                group.addTask {
                    var result = ""
                    for try await token in stream {
                        try Task.checkCancellation()
                        result += token
                    }
                    return result
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }

                let first = try await group.next() ?? nil
                group.cancelAll()
                while let _ = try await group.next() {}

                return first ?? ""
            }
        } catch {
            return ""
        }
    }

    private func cancelCurrentGenerationTask() {
        generationTask?.cancel()
        generationTask = nil
    }
}
