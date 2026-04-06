import SwiftUI
import AppKit

// MARK: - Commands

struct NightScopeCommands: Commands {
    @FocusedBinding(\.selectedDate) private var selectedDate: Date?
    @FocusedValue(\.refreshAction) private var refreshAction: (() -> Void)?
    @FocusedValue(\.focusSearchAction) private var focusSearchAction: (() -> Void)?
    @FocusedValue(\.currentLocationAction) private var currentLocationAction: (() -> Void)?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("NightScope について") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandGroup(after: .sidebar) {
            Button("前日") {
                if let date = selectedDate {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: date)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(selectedDate == nil)

            Button("翌日") {
                if let date = selectedDate {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: date)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(selectedDate == nil)

            Divider()

            Button("前の月") {
                if let date = selectedDate {
                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: date)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(selectedDate == nil)

            Button("次の月") {
                if let date = selectedDate {
                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: date)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(selectedDate == nil)

            Divider()

            Button("今日に移動") {
                selectedDate = Date()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(selectedDate == nil)

            Divider()

            Button("場所を検索") {
                focusSearchAction?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(focusSearchAction == nil)

            Button("現在地を使用") {
                currentLocationAction?()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(currentLocationAction == nil)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("データを更新") {
                refreshAction?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshAction == nil)
        }
    }
}

// MARK: - App Delegate

/// アプリ終了シーケンスを制御する AppDelegate。
///
/// ## 設計方針
/// - `.terminateLater` を返し、バックグラウンドスレッドで DispatchGroup.wait() する。
/// - メインスレッドをブロックしないため RunLoop が通常通り動作し、
///   AppKit/SwiftUI の再入によるクラッシュを防ぐ。
/// - 終了状態を `idle/preparing/replied` の状態機械で管理し、
///   AppKit 再呼び出し時の二重フロー・二重 reply を防ぐ。
/// - バックグラウンドスレッドが wait → `DispatchQueue.main.async` で
///   `NSApp.reply(true)` を呼ぶことで AppKit の正規終了フローを維持する。
/// - この型は「終了オーケストレーション」専任。推論停止の実処理は
///   `AppTerminationCoordinator` に登録された各ハンドラへ委譲する。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private typealias TerminationHandler = AppTerminationCoordinator.TerminationHandler

    private enum TerminationPhase {
        case idle
        case preparing
        case replied
    }

    private var terminationPhase: TerminationPhase = .idle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch terminationPhase {
        case .preparing:
            // 終了準備中の再呼び出しは同一フローに合流する。
            return .terminateLater
        case .replied:
            // reply 済み後の再呼び出しは即終了させる。
            return .terminateNow
        case .idle:
            break
        }

        let coordinator = AppTerminationCoordinator.shared
        let handlers = coordinator.consumeHandlers()
        guard !handlers.isEmpty else {
            return .terminateNow
        }

        coordinator.markPreparingForTermination()
        terminationPhase = .preparing

        // 安全停止を優先し、終了ハンドラが完了するまで await する。
        // これにより、推論タスクが生きたままプロセス終了へ進む経路を防ぐ。
        Task { @MainActor in
            await executeTerminationHandlers(handlers)
            guard self.terminationPhase == .preparing else { return }
            coordinator.markFinishedTermination()
            self.terminationPhase = .replied
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    private func executeTerminationHandlers(_ handlers: [TerminationHandler]) async {
        await withTaskGroup(of: Void.self) { group in
            for handler in handlers {
                group.addTask {
                    await handler()
                }
            }
            await group.waitForAll()
        }
    }
}

// MARK: - App

@main
struct NightScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appController = AppController()

    var body: some Scene {
        WindowGroup {
            ContentView(appController: appController)
                .environmentObject(appController)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            NightScopeCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appController)
        }
    }
}
