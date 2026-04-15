import Foundation

enum ObservationTimeZone {
    static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
        gregorianCalendar(timeZone: timeZone).startOfDay(for: date)
    }

    static func isDate(_ lhs: Date, inSameDayAs rhs: Date, timeZone: TimeZone) -> Bool {
        gregorianCalendar(timeZone: timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    static func isDateInToday(_ date: Date, timeZone: TimeZone, referenceDate: Date = Date()) -> Bool {
        isDate(date, inSameDayAs: referenceDate, timeZone: timeZone)
    }

    static func date(byAdding component: Calendar.Component, value: Int, to date: Date, timeZone: TimeZone) -> Date? {
        gregorianCalendar(timeZone: timeZone).date(byAdding: component, value: value, to: date)
    }

    static func preservingCalendarDay(_ date: Date, from sourceTimeZone: TimeZone, to destinationTimeZone: TimeZone) -> Date {
        let sourceCalendar = gregorianCalendar(timeZone: sourceTimeZone)
        let destinationCalendar = gregorianCalendar(timeZone: destinationTimeZone)
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
        let destinationDate = destinationCalendar.date(from: components) ?? date
        return destinationCalendar.startOfDay(for: destinationDate)
    }
}
