import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class SidebarViewModelTests: XCTestCase {
    final class MockLocationController: LocationProviding {
        var selectedLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        @Published var locationName = ""
        @Published var locationUpdateID = UUID()
        var locationUpdateIDPublisher: Published<UUID>.Publisher { $locationUpdateID }
        var locationNamePublisher: Published<String>.Publisher { $locationName }
        var anyChangePublisher: AnyPublisher<Void, Never> {
            objectWillChange.map { _ in () }.eraseToAnyPublisher()
        }
        var searchResults: [MKMapItem] = []
        var isSearching = false
        var isLocating = false
        var locationError: LocationController.LocationError?
        var searchFocusTrigger = 0
        var currentLocationCenterTrigger = 0

        private(set) var requestCurrentLocationCalled = false
        private(set) var searchQuery: String?
        private(set) var selectedMapItem: MKMapItem?
        private(set) var selectedCoordinateCalls: [CLLocationCoordinate2D] = []

        func requestCurrentLocation() {
            requestCurrentLocationCalled = true
        }

        func search(query: String) {
            searchQuery = query
            isSearching = true
        }

        func select(_ mapItem: MKMapItem) {
            selectedMapItem = mapItem
            selectedLocation = mapItem.location.coordinate
            currentLocationCenterTrigger += 1
        }

        func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
            selectedCoordinateCalls.append(coordinate)
            selectedLocation = coordinate
            currentLocationCenterTrigger += 1
        }
    }

    final class MockLightPollutionService: LightPollutionProviding {
        @Published var bortleClass: Double? = nil
        var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
        @Published var isLoading = false
        var isLoadingPublisher: Published<Bool>.Publisher { $isLoading }
        @Published var fetchFailed = false

        func fetch(latitude: Double, longitude: Double) async {
            isLoading = true
            try? await Task.sleep(nanoseconds: 1_000_000)
            isLoading = false
        }

        func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
            4.0
        }
    }

    func test_SidebarViewModel_handleSearchTextChanged_triggersSearch() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        viewModel.searchState.text = "Tokyo"
        viewModel.handleSearchTextChanged()

        XCTAssertEqual(locationController.searchQuery, "Tokyo")
        XCTAssertTrue(locationController.isSearching)
    }

    func test_SidebarViewModel_selectCoordinate_updatesLocationController() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        let coordinate = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        viewModel.selectCoordinate(coordinate)

        XCTAssertEqual(locationController.selectedLocation.latitude, coordinate.latitude)
        XCTAssertEqual(locationController.selectedLocation.longitude, coordinate.longitude)
        XCTAssertEqual(locationController.currentLocationCenterTrigger, 1)
    }

    func test_SidebarViewModel_setLocationInputMode_updatesOverlayStateAndSyncTrigger() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        XCTAssertEqual(viewModel.locationInputMode, .map)
        XCTAssertFalse(viewModel.isShowingLightPollution)
        XCTAssertEqual(viewModel.mapViewportSyncTrigger, 0)

        viewModel.setLocationInputMode(.lightPollutionMap)

        XCTAssertEqual(viewModel.locationInputMode, .lightPollutionMap)
        XCTAssertTrue(viewModel.isShowingLightPollution)
        XCTAssertEqual(viewModel.mapViewportSyncTrigger, 1)
    }

    func test_SidebarViewModel_setLocationInputMode_sameValue_doesNotTriggerViewportSync() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        viewModel.setLocationInputMode(.map)

        XCTAssertEqual(viewModel.mapViewportSyncTrigger, 0)
    }

    func test_SidebarViewModel_selectSearchResult_fillSelectionName_keepsSelectedNameInSearchField() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let item = MKMapItem(
            location: CLLocation(latitude: 35.3606, longitude: 138.7274),
            address: nil
        )
        item.name = "富士山五合目"

        viewModel.searchState.text = "富士山"
        viewModel.selectSearchResult(item, searchTextBehavior: .fillSelectionName)

        XCTAssertTrue(locationController.selectedMapItem === item)
        XCTAssertEqual(viewModel.searchState.text, "富士山五合目")
    }

    func test_SidebarViewModel_selectSearchResult_clear_emptiesSearchField() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let item = MKMapItem(
            location: CLLocation(latitude: 35.3606, longitude: 138.7274),
            address: nil
        )
        item.name = "富士山五合目"

        viewModel.searchState.text = "富士山"
        viewModel.selectSearchResult(item, searchTextBehavior: .clear)

        XCTAssertTrue(locationController.selectedMapItem === item)
        XCTAssertEqual(viewModel.searchState.text, "")
    }

    func test_SidebarViewModel_updateViewportIfNeeded_ignoresSmallRegionChanges() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let initialCenter = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        let initialSpan = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        viewModel.viewport.center = initialCenter
        viewModel.viewport.span = initialSpan

        viewModel.updateViewportIfNeeded(
            center: CLLocationCoordinate2D(latitude: 35.00001, longitude: 139.00001),
            span: MKCoordinateSpan(latitudeDelta: 0.10001, longitudeDelta: 0.10001)
        )

        XCTAssertEqual(viewModel.viewport.center.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.center.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.span.latitudeDelta, initialSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.span.longitudeDelta, initialSpan.longitudeDelta, accuracy: 0.000001)
    }

    func test_SidebarViewModel_updateViewportIfNeeded_appliesMeaningfulRegionChanges() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let viewModel = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let updatedCenter = CLLocationCoordinate2D(latitude: 35.1, longitude: 139.1)
        let updatedSpan = MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)

        viewModel.updateViewportIfNeeded(center: updatedCenter, span: updatedSpan)

        XCTAssertEqual(viewModel.viewport.center.latitude, updatedCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.center.longitude, updatedCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.span.latitudeDelta, updatedSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(viewModel.viewport.span.longitudeDelta, updatedSpan.longitudeDelta, accuracy: 0.000001)
    }
}
