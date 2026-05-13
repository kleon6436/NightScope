import Foundation
import Combine

@MainActor
final class ObservationAdvisorViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case unavailable
        case loading
        case streaming(String)
        case complete(String)
        case error(String)
    }

    @Published private(set) var state: State

    private let service: any ObservationAdvising
    private var generationTask: Task<Void, Never>?

    init(service: (any ObservationAdvising)? = nil) {
        let resolved = service ?? ObservationAdvisorService()
        self.service = resolved
        self.state = resolved.isAvailable ? .idle : .unavailable
    }

    func generate(input: ObservationAdvisorInput) {
        guard service.isAvailable else {
            cancel()
            state = .unavailable
            return
        }

        generationTask?.cancel()
        state = .loading

        generationTask = Task {
            do {
                let stream = try await service.generateAdvice(for: input)
                let finalText = try await resolveWithTimeout(stream: stream)
                guard !Task.isCancelled else { return }
                if finalText.isEmpty {
                    state = .error(String(localized: "advice.error.generation_failed"))
                } else {
                    state = .complete(finalText)
                }
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        state = service.isAvailable ? .idle : .unavailable
    }

    // Consumes the stream on the main actor (Task inherits @MainActor from generate()).
    // Deadline is checked between token emissions; if the model hangs between tokens
    // the outer generationTask cancellation propagates via Task.checkCancellation().
    private func resolveWithTimeout(stream: AsyncThrowingStream<String, Error>) async throws -> String {
        let deadline = ContinuousClock.now + .seconds(30)
        var latest = ""
        for try await partial in stream {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw ObservationAdvisorTimeoutError() }
            let normalized = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            latest = normalized
            state = .streaming(normalized)
        }
        return Self.normalizeAdviceText(latest)
    }

    static func normalizeAdviceText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let cleaned = lines.compactMap { line -> String? in
            var s = line
            s = s.replacingOccurrences(of: #"^[\s]*[・\-\*•]\s*"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"^\s*\d+[\.．]\s*"#, with: "", options: .regularExpression)
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return cleaned.joined(separator: " ")
    }
}

private struct ObservationAdvisorTimeoutError: LocalizedError {
    var errorDescription: String? {
        String(localized: "advice.error.timeout")
    }
}
