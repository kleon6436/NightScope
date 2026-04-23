import SwiftUI
import AppKit

// MARK: - Commands

struct NightScopeCommands: Commands {
    @FocusedBinding(\.selectedDate) private var selectedDate: Date?
    @FocusedValue(\.observationTimeZone) private var observationTimeZone: TimeZone?
    @FocusedValue(\.refreshAction) private var refreshAction: (() -> Void)?
    @FocusedValue(\.focusSearchAction) private var focusSearchAction: (() -> Void)?
    @FocusedValue(\.currentLocationAction) private var currentLocationAction: (() -> Void)?

    private var observationCalendar: Calendar {
        ObservationTimeZone.gregorianCalendar(timeZone: observationTimeZone ?? .current)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("NightScope について") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandGroup(after: .sidebar) {
            Button("前日") {
                if let date = selectedDate {
                    selectedDate = observationCalendar.date(byAdding: .day, value: -1, to: date)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(selectedDate == nil)

            Button("翌日") {
                if let date = selectedDate {
                    selectedDate = observationCalendar.date(byAdding: .day, value: 1, to: date)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(selectedDate == nil)

            Divider()

            Button("前の月") {
                if let date = selectedDate {
                    selectedDate = observationCalendar.date(byAdding: .month, value: -1, to: date)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(selectedDate == nil)

            Button("次の月") {
                if let date = selectedDate {
                    selectedDate = observationCalendar.date(byAdding: .month, value: 1, to: date)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(selectedDate == nil)

            Divider()

            Button("今日に移動") {
                selectedDate = observationCalendar.startOfDay(for: Date())
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

// MARK: - App

@main
struct NightScopeApp: App {
    @StateObject private var weatherAttributionService = WeatherAttributionService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(weatherAttributionService)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            NightScopeCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(weatherAttributionService)
        }
    }
}
