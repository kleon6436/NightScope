import Foundation

enum StarMapUpdatePolicy {
    static let minUpdateInterval: TimeInterval = 1.0 / 30
    static let minScrubbingUpdateInterval: TimeInterval = 1.0 / 20
    static let timeSliderCommitInterval: TimeInterval = 1.0 / 20

    static func trailingDelay(
        now: TimeInterval,
        lastUpdateTime: TimeInterval,
        isScrubbing: Bool
    ) -> TimeInterval? {
        let interval = isScrubbing ? minScrubbingUpdateInterval : minUpdateInterval
        let elapsed = now - lastUpdateTime
        guard elapsed < interval else { return nil }
        return interval - elapsed
    }

    static func commitDelay(now: TimeInterval, lastCommitTime: TimeInterval) -> TimeInterval? {
        let elapsed = now - lastCommitTime
        guard elapsed < timeSliderCommitInterval else { return nil }
        return timeSliderCommitInterval - elapsed
    }
}

enum StarMapTimelinePolicy {
    enum DisplayDateUpdateMode {
        case standard
        case preserveNightRangeAndSlider

        var preservesNightRangeAndSlider: Bool {
            self == .preserveNightRangeAndSlider
        }
    }

    static func updateMode(
        skipNightRange: Bool,
        skipTimeSliderSync: Bool
    ) -> DisplayDateUpdateMode {
        (skipNightRange || skipTimeSliderSync) ? .preserveNightRangeAndSlider : .standard
    }

    static func clampedSliderMinutes(_ minutes: Double, nightDurationMinutes: Double) -> Double {
        max(0, min(nightDurationMinutes, minutes.rounded()))
    }

    static func shouldApplySliderChange(
        currentMinutes: Double,
        newMinutes: Double,
        tolerance: Double = 0.5
    ) -> Bool {
        abs(currentMinutes - newMinutes) > tolerance
    }

    static func sliderOffset(
        for displayDate: Date,
        nightStartMinutes: Double,
        nightDurationMinutes: Double
    ) -> Double {
        let realMinutes = StarMapDateLogic.clockMinutes(for: displayDate)
        return StarMapDateLogic.realMinutesToNightOffset(
            realMinutes,
            nightStartMinutes: nightStartMinutes,
            nightDurationMinutes: nightDurationMinutes
        )
    }

    static func displayDate(
        for sliderMinutes: Double,
        nightStartMinutes: Double,
        baseDate: Date
    ) -> Date? {
        let realMinutes = StarMapDateLogic.nightOffsetToRealMinutes(
            sliderMinutes,
            nightStartMinutes: nightStartMinutes
        )
        return StarMapDateLogic.date(bySettingClockMinutes: realMinutes, on: baseDate)
    }

    static func shouldUpdateNightRange(
        from oldDate: Date,
        to newDate: Date,
        updateMode: DisplayDateUpdateMode
    ) -> Bool {
        guard !updateMode.preservesNightRangeAndSlider else { return false }
        return !StarMapDateLogic.isSameCalendarDay(oldDate, newDate)
    }

    static func shouldSyncTimeSlider(updateMode: DisplayDateUpdateMode) -> Bool {
        !updateMode.preservesNightRangeAndSlider
    }
}
