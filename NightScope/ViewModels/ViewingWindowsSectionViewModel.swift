import Foundation

/// 観測可能時間帯の文言を整形する ViewModel。
struct ViewingWindowsSectionViewModel {
    // MARK: - Formatting Methods

    /// 開始時刻と終了時刻を 1 行で表示する。
    func windowTimeText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        "\(window.start.nightTimeString(timeZone: timeZone)) 〜 \(window.end.nightTimeString(timeZone: timeZone))"
    }

    /// 最大高度を読みやすい表記へ整形する。
    func altitudeText(_ window: ViewingWindow) -> String {
        L10n.format("最大高度 %.0f°", window.peakAltitude)
    }

    /// 見頃時刻を補足付きで表示する。
    func peakTimeText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        L10n.format("（見頃 %@）", window.peakTime.nightTimeString(timeZone: timeZone))
    }

    /// 時間帯と見頃をまとめて返す。
    func timeAndPeakText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        "\(windowTimeText(window, timeZone: timeZone)) \(peakTimeText(window, timeZone: timeZone))"
    }

    /// 方位を読みやすい文字列へ整形する。
    func directionText(_ window: ViewingWindow) -> String {
        L10n.format("方位 %@", window.peakDirectionName)
    }

    /// `ViewingWindow` 自身の読み上げ文をそのまま使う。
    func accessibilityDescription(for window: ViewingWindow, timeZone: TimeZone) -> String {
        window.accessibilityDescription(timeZone: timeZone)
    }
}
