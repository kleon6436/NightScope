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
    private var cancellables: Set<AnyCancellable> = []

    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        self.appController = dependencies.appController
        self.sidebarViewModel = dependencies.sidebarViewModel
        self.detailViewModel = dependencies.detailViewModel
        self.starMapViewModel = dependencies.starMapViewModel
        bindChildChanges()
    }

    private func bindChildChanges() {
        let childPublishers: [AnyPublisher<Void, Never>] = [
            sidebarViewModel.objectWillChange.eraseToAnyPublisher(),
            detailViewModel.objectWillChange.eraseToAnyPublisher(),
            starMapViewModel.objectWillChange.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(childPublishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
