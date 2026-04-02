import Foundation

struct ViewingWindowsSectionViewModel {
    let summary: NightSummary

    // MARK: - Formatting Methods

    func windowTimeText(_ window: ViewingWindow) -> String {
        "\(window.start.nightTimeString()) 〜 \(window.end.nightTimeString())"
    }

    func durationText(_ window: ViewingWindow) -> String {
        String(format: "観測 %.1f時間", window.duration / 3600)
    }

    func altitudeText(_ window: ViewingWindow) -> String {
        String(format: "最大高度 %.0f°", window.peakAltitude)
    }

    func peakTimeText(_ window: ViewingWindow) -> String {
        "見頃 \(window.peakTime.nightTimeString())"
    }

    func moonStatusLabel(for window: ViewingWindow) -> String {
        summary.isMoonFavorable ? "条件良好" : "月明かりあり"
    }

    func accessibilityDescription(for window: ViewingWindow) -> String {
        window.accessibilityDescription(isMoonFavorable: summary.isMoonFavorable)
    }
}
