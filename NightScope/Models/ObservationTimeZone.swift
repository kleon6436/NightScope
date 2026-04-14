import Foundation
import os

enum ObservationTimeZone {
    private static let storage = OSAllocatedUnfairLock(initialState: TimeZone.current)

    static var current: TimeZone {
        storage.withLock { $0 }
    }

    static func update(_ timeZone: TimeZone) {
        storage.withLock { $0 = timeZone }
    }

    static func gregorianCalendar(timeZone: TimeZone = ObservationTimeZone.current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
