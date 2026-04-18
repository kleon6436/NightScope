import SwiftUI
import MapKit
import Combine

enum LocationInputMode: String, CaseIterable, Identifiable {
    case map
    case lightPollutionMap

    var id: String { rawValue }
}

@MainActor
final class SidebarViewModel: ObservableObject {
    enum SearchTextSelectionBehavior {
        case fillSelectionName
        case clear
    }

    enum SearchPresentation {
        case hidden
        case loading([MKMapItem])
        case results([MKMapItem])
        case empty(String)
        case error(query: String, message: String)
    }

    private enum PendingLocationUpdateBehavior {
        case preserveCommittedSelection(String)
        case clearSearch
    }

    private enum ViewportUpdateThresholds {
        static let coordinateEpsilon = 0.00005
        static let spanEpsilon = 0.00005
    }

    @Published var viewport = ViewportBox()
    @Published var searchText = ""
    @Published private(set) var isShowingCommittedSelection = false
    @Published private(set) var searchState: LocationSearchState
    @Published private(set) var isLocating: Bool
    @Published private(set) var locationError: LocationController.LocationError?
    @Published private(set) var selectedCoordinate: CLLocationCoordinate2D
    @Published private(set) var selectedLocationName: String
    @Published private(set) var searchFocusTrigger: Int
    @Published private(set) var currentLocationCenterTrigger: Int
    @Published private(set) var lightPollutionBortleClass: Double?
    @Published private(set) var isLightPollutionLoading: Bool
    @Published private(set) var hasLightPollutionFetchFailed: Bool
    @Published private(set) var selectedTimeZone: TimeZone

    let locationController: any LocationProviding
    let lightPollutionService: any LightPollutionProviding
    private var cancellables = Set<AnyCancellable>()
    private var pendingLocationUpdateBehavior: PendingLocationUpdateBehavior?

    var isSearching: Bool {
        searchState.isSearching
    }

    var searchResults: [MKMapItem] {
        searchState.results
    }

    var searchPresentation: SearchPresentation {
        guard !isShowingCommittedSelection else { return .hidden }

        switch searchState.phase {
        case .idle:
            return .hidden
        case .loading:
            return .loading(searchState.results)
        case .results:
            return searchState.results.isEmpty ? .hidden : .results(searchState.results)
        case .empty:
            return .empty(searchState.query)
        case .failure:
            return .error(
                query: searchState.query,
                message: searchState.errorMessage ?? "場所を検索できませんでした。"
            )
        }
    }

    init(locationController: some LocationProviding, lightPollutionService: some LightPollutionProviding) {
        self.locationController = locationController
        self.lightPollutionService = lightPollutionService
        self.searchState = locationController.searchState
        self.isLocating = locationController.isLocating
        self.locationError = locationController.locationError
        self.selectedCoordinate = locationController.selectedLocation
        self.selectedLocationName = locationController.locationName
        self.searchFocusTrigger = locationController.searchFocusTrigger
        self.currentLocationCenterTrigger = locationController.currentLocationCenterTrigger
        self.lightPollutionBortleClass = lightPollutionService.bortleClass
        self.isLightPollutionLoading = lightPollutionService.isLoading
        self.hasLightPollutionFetchFailed = lightPollutionService.fetchFailed
        self.selectedTimeZone = locationController.selectedTimeZone

        locationController.searchStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.searchState = $0 }
            .store(in: &cancellables)

        locationController.isLocatingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isLocating = $0 }
            .store(in: &cancellables)

        locationController.locationErrorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.locationError = $0 }
            .store(in: &cancellables)

        locationController.locationNamePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectedLocationName = $0 }
            .store(in: &cancellables)

        locationController.searchFocusTriggerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.searchFocusTrigger = $0 }
            .store(in: &cancellables)

        locationController.currentLocationCenterTriggerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentLocationCenterTrigger = $0 }
            .store(in: &cancellables)

        locationController.selectedTimeZonePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectedTimeZone = $0 }
            .store(in: &cancellables)

        locationController.selectedLocationPublisher
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] coordinate in
                self?.selectedCoordinate = coordinate
                self?.applyPendingLocationUpdateBehavior()
            }
            .store(in: &cancellables)

        lightPollutionService.bortleClassPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lightPollutionBortleClass = $0 }
            .store(in: &cancellables)

        lightPollutionService.isLoadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isLightPollutionLoading = $0 }
            .store(in: &cancellables)

        lightPollutionService.fetchFailedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.hasLightPollutionFetchFailed = $0 }
            .store(in: &cancellables)
    }

    func handleLocationSectionAppear(selectedCoordinate: CLLocationCoordinate2D) {
        viewport.center = selectedCoordinate
    }

    func clearLocationError() {
        locationController.locationError = nil
    }

    func updateSearchText(_ searchText: String) {
        guard self.searchText != searchText else { return }
        self.searchText = searchText
        isShowingCommittedSelection = false
        locationController.search(query: searchText)
    }

    func selectSearchResult(_ item: MKMapItem, searchTextBehavior: SearchTextSelectionBehavior) {
        let locationName = item.name ?? ""
        pendingLocationUpdateBehavior = pendingBehavior(
            for: searchTextBehavior,
            selectedLocationName: locationName
        )
        applySearchSelectionPresentation(
            for: searchTextBehavior,
            selectedLocationName: locationName
        )
        locationController.select(item)
    }

    func clearSearch() {
        pendingLocationUpdateBehavior = nil
        resetSearchPresentation()
        locationController.clearSearch()
    }

    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        pendingLocationUpdateBehavior = .clearSearch
        resetSearchPresentation()
        locationController.selectCoordinate(coordinate)
    }

    func requestCurrentLocation() {
        pendingLocationUpdateBehavior = .clearSearch
        // 同一座標が返ると selectedLocation が変化せず applyPendingLocationUpdateBehavior()
        // が呼ばれない経路があるため、ここで即時リセットする。
        // pendingLocationUpdateBehavior は座標変更経路でも再度 .clearSearch を適用するため保持。
        resetSearchPresentation()
        locationController.requestCurrentLocation()
    }

    func prepareForLocationSettingsRecovery() {
        locationController.prepareForSettingsRecovery()
    }

    func refreshLocationAuthorizationState() {
        locationController.refreshAuthorizationState()
    }

    func updateViewportIfNeeded(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let currentCenter = viewport.center
        let currentSpan = viewport.span

        let shouldUpdateCenter =
            abs(currentCenter.latitude - center.latitude) > ViewportUpdateThresholds.coordinateEpsilon
            || abs(currentCenter.longitude - center.longitude) > ViewportUpdateThresholds.coordinateEpsilon

        let shouldUpdateSpan =
            abs(currentSpan.latitudeDelta - span.latitudeDelta) > ViewportUpdateThresholds.spanEpsilon
            || abs(currentSpan.longitudeDelta - span.longitudeDelta) > ViewportUpdateThresholds.spanEpsilon

        if shouldUpdateCenter {
            viewport.center = center
        }
        if shouldUpdateSpan {
            viewport.span = span
        }
    }

    func retrySearch() {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }
        isShowingCommittedSelection = false
        locationController.search(query: normalizedQuery)
    }

    func retryLightPollution() {
        Task {
            await lightPollutionService.fetch(
                latitude: selectedCoordinate.latitude,
                longitude: selectedCoordinate.longitude
            )
        }
    }

    private func applyPendingLocationUpdateBehavior() {
        let behavior = pendingLocationUpdateBehavior ?? .clearSearch
        pendingLocationUpdateBehavior = nil

        switch behavior {
        case .preserveCommittedSelection(let selectedLocationName):
            searchText = selectedLocationName
            isShowingCommittedSelection = true
        case .clearSearch:
            resetSearchPresentation()
        }
    }

    private func pendingBehavior(
        for searchTextBehavior: SearchTextSelectionBehavior,
        selectedLocationName: String
    ) -> PendingLocationUpdateBehavior {
        switch searchTextBehavior {
        case .fillSelectionName:
            return .preserveCommittedSelection(selectedLocationName)
        case .clear:
            return .clearSearch
        }
    }

    private func applySearchSelectionPresentation(
        for searchTextBehavior: SearchTextSelectionBehavior,
        selectedLocationName: String
    ) {
        switch searchTextBehavior {
        case .fillSelectionName:
            searchText = selectedLocationName
            isShowingCommittedSelection = true
        case .clear:
            resetSearchPresentation()
        }
    }

    private func resetSearchPresentation() {
        searchText = ""
        isShowingCommittedSelection = false
    }
}

enum SidebarSearchInteraction {
    static let noSelectionIndex = -1
    static let maxVisibleResults = 5

    static func highlightedTarget(in results: [MKMapItem], highlightedIndex: Int) -> MKMapItem? {
        if results.indices.contains(highlightedIndex) {
            return results[highlightedIndex]
        }
        return results.first
    }

    static func nextHighlightedIndex(current: Int, totalResults: Int) -> Int {
        let count = min(totalResults, maxVisibleResults)
        guard count > 0 else { return current }
        return min(current + 1, count - 1)
    }

    static func previousHighlightedIndex(current: Int) -> Int {
        max(current - 1, noSelectionIndex)
    }

}
