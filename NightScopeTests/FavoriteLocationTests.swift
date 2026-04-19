import XCTest
import CoreLocation
@testable import NightScope

@MainActor
final class FavoriteLocationTests: XCTestCase {

    private final class MockFavoriteStore: FavoriteLocationStoring, @unchecked Sendable {
        private(set) var saved: [FavoriteLocation] = []
        var preloaded: [FavoriteLocation] = []

        func loadAll() -> [FavoriteLocation] {
            preloaded
        }

        func save(_ favorites: [FavoriteLocation]) {
            saved = favorites
        }
    }

    private func makeSidebarViewModel(
        favoriteStore: MockFavoriteStore = MockFavoriteStore()
    ) -> (SidebarViewModel, MockLocationController, MockFavoriteStore) {
        let locationController = MockLocationController()
        locationController.selectedLocation = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        locationController.locationName = "東京"
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(
            locationController: locationController,
            lightPollutionService: lightService,
            favoriteStore: favoriteStore
        )
        return (vm, locationController, favoriteStore)
    }

    // MARK: - Add

    func test_addCurrentLocationToFavorites_appendsAndPersists() {
        let (vm, _, store) = makeSidebarViewModel()

        vm.addCurrentLocationToFavorites()

        XCTAssertEqual(vm.favorites.count, 1)
        XCTAssertEqual(vm.favorites.first?.name, "東京")
        XCTAssertEqual(vm.favorites.first?.latitude ?? 0, 35.6762, accuracy: 0.0001)
        XCTAssertEqual(vm.favorites.first?.longitude ?? 0, 139.6503, accuracy: 0.0001)
        XCTAssertEqual(store.saved.count, 1)
    }

    func test_addCurrentLocationToFavorites_doesNotDuplicate() {
        let (vm, _, store) = makeSidebarViewModel()

        vm.addCurrentLocationToFavorites()
        vm.addCurrentLocationToFavorites()

        XCTAssertEqual(vm.favorites.count, 1)
        XCTAssertEqual(store.saved.count, 1)
    }

    func test_isCurrentLocationFavorited_returnsTrueWhenNearby() {
        let (vm, _, _) = makeSidebarViewModel()

        XCTAssertFalse(vm.isCurrentLocationFavorited)
        vm.addCurrentLocationToFavorites()
        XCTAssertTrue(vm.isCurrentLocationFavorited)
    }

    // MARK: - Toggle

    func test_toggleCurrentLocationFavorite_addsWhenNotFavorited() {
        let (vm, _, store) = makeSidebarViewModel()

        vm.toggleCurrentLocationFavorite()

        XCTAssertEqual(vm.favorites.count, 1)
        XCTAssertEqual(vm.favorites.first?.name, "東京")
        XCTAssertEqual(store.saved.count, 1)
    }

    func test_toggleCurrentLocationFavorite_removesWhenFavorited() {
        let (vm, _, store) = makeSidebarViewModel()
        vm.addCurrentLocationToFavorites()
        XCTAssertTrue(vm.isCurrentLocationFavorited)

        vm.toggleCurrentLocationFavorite()

        XCTAssertTrue(vm.favorites.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
    }

    // MARK: - Remove

    func test_removeFavorite_removesFromListAndPersists() {
        let (vm, _, store) = makeSidebarViewModel()
        vm.addCurrentLocationToFavorites()
        let favorite = vm.favorites[0]

        vm.removeFavorite(favorite)

        XCTAssertTrue(vm.favorites.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func test_removeFavorites_atOffsets() {
        let (vm, locationController, store) = makeSidebarViewModel()
        vm.addCurrentLocationToFavorites()

        locationController.selectedLocation = CLLocationCoordinate2D(latitude: 34.0, longitude: 135.0)
        locationController.locationName = "大阪"
        vm.addCurrentLocationToFavorites()

        XCTAssertEqual(vm.favorites.count, 2)

        vm.removeFavorites(at: IndexSet(integer: 0))

        XCTAssertEqual(vm.favorites.count, 1)
        XCTAssertEqual(vm.favorites[0].name, "大阪")
        XCTAssertEqual(store.saved.count, 1)
    }

    // MARK: - Select

    func test_selectFavorite_updatesLocationController() {
        let (vm, locationController, _) = makeSidebarViewModel()
        vm.addCurrentLocationToFavorites()

        locationController.selectedLocation = CLLocationCoordinate2D(latitude: 34.0, longitude: 135.0)
        locationController.locationName = "大阪"

        let favorite = vm.favorites[0]
        vm.selectFavorite(favorite)

        XCTAssertEqual(locationController.selectedCoordinateCalls.count, 1)
        XCTAssertEqual(locationController.selectedCoordinateCalls[0].latitude, 35.6762, accuracy: 0.0001)
        XCTAssertEqual(locationController.selectedCoordinateCalls[0].longitude, 139.6503, accuracy: 0.0001)
    }

    // MARK: - Load

    func test_init_loadsFavoritesFromStore() {
        let store = MockFavoriteStore()
        store.preloaded = [
            FavoriteLocation(
                name: "京都",
                latitude: 35.0116,
                longitude: 135.7681,
                timeZoneIdentifier: "Asia/Tokyo"
            )
        ]
        let (vm, _, _) = makeSidebarViewModel(favoriteStore: store)

        XCTAssertEqual(vm.favorites.count, 1)
        XCTAssertEqual(vm.favorites[0].name, "京都")
    }

    // MARK: - FavoriteLocationStore persistence

    func test_favoriteLocationStore_roundTrips() {
        let suiteName = "test.favorites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = FavoriteLocationStore(userDefaults: defaults)

        let favorite = FavoriteLocation(
            name: "札幌",
            latitude: 43.0618,
            longitude: 141.3545,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        store.save([favorite])
        let loaded = store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "札幌")
        XCTAssertEqual(loaded[0].latitude, 43.0618, accuracy: 0.0001)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_favoriteLocationStore_emptyByDefault() {
        let suiteName = "test.favorites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = FavoriteLocationStore(userDefaults: defaults)

        XCTAssertTrue(store.loadAll().isEmpty)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
