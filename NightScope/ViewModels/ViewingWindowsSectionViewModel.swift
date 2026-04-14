import Foundation

struct ViewingWindowsSectionViewModel {
    // MARK: - Formatting Methods

    func windowTimeText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        "\(window.start.nightTimeString(timeZone: timeZone)) 〜 \(window.end.nightTimeString(timeZone: timeZone))"
    }

    func altitudeText(_ window: ViewingWindow) -> String {
        String(format: "最大高度 %.0f°", window.peakAltitude)
    }

    func peakTimeText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        "（見頃 \(window.peakTime.nightTimeString(timeZone: timeZone))）"
    }

    func timeAndPeakText(_ window: ViewingWindow, timeZone: TimeZone) -> String {
        "\(windowTimeText(window, timeZone: timeZone)) \(peakTimeText(window, timeZone: timeZone))"
    }

    func directionText(_ window: ViewingWindow) -> String {
        "方位 \(window.peakDirectionName)"
    }

    func accessibilityDescription(for window: ViewingWindow, timeZone: TimeZone) -> String {
        window.accessibilityDescription(timeZone: timeZone)
    }
}
