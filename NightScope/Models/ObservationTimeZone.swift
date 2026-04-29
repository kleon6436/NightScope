import Foundation

/// 日付境界をタイムゾーン固定で扱うためのカレンダーヘルパー。
enum ObservationTimeZone {
    /// 指定タイムゾーンに固定した Gregorian カレンダーを返す。
    static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 指定タイムゾーンでの日付開始時刻を返す。
    static func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
        gregorianCalendar(timeZone: timeZone).startOfDay(for: date)
    }

    /// 同一タイムゾーン基準で日付が同じかを判定する。
    static func isDate(_ lhs: Date, inSameDayAs rhs: Date, timeZone: TimeZone) -> Bool {
        gregorianCalendar(timeZone: timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    /// 参照日時に対して「今日」と同じ日付かを判定する。
    static func isDateInToday(_ date: Date, timeZone: TimeZone, referenceDate: Date = Date()) -> Bool {
        isDate(date, inSameDayAs: referenceDate, timeZone: timeZone)
    }

    /// 指定タイムゾーンの Gregorian カレンダーで日付加算する。
    static func date(byAdding component: Calendar.Component, value: Int, to date: Date, timeZone: TimeZone) -> Date? {
        gregorianCalendar(timeZone: timeZone).date(byAdding: component, value: value, to: date)
    }

    /// 日付の年月日だけを別タイムゾーンへ写し替える。
    static func preservingCalendarDay(_ date: Date, from sourceTimeZone: TimeZone, to destinationTimeZone: TimeZone) -> Date {
        let sourceCalendar = gregorianCalendar(timeZone: sourceTimeZone)
        let destinationCalendar = gregorianCalendar(timeZone: destinationTimeZone)
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
        let destinationDate = destinationCalendar.date(from: components) ?? date
        return destinationCalendar.startOfDay(for: destinationDate)
    }
}
