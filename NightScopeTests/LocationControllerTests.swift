import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class LocationControllerTests: XCTestCase {

    private func makeMapItem(coordinate: CLLocationCoordinate2D, name: String? = nil) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        return item
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("条件を満たすまでにタイムアウトしました", file: file, line: line)
    }

    final class InMemoryLocationStorage: LocationStorage {
        var latitude: Double?
        var longitude: Double?
        var name: String?
    }

    enum MockLocationSearchError: Error {
        case failed
    }

    actor MockLocationSearchService: LocationSearchServicing {
        let result: Result<[MKMapItem], Error>
        private var lastQuery: String?

        init(result: Result<[MKMapItem], Error>) {
            self.result = result
        }

        func search(query: String) async throws -> [MKMapItem] {
            lastQuery = query
            return try result.get()
        }

        func getLastQuery() -> String? {
            lastQuery
        }
    }

    actor MockLocationNameResolver: LocationNameResolving {
        let resolvedName: String
        private var lastCoordinate: CLLocationCoordinate2D?

        init(resolvedName: String) {
            self.resolvedName = resolvedName
        }

        func resolveName(for coordinate: CLLocationCoordinate2D) async -> String {
            lastCoordinate = coordinate
            return resolvedName
        }

        func getLastCoordinate() -> CLLocationCoordinate2D? {
            lastCoordinate
        }
    }

    actor SequencedLocationNameResolver: LocationNameResolving {
        private let resolvedNames: [String]
        private let delaysInNanoseconds: [UInt64]
        private var callCount = 0

        init(resolvedNames: [String], delaysInNanoseconds: [UInt64]) {
            self.resolvedNames = resolvedNames
            self.delaysInNanoseconds = delaysInNanoseconds
        }

        func resolveName(for coordinate: CLLocationCoordinate2D) async -> String {
            let index = callCount
            callCount += 1
            let delay = index < delaysInNanoseconds.count ? delaysInNanoseconds[index] : 0
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            return index < resolvedNames.count ? resolvedNames[index] : "現在地"
        }

        func getCallCount() -> Int {
            callCount
        }
    }

    actor DelayedQueryLocationSearchService: LocationSearchServicing {
        private var queries: [String] = []

        func search(query: String) async throws -> [MKMapItem] {
            queries.append(query)

            if query == "tok" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return [Self.makeMapItem(latitude: 35.0, longitude: 139.0, name: "旧結果")]
            }

            if query == "tokyo" {
                try? await Task.sleep(nanoseconds: 1_000_000)
                return [Self.makeMapItem(latitude: 35.6762, longitude: 139.6503, name: "最新結果")]
            }

            return []
        }

        func getQueries() -> [String] {
            queries
        }

        private static func makeMapItem(latitude: Double, longitude: Double, name: String) -> MKMapItem {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let item = MKMapItem(location: location, address: nil)
            item.name = name
            return item
        }
    }

    actor CountingLocationSearchService: LocationSearchServicing {
        private let delayInNanoseconds: UInt64
        private var queries: [String] = []

        init(delayInNanoseconds: UInt64 = 300_000_000) {
            self.delayInNanoseconds = delayInNanoseconds
        }

        func search(query: String) async throws -> [MKMapItem] {
            queries.append(query)
            if delayInNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayInNanoseconds)
            }

            let location = CLLocation(latitude: 35.6762, longitude: 139.6503)
            let item = MKMapItem(location: location, address: nil)
            item.name = query
            return [item]
        }

        func getQueries() -> [String] {
            queries
        }
    }

    func test_UserDefaultsLocationStorage_zeroCoordinatesRoundTrip() {
        let suiteName = "LocationControllerTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("テスト用 UserDefaults を生成できませんでした")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let storage = UserDefaultsLocationStorage(userDefaults: userDefaults)
        storage.latitude = 0
        storage.longitude = 0

        XCTAssertEqual(storage.latitude, 0)
        XCTAssertEqual(storage.longitude, 0)
    }

    func test_LocationController_search_success_updatesResults() async {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let item = makeMapItem(coordinate: coordinate, name: "東京駅")

        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([item]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "東京駅")

        await waitUntil {
            sut.isSearching == false && sut.searchResults.count == 1
        }

        let lastQuery = await searchService.getLastQuery()
        XCTAssertEqual(lastQuery, "東京駅")
        XCTAssertEqual(sut.searchResults.first?.name, "東京駅")
    }

    func test_LocationController_search_failure_clearsResults() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .failure(MockLocationSearchError.failed))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        sut.searchResults = [makeMapItem(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))]

        sut.search(query: "invalid")

        await waitUntil {
            sut.isSearching == false
        }

        let lastQuery = await searchService.getLastQuery()
        XCTAssertEqual(lastQuery, "invalid")
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func test_LocationController_search_trimsWhitespaceAndNewline() async {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let item = makeMapItem(coordinate: coordinate, name: "東京駅")

        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([item]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "  東京駅\n")

        await waitUntil {
            sut.isSearching == false && sut.searchResults.count == 1
        }

        let lastQuery = await searchService.getLastQuery()
        XCTAssertEqual(lastQuery, "東京駅")
    }

    func test_LocationController_search_latestQueryResultWins() async {
        let storage = InMemoryLocationStorage()
        let searchService = DelayedQueryLocationSearchService()
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "tok")
        try? await Task.sleep(nanoseconds: 170_000_000)
        sut.search(query: "tokyo")

        await waitUntil(timeout: 2.0) {
            sut.isSearching == false && sut.searchResults.first?.name == "最新結果"
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(sut.searchResults.first?.name, "最新結果")
        let queries = await searchService.getQueries()
        XCTAssertTrue(queries.contains("tok"))
        XCTAssertEqual(queries.last, "tokyo")
    }

    func test_LocationController_search_sameNormalizedQueryWhileSearching_skipsRedundantRequest() async {
        let storage = InMemoryLocationStorage()
        let searchService = CountingLocationSearchService(delayInNanoseconds: 300_000_000)
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "tokyo")
        try? await Task.sleep(nanoseconds: 30_000_000)
        sut.search(query: "  tokyo\n")

        await waitUntil(timeout: 2.0) {
            sut.isSearching == false && sut.searchResults.first?.name == "tokyo"
        }

        let queries = await searchService.getQueries()
        XCTAssertEqual(queries, ["tokyo"])
    }

    func test_LocationController_select_updatesCenterTriggerAndResolvedName() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "新宿区")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let coordinate = CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034)
        let item = makeMapItem(coordinate: coordinate, name: "新宿駅")
        let baseTrigger = sut.currentLocationCenterTrigger

        sut.searchResults = [item]
        sut.isSearching = true
        sut.select(item)

        await waitUntil {
            sut.locationName == "新宿区"
        }

        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(sut.currentLocationCenterTrigger, baseTrigger + 1)
        XCTAssertFalse(sut.isSearching)
        XCTAssertTrue(sut.searchResults.isEmpty)
        guard let resolvedLatitude = await resolver.getLastCoordinate()?.latitude else {
            return XCTFail("resolver に座標が渡されていません")
        }
        XCTAssertEqual(resolvedLatitude, coordinate.latitude, accuracy: 0.000001)
    }

    func test_LocationController_selectCoordinate_updatesNameWithoutCenterIncrement() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "渋谷区")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let baseTrigger = sut.currentLocationCenterTrigger
        let coordinate = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        sut.isLocating = true
        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "渋谷区"
        }

        XCTAssertEqual(sut.currentLocationCenterTrigger, baseTrigger)
        XCTAssertFalse(sut.isLocating)
        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)
        guard let storedLatitude = storage.latitude,
              let storedLongitude = storage.longitude else {
            return XCTFail("選択座標が storage に保存されていません")
        }
        XCTAssertEqual(storedLatitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(storedLongitude, coordinate.longitude, accuracy: 0.000001)
    }

    func test_LocationController_selectCoordinate_latestResolutionWins() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = SequencedLocationNameResolver(
            resolvedNames: ["古い候補", "最新候補"],
            delaysInNanoseconds: [80_000_000, 1_000_000]
        )
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let first = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        let second = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)

        sut.selectCoordinate(first)
        sut.selectCoordinate(second)

        await waitUntil {
            sut.locationName == "最新候補"
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(sut.locationName, "最新候補")
        XCTAssertEqual(sut.selectedLocation.latitude, second.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, second.longitude, accuracy: 0.000001)
        let callCount = await resolver.getCallCount()
        XCTAssertEqual(callCount, 2)
    }
}
