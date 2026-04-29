import Foundation
import CoreLocation

/// 星空マップで使う夜間時刻の変換ロジックをまとめる。
enum StarMapDateLogic {
    /// 夜間スライダー用の夜間範囲。
    struct NightRange {
        let startMinutes: Double
        let durationMinutes: Double
    }

    /// 日時をタイムゾーン基準の 0-1439 分へ変換する。
    static func clockMinutes(for date: Date, timeZone: TimeZone) -> Double {
        let components = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
            .dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    /// 2 つの日時が同じ暦日かをタイムゾーン込みで判定する。
    static func isSameCalendarDay(_ lhs: Date, _ rhs: Date, timeZone: TimeZone) -> Bool {
        ObservationTimeZone.gregorianCalendar(timeZone: timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    /// 夜間開始時刻からのオフセットを、実際の時刻へ戻す。
    static func nightOffsetToRealMinutes(_ offset: Double, nightStartMinutes: Double) -> Double {
        let real = nightStartMinutes + offset
        return real.truncatingRemainder(dividingBy: 1_440)
    }

    /// 夜間スライダーで選べる最大オフセットを返す。
    static func maxSelectableNightOffset(nightDurationMinutes: Double) -> Double {
        max(0, min(nightDurationMinutes, 1_439))
    }

    /// 実時刻を夜間開始からのオフセットへ正規化する。
    static func realMinutesToNightOffset(
        _ realMinutes: Double,
        nightStartMinutes: Double,
        nightDurationMinutes: Double
    ) -> Double {
        var offset = realMinutes - nightStartMinutes
        if offset < 0 { offset += 1_440 }
        return max(0, min(maxSelectableNightOffset(nightDurationMinutes: nightDurationMinutes), offset))
    }

    /// 日没・日出から、その日の観測用夜間範囲を算出する。
    static func nightRange(
        for date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone,
        referenceDate: Date? = nil,
        fallback: NightRange
    ) -> NightRange {
        guard let interval = MilkyWayCalculator.sunsetSunriseInterval(
            date: date,
            location: location,
            timeZone: timeZone
        ) else {
            let startMinutes = referenceDate.map { clockMinutes(for: $0, timeZone: timeZone) } ?? fallback.startMinutes
            return NightRange(startMinutes: startMinutes, durationMinutes: 0)
        }

        let startOfDay = ObservationTimeZone.startOfDay(for: date, timeZone: timeZone)
        let startMinutes = interval.start.timeIntervalSince(startOfDay).truncatingRemainder(dividingBy: 1_440 * 60) / 60
        let duration = min(1_440, max(0, interval.duration / 60))

        return NightRange(
            startMinutes: startMinutes,
            durationMinutes: duration
        )
    }

    /// 表示用の日付を、観測日に属する実日付へ変換する。
    static func observationDate(
        for presentationDate: Date,
        timeZone: TimeZone,
        nightStartMinutes: Double
    ) -> Date {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let startOfDay = calendar.startOfDay(for: presentationDate)
        let clockMinutes = self.clockMinutes(for: presentationDate, timeZone: timeZone)
        guard clockMinutes < nightStartMinutes else {
            return startOfDay
        }
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
    }

    /// 選択日と参照時刻から、表示に使う日時を解決する。
    static func resolvedPresentationDate(
        for selectedDate: Date,
        referenceDate: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        guard let twilight = MilkyWayCalculator.findSunsetSunriseMinutes(
            date: selectedDate,
            location: location,
            timeZone: timeZone
        ) else {
            return date(byApplyingTimeOf: referenceDate, to: selectedDate, timeZone: timeZone)
        }

        let referenceMinutes = clockMinutes(for: referenceDate, timeZone: timeZone)
        if isWithinNightRange(
            referenceMinutes,
            eveningMinutes: twilight.sunsetMinutes,
            morningMinutes: twilight.sunriseMinutes
        ) {
            return date(
                bySettingClockMinutes: referenceMinutes,
                onObservationDate: selectedDate,
                timeZone: timeZone,
                nightStartMinutes: twilight.sunsetMinutes
            )
        }

        return date(
            bySettingClockMinutes: twilight.sunsetMinutes,
            onObservationDate: selectedDate,
            timeZone: timeZone,
            nightStartMinutes: twilight.sunsetMinutes
        )
    }

    /// 分単位の時刻を、指定日の Date として組み立てる。
    static func date(bySettingClockMinutes minutes: Double, on date: Date, timeZone: TimeZone) -> Date? {
        let normalizedMinutes = ((Int(minutes.rounded()) % 1_440) + 1_440) % 1_440
        return ObservationTimeZone.gregorianCalendar(timeZone: timeZone).date(
            bySettingHour: normalizedMinutes / 60,
            minute: normalizedMinutes % 60,
            second: 0,
            of: date
        )
    }

    /// 夜間スライダーの観測日をまたぐ時刻補正を加味して Date を返す。
    static func date(
        bySettingClockMinutes minutes: Double,
        onObservationDate observationDate: Date,
        timeZone: TimeZone,
        nightStartMinutes: Double
    ) -> Date? {
        let normalizedMinutes = ((Int(minutes.rounded()) % 1_440) + 1_440) % 1_440
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let dayOffset = Double(normalizedMinutes) < nightStartMinutes ? 1 : 0
        let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: observationDate) ?? observationDate
        return calendar.date(
            bySettingHour: normalizedMinutes / 60,
            minute: normalizedMinutes % 60,
            second: 0,
            of: baseDate
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
