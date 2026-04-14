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
}
