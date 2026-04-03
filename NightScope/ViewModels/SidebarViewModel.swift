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
    @Published var searchState = SidebarSearchState()
    @Published var locationInputMode: LocationInputMode = .map
    @Published var viewport = ViewportBox()
    @Published var mapViewportSyncTrigger = 0

    let locationController: any LocationProviding
    let lightPollutionService: any LightPollutionProviding
    private var cancellables = Set<AnyCancellable>()

    init(locationController: some LocationProviding, lightPollutionService: some LightPollutionProviding) {
        self.locationController = locationController
        self.lightPollutionService = lightPollutionService

        // locationController の変化を SidebarViewModel に伝播（View 更新サイクル外で実行）
        locationController.anyChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // locationUpdateID の変化を Combine で検知し、検索状態をクリア
        // View の onChange で処理するとビュー更新コミットフェーズ中に @Published を変更してしまうため
        locationController.locationUpdateIDPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleLocationUpdateIDChanged() }
            .store(in: &cancellables)
    }

    func handleLocationSectionAppear(selectedCoordinate: CLLocationCoordinate2D) {
        viewport.center = selectedCoordinate
    }

    func handleLocationUpdateIDChanged() {
        setSearchTextProgrammatically("")
    }

    func handleLocationInputModeChanged() {
        mapViewportSyncTrigger += 1
    }

    func clearLocationError() {
        locationController.locationError = nil
    }

    func handleSearchTextChanged() {
        searchState.clearHighlight()
        if searchState.consumeSearchSuppression() {
            return
        }
        locationController.search(query: searchState.text)
    }

    func setSearchTextProgrammatically(_ text: String) {
        if searchState.setProgrammaticText(text) {
            locationController.searchResults = []
        }
    }

    func clearSearchState() {
        locationController.searchResults = []
        locationController.isSearching = false
    }

    var isSearching: Bool { locationController.isSearching }
    var isLocating: Bool { locationController.isLocating }
    var searchResults: [MKMapItem] { locationController.searchResults }

    var selectedCoordinate: CLLocationCoordinate2D { locationController.selectedLocation }
    var selectedLocationName: String { locationController.locationName }

    var searchFocusTrigger: Int { locationController.searchFocusTrigger }
    var currentLocationCenterTrigger: Int { locationController.currentLocationCenterTrigger }
}

struct SidebarSearchState {
    var text: String = ""
    var highlightedIndex: Int = SidebarSearchInteraction.noSelectionIndex
    var shouldSuppressNextSearch = false

    @discardableResult
    mutating func setProgrammaticText(_ newText: String) -> Bool {
        guard newText != text else { return false }
        shouldSuppressNextSearch = true
        text = newText
        return true
    }

    mutating func clearHighlight() {
        highlightedIndex = SidebarSearchInteraction.noSelectionIndex
    }

    mutating func consumeSearchSuppression() -> Bool {
        guard shouldSuppressNextSearch else { return false }
        shouldSuppressNextSearch = false
        return true
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

    static func shouldShowEmptyState(searchText: String, isSearching: Bool, hasResults: Bool) -> Bool {
        !hasResults && !isSearching && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
