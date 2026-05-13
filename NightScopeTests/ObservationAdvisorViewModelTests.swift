import XCTest
import Combine
@testable import NightScope

@MainActor
final class ObservationAdvisorViewModelTests: XCTestCase {
    func test_generate_transitionsIdleToLoadingStreamingComplete() async {
        let service = MockObservationAdvisorService(
            streamFactory: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("1. 今夜のまとめ")
                    continuation.yield("1. 今夜のまとめ\n2. 良い点・悪い点")
                    continuation.yield("1. 今夜のまとめ\n2. 良い点・悪い点")
                    continuation.finish()
                }
            }
        )
        let viewModel = ObservationAdvisorViewModel(service: service)
        var states: [ObservationAdvisorViewModel.State] = []
        let cancellable = viewModel.$state.sink { states.append($0) }

        viewModel.generate(input: sampleInput)
        await waitForState(
            .complete("今夜のまとめ 良い点・悪い点"),
            in: viewModel
        )

        XCTAssertEqual(
            viewModel.state,
            .complete("今夜のまとめ 良い点・悪い点")
        )
        XCTAssertTrue(states.contains(.loading))
        XCTAssertTrue(states.contains {
            if case .streaming = $0 { return true }
            return false
        })
        cancellable.cancel()
    }

    func test_cancel_midStream_returnsToIdle() async {
        let service = MockObservationAdvisorService(
            streamFactory: { service in
                AsyncThrowingStream { continuation in
                    continuation.yield("1. 今夜のまとめ")
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        continuation.yield("1. 今夜のまとめ\n2. 良い点")
                        continuation.finish()
                    }
                    continuation.onTermination = { termination in
                        guard case .cancelled = termination else { return }
                        Task { @MainActor in
                            service.cancelledCount += 1
                        }
                    }
                }
            }
        )
        let viewModel = ObservationAdvisorViewModel(service: service)

        viewModel.generate(input: sampleInput)
        await waitForStreamingState(in: viewModel)
        viewModel.cancel()
        await waitForState(.idle, in: viewModel)

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertGreaterThanOrEqual(service.cancelledCount, 1)
    }

    func test_unavailableService_setsUnavailableImmediately() {
        let viewModel = ObservationAdvisorViewModel(
            service: MockObservationAdvisorService(isAvailable: false)
        )

        XCTAssertEqual(viewModel.state, .unavailable)
        viewModel.generate(input: sampleInput)
        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func test_errorPropagation_setsErrorState() async {
        let viewModel = ObservationAdvisorViewModel(
            service: MockObservationAdvisorService(error: MockObservationAdvisorError.failed)
        )

        viewModel.generate(input: sampleInput)
        await waitForState(
            .error(MockObservationAdvisorError.failed.localizedDescription),
            in: viewModel
        )

        XCTAssertEqual(viewModel.state, .error(MockObservationAdvisorError.failed.localizedDescription))
    }

    func test_normalizeAdviceText_removesJapaneseBulletListMarkers() {
        let input = "・今夜は雲が少なく観測しやすいです\n・月明かりの影響は後半に弱まります"

        let result = ObservationAdvisorViewModel.normalizeAdviceText(input)

        XCTAssertEqual(result, "今夜は雲が少なく観測しやすいです 月明かりの影響は後半に弱まります")
    }

    func test_normalizeAdviceText_removesHyphenListMarkers() {
        let input = "- 今夜は透明度が安定しています\n- 風も弱めです"

        let result = ObservationAdvisorViewModel.normalizeAdviceText(input)

        XCTAssertEqual(result, "今夜は透明度が安定しています 風も弱めです")
    }

    func test_normalizeAdviceText_removesNumberedListMarkers() {
        let input = "1. 今夜は前半が見やすいです\n2. 後半は薄雲に注意です"

        let result = ObservationAdvisorViewModel.normalizeAdviceText(input)

        XCTAssertEqual(result, "今夜は前半が見やすいです 後半は薄雲に注意です")
    }

    func test_normalizeAdviceText_preservesProse() {
        let input = "今夜は雲の切れ間があり、前半ほど観測しやすいでしょう。"

        let result = ObservationAdvisorViewModel.normalizeAdviceText(input)

        XCTAssertEqual(result, input)
    }

    private func waitForState(
        _ expected: ObservationAdvisorViewModel.State,
        in viewModel: ObservationAdvisorViewModel,
        timeout: TimeInterval = 1.0
    ) async {
        let expectation = expectation(description: "state becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$state.sink { state in
            guard state == expected else { return }
            expectation.fulfill()
            cancellable?.cancel()
        }

        await fulfillment(of: [expectation], timeout: timeout)
        cancellable?.cancel()
    }

    private func waitForStreamingState(
        in viewModel: ObservationAdvisorViewModel,
        timeout: TimeInterval = 1.0
    ) async {
        let expectation = expectation(description: "state becomes streaming")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$state.sink { state in
            guard case .streaming = state else { return }
            expectation.fulfill()
            cancellable?.cancel()
        }

        await fulfillment(of: [expectation], timeout: timeout)
        cancellable?.cancel()
    }
}

private let sampleInput = ObservationAdvisorInput(
    language: "ja",
    isUnfavorable: false,
    dateString: "2026年5月13日（水）",
    locationName: "長野県 乗鞍高原",
    tierLabel: "良好",
    viewingWindowSummary: "22:15〜03:30（5時間15分）、見頃：00:45ごろ",
    moonSummary: "上弦の月（照度32%、23:10に沈む）",
    weatherSummary: "薄曇り、雲量35%、透明度良好、風速2m/s",
    lightPollutionSummary: "郊外の空（天の川は肉眼でうっすら見える）"
)

@MainActor
private final class MockObservationAdvisorService: ObservationAdvising {
    var isAvailable: Bool = true
    var error: (any Error & Sendable)?
    var cancelledCount = 0
    var streamFactory: @MainActor (MockObservationAdvisorService) -> AsyncThrowingStream<String, Error> = { _ in
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    init(
        isAvailable: Bool = true,
        error: (any Error & Sendable)? = nil,
        streamFactory: @escaping @MainActor (MockObservationAdvisorService) -> AsyncThrowingStream<String, Error> = { _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    ) {
        self.isAvailable = isAvailable
        self.error = error
        self.streamFactory = streamFactory
    }

    func generateAdvice(for input: ObservationAdvisorInput) async throws -> AsyncThrowingStream<String, Error> {
        if let error {
            throw error
        }
        return streamFactory(self)
    }
}

private enum MockObservationAdvisorError: LocalizedError, Sendable {
    case failed

    var errorDescription: String? {
        "生成に失敗しました。"
    }
}
