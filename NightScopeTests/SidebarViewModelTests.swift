import XCTest
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class SidebarViewModelTests: XCTestCase {
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

    func test_updateSearchText_triggersSearch() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        vm.updateSearchText("Tokyo")

        XCTAssertEqual(vm.searchText, "Tokyo")
        XCTAssertEqual(locationController.searchQuery, "Tokyo")
        XCTAssertTrue(locationController.isSearching)
    }

    func test_updateSearchText_entersLoadingPresentationWithoutEmptyState() async {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        vm.updateSearchText("Osaka")

        await waitUntil {
            vm.searchState.phase == .loading
        }

        XCTAssertEqual(vm.searchState.phase, .loading)
        if case .loading = vm.searchPresentation {
            XCTAssertTrue(vm.isSearching)
        } else {
            XCTFail("検索中表示になっていません")
        }
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

    func test_requestCurrentLocation_clearsSearchPresentationImmediately() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        vm.searchText = "富士山"
        locationController.searchState = .results(
            query: "富士山",
            items: [MKMapItem(location: CLLocation(latitude: 35.0, longitude: 139.0), address: nil)]
        )

        vm.requestCurrentLocation()

        XCTAssertTrue(locationController.requestCurrentLocationCalled)
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
        locationController.searchState = .results(
            query: "富士山",
            items: [MKMapItem(location: CLLocation(latitude: 35.0, longitude: 139.0), address: nil)]
        )

        vm.clearSearch()

        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertEqual(locationController.searchState.phase, .idle)
        XCTAssertTrue(locationController.searchState.results.isEmpty)
    }

    func test_searchPresentation_showsErrorWithRetryForFailedSearch() async {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)
        vm.searchText = "Kyoto"
        locationController.searchState = .failure(
            query: "Kyoto",
            errorMessage: "通信状況を確認してください。"
        )

        await waitUntil {
            vm.searchState.phase == .failure
        }

        if case .error(let query, let message) = vm.searchPresentation {
            XCTAssertEqual(query, "Kyoto")
            XCTAssertEqual(message, "通信状況を確認してください。")
        } else {
            XCTFail("検索エラー表示になっていません")
        }

        vm.retrySearch()

        XCTAssertEqual(locationController.searchQuery, "Kyoto")
        XCTAssertEqual(locationController.searchState.phase, .loading)
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

    // MARK: - Bug fix: 同一座標の現在地再選択で検索UIが残る

    /// requestCurrentLocation() 呼び出し直後に searchText が空になり isShowingCommittedSelection が false になる。
    /// これにより同一座標が返った場合でも検索UIが確実にクリアされる。
    func test_requestCurrentLocation_immediatelyClearsSearchUI() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        // 検索済み・確定表示の状態を作る
        vm.searchText = "富士山"
        vm.updateSearchText("富士山") // isShowingCommittedSelection はここでは false だがテキストは残る

        vm.requestCurrentLocation()

        XCTAssertTrue(vm.searchText.isEmpty, "requestCurrentLocation() 後は searchText が空であること")
        XCTAssertFalse(vm.isShowingCommittedSelection, "requestCurrentLocation() 後は isShowingCommittedSelection が false であること")
        XCTAssertTrue(locationController.requestCurrentLocationCalled)
    }

    /// 検索候補を確定表示した後に requestCurrentLocation() を呼んでも UI がクリアされる。
    func test_requestCurrentLocation_clearsCommittedSelectionState() {
        let locationController = MockLocationController()
        let lightService = MockLightPollutionService()
        let vm = SidebarViewModel(locationController: locationController, lightPollutionService: lightService)

        let item = MKMapItem(location: CLLocation(latitude: 35.0, longitude: 139.0), address: nil)
        item.name = "御嶽山"
        vm.selectSearchResult(item, searchTextBehavior: .fillSelectionName)
        // この時点で searchText="御嶽山", isShowingCommittedSelection=true

        vm.requestCurrentLocation()

        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertFalse(vm.isShowingCommittedSelection)
    }
}

final class SidebarSearchInteractionTests: XCTestCase {
    func test_highlightedTarget_withoutValidIndex_returnsFirst() {
        let first = MKMapItem(location: CLLocation(latitude: 35.0, longitude: 139.0), address: nil)
        let second = MKMapItem(location: CLLocation(latitude: 36.0, longitude: 140.0), address: nil)

        let target = SidebarSearchInteraction.highlightedTarget(in: [first, second], highlightedIndex: 99)

        XCTAssertTrue(target === first)
    }
}
