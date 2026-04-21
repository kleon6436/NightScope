import XCTest
@testable import NightScope

final class CalendarViewTests: XCTestCase {
    func test_makeWeekdayHeaderItems_preservesLabelsAndUsesUniqueIDs() {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]

        let items = CalendarView.makeWeekdayHeaderItems(from: labels)

        XCTAssertEqual(items.map(\.label), labels)
        XCTAssertEqual(items.map(\.id), Array(0..<labels.count))
        XCTAssertEqual(Set(items.map(\.id)).count, labels.count)
    }
}