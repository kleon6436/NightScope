import XCTest
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class SidebarViewModelTests: XCTestCase {
    func test_updateSearchText_triggersSearch() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        vm.updateSearchText("Tokyo")

        XCTAssertEqual(vm.searchText, "Tokyo")
        XCTAssertEqual(locationController.searchQuery, "Tokyo")
        XCTAssertTrue(locationController.isSearching)
    }

    func test_selectCoordinate_updatesLocationController() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        let coord = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        vm.selectCoordinate(coord)

        XCTAssertEqual(locationController.selectedLocation.latitude, coord.latitude)
        XCTAssertEqual(locationController.selectedLocation.longitude, coord.longitude)
        XCTAssertEqual(locationController.selectedCoordinateCalls.count, 1)
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertFalse(vm.isShowingCommittedSelection)
    }

    func test_selectSearchResult_fillSelectionName_selectsItem() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let item = MKMapItem(location: CLLocation(latitude: 35.3606, longitude: 138.7274), address: nil)
        item.name = "富士山五合目"

        vm.selectSearchResult(item, searchTextBehavior: .fillSelectionName)

        XCTAssertTrue(locationController.selectedMapItem === item)
        XCTAssertEqual(locationController.currentLocationCenterTrigger, 1)
        XCTAssertEqual(vm.searchText, "富士山五合目")
        XCTAssertTrue(vm.isShowingCommittedSelection)
    }

    func test_selectSearchResult_clear_selectsItem() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let item = MKMapItem(location: CLLocation(latitude: 35.3606, longitude: 138.7274), address: nil)
        item.name = "富士山五合目"

        vm.selectSearchResult(item, searchTextBehavior: .clear)

        XCTAssertTrue(locationController.selectedMapItem === item)
        XCTAssertEqual(locationController.currentLocationCenterTrigger, 1)
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertFalse(vm.isShowingCommittedSelection)
    }

    func test_clearSearch_clearsResultsAndStopsSearching() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        vm.searchText = "富士山"
        locationController.searchResults = [
            MKMapItem(location: CLLocation(latitude: 35.0, longitude: 139.0), address: nil)
        ]
        locationController.isSearching = true

        vm.clearSearch()

        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertTrue(locationController.searchResults.isEmpty)
        XCTAssertFalse(locationController.isSearching)
    }

    func test_updateViewportIfNeeded_ignoresSmallRegionChanges() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let initialCenter = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)
        let initialSpan = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        vm.viewport.center = initialCenter
        vm.viewport.span = initialSpan

        vm.updateViewportIfNeeded(
            center: CLLocationCoordinate2D(latitude: 35.00001, longitude: 139.00001),
            span: MKCoordinateSpan(latitudeDelta: 0.10001, longitudeDelta: 0.10001)
        )

        XCTAssertEqual(vm.viewport.center.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.center.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.span.latitudeDelta, initialSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.span.longitudeDelta, initialSpan.longitudeDelta, accuracy: 0.000001)
    }

    func test_updateViewportIfNeeded_appliesMeaningfulRegionChanges() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        let updatedCenter = CLLocationCoordinate2D(latitude: 35.1, longitude: 139.1)
        let updatedSpan = MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)

        vm.updateViewportIfNeeded(center: updatedCenter, span: updatedSpan)

        XCTAssertEqual(vm.viewport.center.latitude, updatedCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.center.longitude, updatedCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.span.latitudeDelta, updatedSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(vm.viewport.span.longitudeDelta, updatedSpan.longitudeDelta, accuracy: 0.000001)
    }

    func test_appRootDependencies_makeDefault_sharesControllerDependencies() {
        let dependencies = AppRootDependencies.makeDefault()

        XCTAssertTrue((dependencies.sidebarViewModel.locationController as AnyObject) === dependencies.appController.locationController)
        XCTAssertTrue(dependencies.detailViewModel.weatherService === dependencies.appController.weatherService)
        XCTAssertTrue(dependencies.detailViewModel.lightPollutionService === dependencies.appController.lightPollutionService)
    }

    func test_appRootStore_keepsSharedControllerDependencies() {
        let dependencies = AppRootDependencies.makeDefault()
        let store = AppRootStore(dependencies: dependencies)

        XCTAssertTrue((store.sidebarViewModel.locationController as AnyObject) === store.appController.locationController)
        XCTAssertTrue(store.detailViewModel.weatherService === store.appController.weatherService)
        XCTAssertTrue(store.detailViewModel.lightPollutionService === store.appController.lightPollutionService)
    }
}

final class SidebarSearchInteractionTests: XCTestCase {
    func test_shouldShowEmptyState_whenUserQueryHasNoResults_returnsTrue() {
        let shouldShow = SidebarSearchInteraction.shouldShowEmptyState(
            searchText: "富士山",
            isSearching: false,
            hasResults: false,
            isShowingCommittedSelection: false
        )

        XCTAssertTrue(shouldShow)
    }

    func test_shouldShowEmptyState_whenShowingCommittedSelection_returnsFalse() {
        let shouldShow = SidebarSearchInteraction.shouldShowEmptyState(
            searchText: "富士山五合目",
            isSearching: false,
            hasResults: false,
            isShowingCommittedSelection: true
        )

        XCTAssertFalse(shouldShow)
    }
}
