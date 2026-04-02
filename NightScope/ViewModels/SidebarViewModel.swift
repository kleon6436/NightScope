import SwiftUI
import MapKit

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
    @Published var mapKitSyncTrigger = 0

    let locationController: any LocationProviding
    let lightPollutionService: any LightPollutionProviding

    init(locationController: some LocationProviding, lightPollutionService: some LightPollutionProviding) {
        self.locationController = locationController
        self.lightPollutionService = lightPollutionService
    }

    func handleLocationSectionAppear(selectedCoordinate: CLLocationCoordinate2D) {
        viewport.center = selectedCoordinate
    }

    func handleLocationUpdateIDChanged() {
        setSearchTextProgrammatically("")
    }

    func handleLocationInputModeChanged() {
        mapKitSyncTrigger += 1
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

    func handleDownArrow() -> KeyPress.Result {
        searchState.highlightedIndex = SidebarSearchInteraction.nextHighlightedIndex(current: searchState.highlightedIndex, totalResults: locationController.searchResults.count)
        return .handled
    }

    func handleUpArrow() -> KeyPress.Result {
        searchState.highlightedIndex = SidebarSearchInteraction.previousHighlightedIndex(current: searchState.highlightedIndex)
        return .handled
    }

    func handleEscape() -> KeyPress.Result {
        setSearchTextProgrammatically("")
        resetSearchSelectionAndFocus()
        return .handled
    }

    func resetSearchSelectionAndFocus() {
        searchState.clearHighlight()
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
    var suppressNextSearch = false

    @discardableResult
    mutating func setProgrammaticText(_ newText: String) -> Bool {
        guard newText != text else { return false }
        suppressNextSearch = true
        text = newText
        return true
    }

    mutating func clearHighlight() {
        highlightedIndex = SidebarSearchInteraction.noSelectionIndex
    }

    mutating func consumeSearchSuppression() -> Bool {
        guard suppressNextSearch else { return false }
        suppressNextSearch = false
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
