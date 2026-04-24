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
        var timeZoneIdentifier: String?
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
        let timeZoneIdentifier: String?
        private var lastCoordinate: CLLocationCoordinate2D?

        init(resolvedName: String, timeZoneIdentifier: String? = nil) {
            self.resolvedName = resolvedName
            self.timeZoneIdentifier = timeZoneIdentifier
        }

        func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
            lastCoordinate = coordinate
            return ResolvedLocationDetails(name: resolvedName, timeZoneIdentifier: timeZoneIdentifier)
        }

        func getLastCoordinate() -> CLLocationCoordinate2D? {
            lastCoordinate
        }
    }

    actor DelayedLocationNameResolver: LocationNameResolving {
        let details: ResolvedLocationDetails
        let delayNanoseconds: UInt64

        init(details: ResolvedLocationDetails, delayNanoseconds: UInt64) {
            self.details = details
            self.delayNanoseconds = delayNanoseconds
        }

        func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return details
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

        func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
            let index = callCount
            callCount += 1
            let delay = index < delaysInNanoseconds.count ? delaysInNanoseconds[index] : 0
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            let name = index < resolvedNames.count ? resolvedNames[index] : "現在地"
            return ResolvedLocationDetails(name: name, timeZoneIdentifier: nil)
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

    func test_LocationController_init_ignoresInvalidPersistedCoordinateAndClearsStorage() {
        let storage = InMemoryLocationStorage()
        storage.latitude = 90.0522
        storage.longitude = -62.2437
        storage.name = "破損した場所"
        storage.timeZoneIdentifier = "America/Halifax"

        let sut = LocationController(
            storage: storage,
            searchService: MockLocationSearchService(result: .success([])),
            locationNameResolver: MockLocationNameResolver(resolvedName: "東京")
        )

        XCTAssertEqual(sut.selectedLocation.latitude, 35.6762, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, 139.6503, accuracy: 0.000001)
        XCTAssertEqual(sut.locationName, L10n.tr("東京"))
        XCTAssertNil(storage.latitude)
        XCTAssertNil(storage.longitude)
        XCTAssertNil(storage.name)
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_init_replacesPersistedProvisionalTimeZoneWithHeuristicIdentifier() {
        let storage = InMemoryLocationStorage()
        storage.latitude = 34.0522
        storage.longitude = -118.2437
        storage.name = "ロサンゼルス"
        storage.timeZoneIdentifier = "Etc/GMT+8"

        let sut = LocationController(
            storage: storage,
            searchService: MockLocationSearchService(result: .success([])),
            locationNameResolver: MockLocationNameResolver(resolvedName: "ロサンゼルス")
        )

        XCTAssertEqual(sut.selectedTimeZone.identifier, "America/Los_Angeles")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_init_clearsPersistedProvisionalTimeZoneWhenOnlyProvisionalFallbackExists() {
        let storage = InMemoryLocationStorage()
        storage.latitude = 0.0
        storage.longitude = 150.0
        storage.name = "赤道付近"
        storage.timeZoneIdentifier = "Etc/GMT-10"

        let sut = LocationController(
            storage: storage,
            searchService: MockLocationSearchService(result: .success([])),
            locationNameResolver: MockLocationNameResolver(resolvedName: "赤道付近")
        )

        XCTAssertEqual(sut.selectedTimeZone.identifier, "Etc/GMT-10")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_init_usesHeuristicTimeZoneWithoutPersistingIt() {
        let storage = InMemoryLocationStorage()
        storage.latitude = 34.0522
        storage.longitude = -118.2437
        storage.name = "ロサンゼルス"

        let sut = LocationController(
            storage: storage,
            searchService: MockLocationSearchService(result: .success([])),
            locationNameResolver: MockLocationNameResolver(resolvedName: "ロサンゼルス")
        )

        XCTAssertEqual(sut.selectedTimeZone.identifier, "America/Los_Angeles")
        XCTAssertNil(storage.timeZoneIdentifier)
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

    func test_LocationController_search_failure_setsFailureState() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .failure(MockLocationSearchError.failed))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        sut.searchResults = [makeMapItem(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))]

        sut.search(query: "invalid")

        await waitUntil {
            sut.searchState.phase == .failure
        }

        let lastQuery = await searchService.getLastQuery()
        XCTAssertEqual(lastQuery, "invalid")
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertEqual(sut.searchState.query, "invalid")
        XCTAssertNotNil(sut.searchState.errorMessage)
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

    func test_LocationController_search_newQueryKeepsPreviousResultsWhileLoading() {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let previousResults = [makeMapItem(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0), name: "Tokyo")]
        sut.searchResults = previousResults

        sut.search(query: "Osaka")

        XCTAssertTrue(sut.isSearching)
        XCTAssertEqual(sut.searchResults.count, previousResults.count)
        XCTAssertEqual(sut.searchResults.first?.name, previousResults.first?.name)
        XCTAssertEqual(sut.searchState.phase, .loading)
        XCTAssertEqual(sut.searchState.query, "Osaka")
    }

    func test_LocationController_clearSearch_idlesSearchStateImmediately() {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let previousResults = [makeMapItem(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            name: "Tokyo"
        )]
        sut.searchResults = previousResults

        sut.clearSearch()

        XCTAssertFalse(sut.isSearching)
        XCTAssertEqual(sut.searchState.phase, .idle)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func test_LocationController_clearSearch_preventsStaleResultFromAppearing() async {
        let storage = InMemoryLocationStorage()
        let searchService = CountingLocationSearchService(delayInNanoseconds: 300_000_000)
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        sut.search(query: "tokyo")
        // デバウンス(150ms)が終わってサービス呼び出しが始まるのを待つ
        try? await Task.sleep(nanoseconds: 170_000_000)
        XCTAssertTrue(sut.isSearching, "検索中のはず")

        sut.clearSearch()
        XCTAssertEqual(sut.searchState.phase, .idle, "clearSearch 直後は idle のはず")
        XCTAssertTrue(sut.searchResults.isEmpty)

        // サービスの遅延(300ms)が完了するのを十分に待ち、stale 結果が復活しないことを確認
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.searchState.phase, .idle, "stale 結果で上書きされないはず")
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func test_MapItemLocationDetailsExtractor_usesMapItemTimeZone() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let item = makeMapItem(coordinate: coordinate, name: "ロサンゼルス")
        item.timeZone = TimeZone(identifier: "America/Los_Angeles")

        let details = MapItemLocationDetailsExtractor.details(from: item)

        XCTAssertEqual(details.name, "ロサンゼルス")
        XCTAssertEqual(details.timeZoneIdentifier, "America/Los_Angeles")
    }

    func test_LocationController_select_prefersMapItemTimeZoneWhenResolverOmitsTimeZone() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "ロサンゼルス", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let item = makeMapItem(coordinate: coordinate, name: "Los Angeles")
        item.timeZone = TimeZone(identifier: "America/Los_Angeles")

        sut.select(item)

        await waitUntil {
            sut.selectedTimeZone.identifier == "America/Los_Angeles"
                && sut.locationName == "ロサンゼルス"
        }

        XCTAssertEqual(storage.timeZoneIdentifier, "America/Los_Angeles")
    }

    func test_LocationController_select_recommitsWhenResolverCorrectsTimeZone() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = DelayedLocationNameResolver(
            details: ResolvedLocationDetails(
                name: "フェニックス",
                timeZoneIdentifier: "America/Phoenix"
            ),
            delayNanoseconds: 80_000_000
        )
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 33.4484, longitude: -112.0740)
        let item = makeMapItem(coordinate: coordinate, name: "Phoenix")
        item.timeZone = TimeZone(identifier: "America/Los_Angeles")

        let initialUpdateID = sut.locationUpdateID
        sut.select(item)
        let committedUpdateID = sut.locationUpdateID

        XCTAssertNotEqual(committedUpdateID, initialUpdateID)
        XCTAssertEqual(sut.selectedTimeZone.identifier, "America/Los_Angeles")

        await waitUntil(timeout: 2.0) {
            sut.selectedTimeZone.identifier == "America/Phoenix"
                && sut.locationUpdateID != committedUpdateID
        }

        XCTAssertEqual(sut.locationName, "フェニックス")
        XCTAssertEqual(storage.timeZoneIdentifier, "America/Phoenix")
    }

    func test_LocationController_select_updatesCenterTriggerAndResolvedName_andStopsLocating() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "新宿区")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)

        let coordinate = CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034)
        let item = makeMapItem(coordinate: coordinate, name: "新宿駅")
        let baseTrigger = sut.currentLocationCenterTrigger

        sut.searchResults = [item]
        sut.isSearching = true
        sut.isLocating = true
        sut.select(item)

        await waitUntil {
            sut.locationName == "新宿区"
        }

        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(sut.currentLocationCenterTrigger, baseTrigger + 1)
        XCTAssertFalse(sut.isSearching)
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertFalse(sut.isLocating)
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

    func test_LocationController_selectCoordinate_usesManualSelectionFallbackNameWhenResolverCannotNameLocation() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        let expectedFallbackName = L10n.tr("選択した地点")

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == expectedFallbackName
        }

        XCTAssertEqual(sut.locationName, expectedFallbackName)
    }

    func test_LocationController_selectCoordinate_updatesResolvedTimeZone() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(
            resolvedName: "ロサンゼルス",
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "ロサンゼルス"
                && sut.selectedTimeZone.identifier == "America/Los_Angeles"
        }

        XCTAssertEqual(storage.timeZoneIdentifier, "America/Los_Angeles")
    }

    func test_LocationController_selectCoordinate_commitsLocationUpdateBeforeResolverFinishes() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = DelayedLocationNameResolver(
            details: ResolvedLocationDetails(
                name: "ロサンゼルス",
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            delayNanoseconds: 80_000_000
        )
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        let initialUpdateID = sut.locationUpdateID
        sut.selectCoordinate(coordinate)

        XCTAssertNotEqual(sut.locationUpdateID, initialUpdateID)
        XCTAssertEqual(sut.selectedLocation.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, coordinate.longitude, accuracy: 0.000001)

        await waitUntil(timeout: 2.0) {
            sut.locationName == "ロサンゼルス"
                && sut.selectedTimeZone.identifier == "America/Los_Angeles"
        }
    }

    func test_LocationController_selectCoordinate_fallsBackToApproximateTimeZone() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "東京", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "東京"
                && sut.selectedTimeZone.secondsFromGMT() == 9 * 3_600
        }

        XCTAssertEqual(sut.selectedTimeZone.secondsFromGMT(), 9 * 3_600)
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_fallsBackToApproximateTimeZoneForAdelaide() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "アデレード", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "アデレード"
                && sut.selectedTimeZone.identifier == "Australia/Adelaide"
        }

        XCTAssertEqual(sut.selectedTimeZone.identifier, "Australia/Adelaide")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_doesNotPersistProvisionalTimeZone() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 0.0, longitude: 150.0)
        let expectedFallbackName = L10n.tr("選択した地点")

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == expectedFallbackName
        }

        XCTAssertEqual(sut.selectedTimeZone.identifier, "Etc/GMT-10")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_fallsBackToApproximateTimeZoneForKathmandu() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "カトマンズ", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 27.7172, longitude: 85.3240)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "カトマンズ"
                && sut.selectedTimeZone.identifier == "Asia/Kathmandu"
        }

        XCTAssertEqual(sut.selectedTimeZone.identifier, "Asia/Kathmandu")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_fallsBackToApproximateTimeZoneForHalifax() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "ハリファックス", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "ハリファックス"
                && sut.selectedTimeZone.identifier == "America/Halifax"
        }

        XCTAssertEqual(sut.selectedTimeZone.identifier, "America/Halifax")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_fallsBackToDSTAwareTimeZoneForLosAngeles() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "ロサンゼルス", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "ロサンゼルス"
                && sut.selectedTimeZone.identifier == "America/Los_Angeles"
        }

        let summerDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 7,
            day: 1
        ).date!
        XCTAssertEqual(sut.selectedTimeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(sut.selectedTimeZone.secondsFromGMT(for: summerDate), -7 * 3_600)
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_selectCoordinate_fallsBackToDSTAwareTimeZoneForParis() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "パリ", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "パリ"
                && sut.selectedTimeZone.identifier == "Europe/Paris"
        }

        let summerDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 7,
            day: 1
        ).date!
        XCTAssertEqual(sut.selectedTimeZone.identifier, "Europe/Paris")
        XCTAssertEqual(sut.selectedTimeZone.secondsFromGMT(for: summerDate), 2 * 3_600)
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_ApproximateTimeZoneResolver_exactIdentifier_requiresConfirmedSource() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        let identifier = ApproximateTimeZoneResolver.exactIdentifier(for: coordinate)

        XCTAssertNil(identifier)
    }

    func test_ApproximateTimeZoneResolver_usesRegionBackedTimeZoneForTokyo() {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)

        let identifier = ApproximateTimeZoneResolver.identifier(for: coordinate, regionIdentifier: "JP")

        XCTAssertEqual(identifier, "Asia/Tokyo")
    }

    func test_ApproximateTimeZoneResolver_usesAtlanticHeuristicForHalifax() {
        let coordinate = CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752)

        let identifier = ApproximateTimeZoneResolver.identifier(for: coordinate, regionIdentifier: nil)

        XCTAssertEqual(identifier, "America/Halifax")
    }

    func test_ApproximateTimeZoneResolver_usesProvisionalOffsetForAmbiguousUSBorderCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.8481, longitude: -114.6141)

        let identifier = ApproximateTimeZoneResolver.approximateIdentifier(for: coordinate)

        XCTAssertEqual(identifier, "Etc/GMT+8")
    }

    func test_ApproximateTimeZoneResolver_usesRegionBackedTimeZoneForBerlinWithDST() {
        let coordinate = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
        let summerDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 7,
            day: 1
        ).date!

        let identifier = ApproximateTimeZoneResolver.identifier(for: coordinate, regionIdentifier: "DE")

        XCTAssertEqual(identifier, "Europe/Berlin")
        XCTAssertEqual(TimeZone(identifier: identifier)?.secondsFromGMT(for: summerDate), 2 * 3_600)
    }

    func test_ApproximateTimeZoneResolver_usesRegionBackedTimeZoneForBuenosAires() {
        let coordinate = CLLocationCoordinate2D(latitude: -34.6037, longitude: -58.3816)
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 7,
            day: 1
        ).date!

        let identifier = ApproximateTimeZoneResolver.identifier(for: coordinate, regionIdentifier: "AR")

        XCTAssertEqual(identifier, "America/Argentina/Buenos_Aires")
        XCTAssertEqual(TimeZone(identifier: identifier)?.secondsFromGMT(for: date), -3 * 3_600)
    }

    func test_LocationController_selectCoordinate_usesProvisionalOffsetForAmbiguousBorderCoordinate() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "Needles", timeZoneIdentifier: nil)
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let coordinate = CLLocationCoordinate2D(latitude: 34.8481, longitude: -114.6141)

        sut.selectCoordinate(coordinate)

        await waitUntil {
            sut.locationName == "Needles"
        }

        XCTAssertEqual(sut.selectedTimeZone.identifier, "Etc/GMT+8")
        XCTAssertNil(storage.timeZoneIdentifier)
    }

    func test_LocationController_didUpdateLocations_usesLatestLocation() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "現在地")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let older = CLLocation(latitude: 35.6580, longitude: 139.7016)
        let latest = CLLocation(latitude: 35.6762, longitude: 139.6503)

        sut.locationManager(CLLocationManager(), didUpdateLocations: [older, latest])

        await waitUntil {
            abs(sut.selectedLocation.latitude - latest.coordinate.latitude) < 0.000001
                && abs(sut.selectedLocation.longitude - latest.coordinate.longitude) < 0.000001
        }

        XCTAssertEqual(sut.selectedLocation.latitude, latest.coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, latest.coordinate.longitude, accuracy: 0.000001)
    }

    func test_LocationController_didUpdateLocations_ignoresLateLocationAfterManualSelection() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "現在地")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        let manualCoordinate = CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034)
        let lateLocation = CLLocation(latitude: 35.6762, longitude: 139.6503)

        sut.isLocating = true
        sut.select(makeMapItem(coordinate: manualCoordinate, name: "新宿"))

        await waitUntil {
            !sut.isLocating
        }

        sut.locationManager(CLLocationManager(), didUpdateLocations: [lateLocation])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sut.selectedLocation.latitude, manualCoordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(sut.selectedLocation.longitude, manualCoordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(sut.locationName, "新宿")
    }

    // MARK: - Bug fix: 権限未決定時に isLocating が残る

    /// 権限取得後に didUpdateLocations が呼ばれると isLocating が解消される。
    /// requestCurrentLocation() → (権限応答待ち) → 許可 → 位置取得 の流れを模倣。
    func test_LocationController_locationReceivedAfterAuthorization_clearsIsLocating() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "現在地")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        // notDetermined → requestCurrentLocation() → isLocating=true の状態を模倣
        sut.isLocating = true
        let loc = CLLocation(latitude: 35.6762, longitude: 139.6503)

        sut.locationManager(CLLocationManager(), didUpdateLocations: [loc])

        await waitUntil {
            !sut.isLocating
        }

        XCTAssertFalse(sut.isLocating)
        XCTAssertNil(sut.locationError)
    }

    /// select() 呼び出しは、isLocating 中でも確実に isLocating を解消する。
    /// これは権限未決定の状態でユーザーが手動で場所を選択した場合のカバー。
    func test_LocationController_select_whileLocating_clearsIsLocating() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "新宿")
        let sut = LocationController(storage: storage, searchService: searchService, locationNameResolver: resolver)
        sut.isLocating = true

        let item = makeMapItem(coordinate: CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034), name: "新宿")
        sut.select(item)

        await waitUntil { !sut.isLocating }

        XCTAssertFalse(sut.isLocating)
    }

    func test_LocationController_startLocatingTimeout_marksFailureWhenNoUpdateArrives() async {
        let storage = InMemoryLocationStorage()
        let searchService = MockLocationSearchService(result: .success([]))
        let resolver = MockLocationNameResolver(resolvedName: "東京")
        let sut = LocationController(
            storage: storage,
            searchService: searchService,
            locationNameResolver: resolver,
            locationRequestTimeout: .milliseconds(20)
        )
        sut.isLocating = true

        sut.startLocatingTimeout()

        await waitUntil(timeout: 1.0) {
            !sut.isLocating
        }

        XCTAssertFalse(sut.isLocating)
        XCTAssertEqual(sut.locationError, .failed)
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
