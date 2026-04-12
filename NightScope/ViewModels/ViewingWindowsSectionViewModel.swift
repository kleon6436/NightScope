import Foundation

struct ViewingWindowsSectionViewModel {
    // MARK: - Formatting Methods

    func windowTimeText(_ window: ViewingWindow) -> String {
        "\(window.start.nightTimeString()) 〜 \(window.end.nightTimeString())"
    }

    func altitudeText(_ window: ViewingWindow) -> String {
        String(format: "最大高度 %.0f°", window.peakAltitude)
    }

    func peakTimeText(_ window: ViewingWindow) -> String {
        "（見頃 \(window.peakTime.nightTimeString())）"
    }

    func timeAndPeakText(_ window: ViewingWindow) -> String {
        "\(windowTimeText(window)) \(peakTimeText(window))"
    }

    func directionText(_ window: ViewingWindow) -> String {
        "方位 \(window.peakDirectionName)"
    }

    func accessibilityDescription(for window: ViewingWindow) -> String {
        window.accessibilityDescription()
    }
}
