import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
struct AppRootDependencies {
    let appController: AppController
    let observationModePreference: ObservationModePreference
    let sidebarViewModel: SidebarViewModel
    let detailViewModel: DetailViewModel
    let starMapViewModel: StarMapViewModel
    let comparisonController: ComparisonController
    let dashboardCommandBridge: DashboardCommandBridge

    init(
        appController: AppController,
        observationModePreference: ObservationModePreference = ObservationModePreference(),
        comparisonController: ComparisonController? = nil,
        dashboardCommandBridge: DashboardCommandBridge? = nil
    ) {
        self.appController = appController
        self.observationModePreference = observationModePreference
        self.sidebarViewModel = SidebarViewModel(
            locationController: appController.locationController,
            lightPollutionService: appController.lightPollutionService,
            favoriteStore: appController.favoriteStore
        )
        self.detailViewModel = DetailViewModel(
            appController: appController,
            observationModePreference: observationModePreference
        )
        self.starMapViewModel = StarMapViewModel(appController: appController)
        self.comparisonController = comparisonController ?? ComparisonController(
            favoriteStore: appController.favoriteStore,
            weatherService: appController.weatherService,
            lightPollutionService: appController.lightPollutionService,
            calculationService: appController.calculationService
        )
        self.dashboardCommandBridge = dashboardCommandBridge ?? DashboardCommandBridge()
        appController.bindDashboardCommandBridge(self.dashboardCommandBridge) { [detailViewModel] date in
            detailViewModel.selectedDate = date
        }
    }

    static func makeDefault() -> AppRootDependencies {
        AppRootDependencies(appController: AppController())
    }
}

@MainActor
struct DashboardSceneDependencies {
    let appController: AppController
    let dashboardCommandBridge: DashboardCommandBridge
}

@MainActor
final class AppRootStore: ObservableObject {
    let appController: AppController
    let observationModePreference: ObservationModePreference
    let sidebarViewModel: SidebarViewModel
    let detailViewModel: DetailViewModel
    let starMapViewModel: StarMapViewModel
    let comparisonController: ComparisonController
    let dashboardCommandBridge: DashboardCommandBridge
    
    @Published private(set) var selectedDate: Date = Date()

    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        self.appController = dependencies.appController
        self.observationModePreference = dependencies.observationModePreference
        self.sidebarViewModel = dependencies.sidebarViewModel
        self.detailViewModel = dependencies.detailViewModel
        self.starMapViewModel = dependencies.starMapViewModel
        self.comparisonController = dependencies.comparisonController
        self.dashboardCommandBridge = dependencies.dashboardCommandBridge
        
        // detailViewModel の日付変化を AppRootStore に伝播させ ContentView を再描画させる
        dependencies.detailViewModel.$selectedDate
            .assign(to: &$selectedDate)
    }
}

@MainActor
protocol LocationProviding: AnyObject, ObservableObject {
    var selectedLocation: CLLocationCoordinate2D { get set }
    var selectedTimeZone: TimeZone { get }
    var locationName: String { get set }
    var locationUpdateID: UUID { get }
    var searchState: LocationSearchState { get set }
    var searchResults: [MKMapItem] { get set }
    var isSearching: Bool { get set }
    var isLocating: Bool { get set }
    var locationError: LocationController.LocationError? { get set }
    var searchFocusTrigger: Int { get set }
    var currentLocationCenterTrigger: Int { get set }
    var selectedLocationPublisher: AnyPublisher<CLLocationCoordinate2D, Never> { get }
    var locationNamePublisher: AnyPublisher<String, Never> { get }
    var searchStatePublisher: AnyPublisher<LocationSearchState, Never> { get }
    var searchResultsPublisher: AnyPublisher<[MKMapItem], Never> { get }
    var isSearchingPublisher: AnyPublisher<Bool, Never> { get }
    var isLocatingPublisher: AnyPublisher<Bool, Never> { get }
    var locationErrorPublisher: AnyPublisher<LocationController.LocationError?, Never> { get }
    var searchFocusTriggerPublisher: AnyPublisher<Int, Never> { get }
    var currentLocationCenterTriggerPublisher: AnyPublisher<Int, Never> { get }
    var selectedTimeZonePublisher: AnyPublisher<TimeZone, Never> { get }

    func requestCurrentLocation()
    func prepareForSettingsRecovery()
    func refreshAuthorizationState()
    func search(query: String)
    func clearSearch()
    func select(_ mapItem: MKMapItem)
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D)
}
