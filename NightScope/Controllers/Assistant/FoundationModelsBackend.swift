import Foundation
import FoundationModels

/// Apple Intelligence（FoundationModels）を使ったバックエンド実装
@MainActor
final class FoundationModelsBackend: LLMBackend {

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

    var kind: LLMBackendKind { .appleIntelligence }

    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default:         return false
        }
    }

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "このデバイスは Apple Intelligence に対応していません"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence が有効になっていません（設定 › Apple Intelligence & Siri）"
            case .modelNotReady:
                return "Apple Intelligence のモデルをダウンロード中です"
            @unknown default:
                return "Apple Intelligence を利用できません"
            }
        }
    }

    // MARK: - Private

    private var session: LanguageModelSession?
    private var currentSystemPrompt: String = ""
    private var activeInferenceTask: Task<Void, Never>?
    private var activeInferenceTaskID: UUID?
    private var isTerminationModeEnabled = false

    // MARK: - LLMBackend Methods

    func beginTerminationMode() {
        isTerminationModeEnabled = true
    }

    func resetSession(systemPrompt: String) {
        if isTerminationModeEnabled {
            currentSystemPrompt = systemPrompt
            return
        }

        activeInferenceTask?.cancel()
        activeInferenceTask = nil
        activeInferenceTaskID = nil
        currentSystemPrompt = systemPrompt
        session = LanguageModelSession(instructions: systemPrompt)
    }

    func cancelInference() async {
        activeInferenceTask?.cancel()
        activeInferenceTask = nil
        activeInferenceTaskID = nil
    }

    func send(userMessage: String) -> AsyncThrowingStream<String, Error> {
        if isTerminationModeEnabled {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CancellationError())
            }
        }

        // LLMService.send() → この関数は MainActor 上から呼ばれる。
        // セッションを Task 外で同期的にキャプチャしないと、
        // resetSession() が先に呼ばれた場合に別日付のセッションを取得してしまい
        // 会話履歴が汚染され、前の日付の情報が混入する。
        let capturedSession: LanguageModelSession
        if let existing = session {
            capturedSession = existing
        } else {
            let newSession = LanguageModelSession(instructions: currentSystemPrompt.isEmpty ? nil : currentSystemPrompt)
            session = newSession
            capturedSession = newSession
        }

        return AsyncThrowingStream { continuation in
            activeInferenceTask?.cancel()
            let taskID = UUID()
            let terminationGate = StreamTerminationGate()
            let task = Task {
                defer {
                    Task { @MainActor [weak self] in
                        self?.clearInferenceTaskIfMatched(taskID)
                    }
                }

                do {
                    // partial.content は [Character]（累積テキスト）なので差分を抽出して yield する
                    var previousLength = 0
                    let stream = capturedSession.streamResponse(to: userMessage)
                    for try await partial in stream {
                        try Task.checkCancellation()
                        guard await terminationGate.canEmit() else { break }
                        let fullText = String(partial.content)
                        let delta = String(fullText.dropFirst(previousLength))
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        previousLength = fullText.count
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
            activeInferenceTask = task
            activeInferenceTaskID = taskID
            // ストリームの消費側が終了（break / キャンセル）したとき推論タスクも停止する
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    self?.clearInferenceTaskIfMatched(taskID)
                }
                Task {
                    await terminationGate.markTerminated()
                }
            }
        }
    }

    // MARK: - Private

    private func clearInferenceTaskIfMatched(_ taskID: UUID) {
        guard activeInferenceTaskID == taskID else { return }
        activeInferenceTask = nil
        activeInferenceTaskID = nil
    }
}
