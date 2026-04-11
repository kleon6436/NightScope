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
protocol LocationProviding: AnyObject, ObservableObject {
    var selectedLocation: CLLocationCoordinate2D { get set }
    var locationName: String { get set }
    var locationUpdateID: UUID { get }
    var locationUpdateIDPublisher: Published<UUID>.Publisher { get }
    var locationNamePublisher: Published<String>.Publisher { get }
    var anyChangePublisher: AnyPublisher<Void, Never> { get }
    var searchResults: [MKMapItem] { get set }
    var isSearching: Bool { get set }
    var isLocating: Bool { get set }
    var locationError: LocationController.LocationError? { get set }
    var searchFocusTrigger: Int { get set }
    var currentLocationCenterTrigger: Int { get set }

    func requestCurrentLocation()
    func search(query: String)
    func select(_ mapItem: MKMapItem)
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D)
}
