import Foundation
import Combine

/// アプリ終了シーケンスと推論キャンセル処理を仲介する軽量コーディネーター。
///
/// `AppDelegate.applicationShouldTerminate(_:)` の終了状態機械
/// (`idle/preparing/replied`) と組み合わせ、
/// バックグラウンドスレッドでの DispatchGroup.wait() 完了後に
/// `NSApp.reply(toApplicationShouldTerminate: true)` を 1 回だけ呼ぶことで、
/// MLX C++ forward pass が解放済みメモリにアクセスする
/// `__next_prime overflow` クラッシュを防ぐ。
///
/// この型は「終了時に実行すべきハンドラの登録/回収」のみを担当し、
/// 推論停止の具体処理は `LLMService` など各責務側へ委譲する。
@MainActor
final class AppTerminationCoordinator: ObservableObject {

    // MARK: - Shared

    static let shared = AppTerminationCoordinator()
    private init() {}

    // MARK: - Types

    typealias TerminationHandler = () async -> Void

    // MARK: - Handler

    /// 終了待機中かどうか（UI 表示用）。
    @Published private(set) var isPreparingForTermination = false

    /// 終了直前に await するハンドラ群。
    private var handlers: [UUID: TerminationHandler] = [:]

    /// 終了ハンドラを登録する。
    /// - Parameter handler: 終了直前に実行する非同期ハンドラ
    /// - Returns: 解除に使う識別子
    @discardableResult
    func registerHandler(_ handler: @escaping TerminationHandler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    /// 終了ハンドラを解除する。
    /// - Parameter id: `registerHandler(_:)` が返した識別子
    func unregisterHandler(id: UUID) {
        handlers.removeValue(forKey: id)
    }

    /// 終了ハンドラを取得し、重複実行を防ぐために内部状態を空にする。
    /// - Returns: 実行対象の終了ハンドラ配列
    func consumeHandlers() -> [TerminationHandler] {
        let registeredHandlers = Array(handlers.values)
        handlers.removeAll()
        return registeredHandlers
    }

    /// 終了待機 UI を開始する。
    func markPreparingForTermination() {
        isPreparingForTermination = true
    }

    /// 終了待機 UI を終了する。
    func markFinishedTermination() {
        isPreparingForTermination = false
    }
}
