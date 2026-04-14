import Foundation

enum ObservationTimeZone {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var timeZone = TimeZone.current

        func current() -> TimeZone {
            lock.lock()
            defer { lock.unlock() }
            return timeZone
        }

        func update(_ timeZone: TimeZone) {
            lock.lock()
            self.timeZone = timeZone
            lock.unlock()
        }
    }

    private static let storage = Storage()

    static var current: TimeZone {
        storage.current()
    }

    static func update(_ timeZone: TimeZone) {
        storage.update(timeZone)
    }

    static func gregorianCalendar(timeZone: TimeZone = ObservationTimeZone.current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
