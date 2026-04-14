import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
struct AppRootDependencies {
    let appController: AppController
    let sidebarViewModel: SidebarViewModel
    let detailViewModel: DetailViewModel
    let starMapViewModel: StarMapViewModel

    init(appController: AppController) {
        self.appController = appController
        self.sidebarViewModel = SidebarViewModel(
            locationController: appController.locationController,
            lightPollutionService: appController.lightPollutionService
        )
        self.detailViewModel = DetailViewModel(appController: appController)
        self.starMapViewModel = StarMapViewModel(appController: appController)
    }

    static func makeDefault() -> AppRootDependencies {
        AppRootDependencies(appController: AppController())
    }
}

@MainActor
final class AppRootStore: ObservableObject {
    let appController: AppController
    let sidebarViewModel: SidebarViewModel
    let detailViewModel: DetailViewModel
    let starMapViewModel: StarMapViewModel
    
    @Published private(set) var selectedDate: Date = Date()

    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        self.appController = dependencies.appController
        self.sidebarViewModel = dependencies.sidebarViewModel
        self.detailViewModel = dependencies.detailViewModel
        self.starMapViewModel = dependencies.starMapViewModel
        
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
    var searchResults: [MKMapItem] { get set }
    var isSearching: Bool { get set }
    var isLocating: Bool { get set }
    var locationError: LocationController.LocationError? { get set }
    var searchFocusTrigger: Int { get set }
    var currentLocationCenterTrigger: Int { get set }
    var selectedLocationPublisher: AnyPublisher<CLLocationCoordinate2D, Never> { get }
    var locationNamePublisher: AnyPublisher<String, Never> { get }
    var searchResultsPublisher: AnyPublisher<[MKMapItem], Never> { get }
    var isSearchingPublisher: AnyPublisher<Bool, Never> { get }
    var isLocatingPublisher: AnyPublisher<Bool, Never> { get }
    var locationErrorPublisher: AnyPublisher<LocationController.LocationError?, Never> { get }
    var searchFocusTriggerPublisher: AnyPublisher<Int, Never> { get }
    var currentLocationCenterTriggerPublisher: AnyPublisher<Int, Never> { get }

    func requestCurrentLocation()
    func search(query: String)
    func clearSearch()
    func select(_ mapItem: MKMapItem)
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D)
}
