import Foundation

// MARK: - Protocol

@MainActor
protocol LLMBackend: AnyObject {
    var isAvailable: Bool { get }
    var kind: LLMBackendKind { get }

    /// 新しいセッションを開始する（コンテキスト変更時に呼ぶ）
    func resetSession(systemPrompt: String)

    /// メッセージを送信しトークンを AsyncThrowingStream で返す
    func send(userMessage: String) -> AsyncThrowingStream<String, Error>

    /// 実行中の推論を停止する
    func cancelInference() async
}

// MARK: - Backend Kind

enum LLMBackendKind: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple_intelligence"
    case mlx = "mlx"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .mlx:               return "ローカル LLM (MLX)"
        }
    }
}

// MARK: - MLX Model Spec

struct MLXModelSpec: Identifiable {
    /// Hugging Face リポジトリ ID（例: "mlx-community/gemma-4-e4b-4bit"）
    let id: String
    let displayName: String
    /// ダウンロードサイズ目安（GB）
    let sizeGB: Double
    /// 推奨最小搭載 RAM（GB）
    let minRAMGB: Int

    /// アプリが標準で提供するモデル一覧
    static let builtinModels: [MLXModelSpec] = [
        MLXModelSpec(
            id: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B（推奨）",
            sizeGB: 2.3,
            minRAMGB: 8
        ),
        MLXModelSpec(
            id: "mlx-community/gemma-3-1b-it-4bit",
            displayName: "Gemma 3 1B（軽量）",
            sizeGB: 0.7,
            minRAMGB: 4
        ),
        MLXModelSpec(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B（多言語）",
            sizeGB: 2.4,
            minRAMGB: 8
        ),
    ]
}
