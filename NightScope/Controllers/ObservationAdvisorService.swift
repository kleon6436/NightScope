import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol ObservationAdvising: Sendable {
    var isAvailable: Bool { get }
    func generateAdvice(for input: ObservationAdvisorInput) async throws -> AsyncThrowingStream<String, Error>
}

enum ObservationAdvisorServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "advice.error.unavailable")
        }
    }
}

@MainActor
final class ObservationAdvisorService: ObservationAdvising {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func generateAdvice(for input: ObservationAdvisorInput) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else {
            throw ObservationAdvisorServiceError.unavailable
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let prompt = makePrompt(for: input)
            return AsyncThrowingStream { continuation in
                let task = Task { @MainActor [weak self] in
                    do {
                        guard let self else {
                            throw CancellationError()
                        }

                        let session = self.makeSession(language: input.language)
                        let stream = session.streamResponse(to: prompt)
                        for try await snapshot in stream {
                            try Task.checkCancellation()
                            // FoundationModels streams cumulative snapshots: snapshot.content is the full text so far, not a delta.
                            continuation.yield(snapshot.content)
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        #endif

        throw ObservationAdvisorServiceError.unavailable
    }

    private func makePrompt(for input: ObservationAdvisorInput) -> String {
        if input.language == "en" {
            return makeEnglishPrompt(for: input)
        }

        let tierInstruction = input.isUnfavorable
            ? "【出力指示】条件が悪い理由のみ説明すること。観測の推奨・代替行動の提案は一切しないこと。"
            : "【出力指示】条件の説明と、あれば観察のポイントを述べること。"

        return """
        観測日: \(input.dateString)
        観測地: \(input.locationName)
        総合評価: \(input.tierLabel)
        \(tierInstruction)
        見頃: \(input.viewingWindowSummary)
        月: \(input.moonSummary)
        天気: \(input.weatherSummary)
        光害: \(input.lightPollutionSummary)
        """
    }

    private func makeEnglishPrompt(for input: ObservationAdvisorInput) -> String {
        let tierInstruction = input.isUnfavorable
            ? "[Output instruction] Explain only why the conditions are poor. Do not recommend observing or suggest alternatives."
            : "[Output instruction] Explain the conditions and, if relevant, mention what beginners should pay attention to."

        return """
        Observation date: \(input.dateString)
        Location: \(input.locationName)
        Overall rating: \(input.tierLabel)
        \(tierInstruction)
        Viewing window: \(input.viewingWindowSummary)
        Moon: \(input.moonSummary)
        Weather: \(input.weatherSummary)
        Light pollution: \(input.lightPollutionSummary)
        """
    }

    private static func systemPrompt(language: String) -> String {
        if language == "en" {
            return """
            You are a stargazing guide.
            All of the following data has already been calculated. Your role is only to explain the results in plain English for beginners.

            Constraints (strictly follow):
            - Do not perform any new calculations, predictions, or evaluations
            - Do not estimate weather or celestial positions
            - Do not output numeric values (scores, Bortle class, temperature, illumination, altitude, azimuth, etc.) in the prose
            - Do not suggest alternatives that are not included in the input data, such as moving locations, observing indoors, or trying another day
            - Stargazing assumes outdoor observation
            - If the conditions are poor, explain only why they are poor. Do not encourage observing

            Output format:
            - Write only in prose. Do not use bullet points, lists, symbols, or numbered items
            - Summarize tonight's conditions in 1 to 3 concise sentences for beginners
            - For "Poor" or "Very Poor": explain only why the conditions are unfavorable. No advice is needed
            - For "Fair" or better: you may add a simple observation tip
            - Use complete sentences in a friendly, informative tone
            """
        }

        return """
        あなたは星空観察の案内人です。
        以下のデータはすべて事前に計算済みです。あなたの役割は、これらの結果を初心者にわかりやすく日本語で説明することだけです。

        制約（厳守）:
        - 新たな計算・予測・評価を行わないこと
        - 気象予報・天体位置の推定を行わないこと
        - 数値（スコア・Bortleクラス・気温・照度・高度・方位など）は本文中に出力しないこと
        - 室内での観測、場所の移動、別の日への変更など、入力データに含まれない代替行動を提案しないこと
        - 星空観察は屋外での観察が前提であること
        - 悪条件（観測困難・不向き）の場合は、その理由を説明するにとどめること。観測を勧めないこと

        出力形式:
        - 必ず文章（散文）で書くこと。箇条書き・リスト・記号（「・」「-」「•」数字付きリストなど）は一切使用しないこと
        - 今夜の状況を1〜3文で簡潔に述べること（初心者向け）
        - 文体は必ずですます調（〜です、〜ます、〜でしょう等）で統一すること。体言止め・名詞止めは使わないこと。例：「今夜は雲が多く、星はほとんど見えないでしょう。」のように必ず述語で文を終えること
        - 「観測困難」または「不向き」の場合: 条件が悪い理由を説明するだけでよい。アドバイスは不要
        - 「普通」以上の場合: 条件の説明に加え、観察のポイントを述べてよい
        """
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
private extension ObservationAdvisorService {
    func makeSession(language: String) -> LanguageModelSession {
        LanguageModelSession(
            model: .default,
            instructions: Self.systemPrompt(language: language)
        )
    }
}
#endif
