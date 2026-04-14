import Foundation
import CoreLocation

enum StarMapDateLogic {
    struct NightRange {
        let startMinutes: Double
        let durationMinutes: Double
    }

    static func clockMinutes(for date: Date, timeZone: TimeZone) -> Double {
        let components = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
            .dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    static func isSameCalendarDay(_ lhs: Date, _ rhs: Date, timeZone: TimeZone) -> Bool {
        ObservationTimeZone.gregorianCalendar(timeZone: timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    static func nightOffsetToRealMinutes(_ offset: Double, nightStartMinutes: Double) -> Double {
        let real = nightStartMinutes + offset
        return real.truncatingRemainder(dividingBy: 1_440)
    }

    static func realMinutesToNightOffset(
        _ realMinutes: Double,
        nightStartMinutes: Double,
        nightDurationMinutes: Double
    ) -> Double {
        var offset = realMinutes - nightStartMinutes
        if offset < 0 { offset += 1_440 }
        return max(0, min(nightDurationMinutes, offset))
    }

    static func nightRange(
        for date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone,
        fallback: NightRange
    ) -> NightRange {
        guard let twilight = MilkyWayCalculator.findCivilTwilightMinutes(
            date: date,
            location: location,
            timeZone: timeZone
        ) else {
            return fallback
        }

        var duration = twilight.morningMinutes - twilight.eveningMinutes
        if duration < 0 { duration += 1_440 }

        return NightRange(
            startMinutes: twilight.eveningMinutes,
            durationMinutes: max(60, duration)
        )
    }

    static func resolvedPresentationDate(
        for selectedDate: Date,
        referenceDate: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        guard let candidate = date(byApplyingTimeOf: referenceDate, to: selectedDate, timeZone: timeZone) else {
            return nil
        }

        guard let twilight = MilkyWayCalculator.findCivilTwilightMinutes(
            date: selectedDate,
            location: location,
            timeZone: timeZone
        ) else {
            return candidate
        }

        let candidateMinutes = clockMinutes(for: candidate, timeZone: timeZone)
        if isWithinNightRange(
            candidateMinutes,
            eveningMinutes: twilight.eveningMinutes,
            morningMinutes: twilight.morningMinutes
        ) {
            return candidate
        }

        return date(bySettingClockMinutes: twilight.eveningMinutes, on: selectedDate, timeZone: timeZone)
    }

    static func date(bySettingClockMinutes minutes: Double, on date: Date, timeZone: TimeZone) -> Date? {
        let normalizedMinutes = ((Int(minutes.rounded()) % 1_440) + 1_440) % 1_440
        return ObservationTimeZone.gregorianCalendar(timeZone: timeZone).date(
            bySettingHour: normalizedMinutes / 60,
            minute: normalizedMinutes % 60,
            second: 0,
            of: date
        )
    }

    private static func isWithinNightRange(
        _ clockMinutes: Double,
        eveningMinutes: Double,
        morningMinutes: Double
    ) -> Bool {
        if eveningMinutes <= morningMinutes {
            return clockMinutes >= eveningMinutes && clockMinutes < morningMinutes
        }

        return clockMinutes >= eveningMinutes || clockMinutes < morningMinutes
    }

    private static func date(byApplyingTimeOf referenceDate: Date, to date: Date, timeZone: TimeZone) -> Date? {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let time = calendar.dateComponents([.hour, .minute], from: referenceDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        )
    }
}
