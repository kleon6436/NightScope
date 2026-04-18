import XCTest
@testable import NightScope

final class SearchResultsLayoutTests: XCTestCase {
    func test_needsScroll_returnsFalseWhenResultsFitVisibleCapacity() {
        XCTAssertFalse(SearchResultsLayout.needsScroll(resultCount: 2, visibleRowCapacity: 2.5))
        XCTAssertFalse(SearchResultsLayout.needsScroll(resultCount: 3, visibleRowCapacity: 3.38))
    }

    func test_needsScroll_returnsTrueWhenResultsExceedVisibleCapacity() {
        XCTAssertTrue(SearchResultsLayout.needsScroll(resultCount: 3, visibleRowCapacity: 2.5))
        XCTAssertTrue(SearchResultsLayout.needsScroll(resultCount: 4, visibleRowCapacity: 3.38))
    }
}
