import SwiftUI
import MapKit

struct SidebarView: View {

    fileprivate enum LocationInputMode {
        case map, lightPollutionMap
    }

    @ObservedObject var locationController: LocationController
    @ObservedObject var lightPollutionService: LightPollutionService
    @Binding var selectedDate: Date
    @State private var searchState = SidebarSearchState()
    @State private var locationInputMode: LocationInputMode = .map
    @FocusState private var isSearchFocused: Bool
    /// パン中の SwiftUI 再描画を発生させずにビューポートを保持する参照型コンテナ
    @State private var viewport = ViewportBox()
    @State private var mapKitSyncTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            locationSection
            Divider()
            dateSection
            Spacer()
        }
        .padding(.horizontal, Layout.sidebarHorizontalPadding)
        .padding(.vertical, Layout.sidebarVerticalPadding)
    }

    // MARK: - Location Section

    private var locationSection: some View {
        locationSectionContent
            .onAppear(perform: handleLocationSectionAppear)
            .onChange(of: locationController.locationUpdateID) {
                handleLocationUpdateIDChanged()
            }
            .onChange(of: locationInputMode) {
                handleLocationInputModeChanged()
            }
            .alert(
                "位置情報エラー",
                isPresented: locationErrorAlertBinding,
                presenting: locationController.locationError
            ) { _ in
                Button("OK", action: clearLocationError)
            } message: { error in
                Text(error.localizedDescription)
            }
    }

    private var locationSectionContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("場所", systemImage: AppIcons.Navigation.locationPin)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            mapModePickerRow
            searchField
            searchResultsList
            mapView
            selectedLocationLabel
        }
    }

    private var locationErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { locationController.locationError != nil },
            set: { isPresented in
                if !isPresented {
                    clearLocationError()
                }
            }
        )
    }

    private func handleLocationSectionAppear() {
        viewport.center = selectedCoordinate
    }

    private func handleLocationUpdateIDChanged() {
        setSearchTextProgrammatically("")
    }

    private func handleLocationInputModeChanged() {
        mapKitSyncTrigger += 1
    }

    private func clearLocationError() {
        locationController.locationError = nil
    }

    private var mapModePickerRow: some View {
        SidebarLocationModePicker(
            locationInputMode: $locationInputMode,
            isLoadingLightPollution: lightPollutionService.isLoading,
            bortleClass: lightPollutionService.bortleClass
        )
    }

    private var searchField: some View {
        SidebarSearchField(
            searchText: $searchState.text,
            isSearching: isSearching,
            isSearchFocused: $isSearchFocused,
            onSubmit: confirmHighlightedOrFirst,
            onSearchTextChanged: handleSearchTextChanged,
            onDownArrow: handleDownArrow,
            onUpArrow: handleUpArrow,
            onEscape: handleEscape
        )
        .onChange(of: searchFocusTrigger, handleSearchFocusTriggerChanged)
    }

    private func handleSearchFocusTriggerChanged() {
        isSearchFocused = true
    }

    private var searchResults: [MKMapItem] {
        locationController.searchResults
    }

    private var hasSearchResults: Bool {
        !searchResults.isEmpty
    }

    private var selectedCoordinate: CLLocationCoordinate2D {
        locationController.selectedLocation
    }

    private var selectedLocationName: String {
        locationController.locationName
    }

    private var isSearching: Bool {
        locationController.isSearching
    }

    private var isLocating: Bool {
        locationController.isLocating
    }

    private var searchFocusTrigger: Int {
        locationController.searchFocusTrigger
    }

    private var currentLocationCenterTrigger: Int {
        locationController.currentLocationCenterTrigger
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if hasSearchResults {
            SidebarSearchResultsList(
                searchResults: searchResults,
                highlightedIndex: searchState.highlightedIndex,
                onSelect: confirmSelection
            )
        } else if SidebarSearchInteraction.shouldShowEmptyState(
            searchText: searchState.text,
            isSearching: isSearching,
            hasResults: hasSearchResults
        ) {
            ContentUnavailableView.search(text: searchState.text)
                .padding(.vertical, Spacing.xs)
        }
    }

    private var mapView: some View {
        MapLocationPicker(
            selectedCoordinate: selectedCoordinate,
            onSelect: handleMapCoordinateSelection,
            syncState: mapSyncState,
            onRegionChange: handleMapRegionChanged,
            showLightPollution: shouldShowLightPollutionOverlay,
            onCurrentLocation: handleCurrentLocationRequest,
            isLocating: isLocating,
            centerTrigger: currentLocationCenterTrigger
        )
        .equatable()
    }

    private var mapSyncState: MapKitSyncState {
        MapKitSyncState(
            trigger: mapKitSyncTrigger,
            center: viewport.center,
            span: viewport.span
        )
    }

    private var shouldShowLightPollutionOverlay: Bool {
        locationInputMode == .lightPollutionMap
    }

    private func handleMapCoordinateSelection(_ coordinate: CLLocationCoordinate2D) {
        locationController.selectCoordinate(coordinate)
    }

    private func handleMapRegionChanged(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        viewport.center = center
        viewport.span = span
    }

    private func handleCurrentLocationRequest() {
        locationController.requestCurrentLocation()
    }

    private var selectedLocationLabel: some View {
        SidebarSelectedLocationSummaryView(
            locationName: selectedLocationName,
            coordinate: selectedCoordinate
        )
    }

    // MARK: - Search Helpers

    /// onChange の再検索を抑制しながら検索テキストをコード側から更新する
    private func setSearchTextProgrammatically(_ text: String) {
        _ = searchState.setProgrammaticText(text)
    }

    private func resetSearchSelectionAndFocus() {
        searchState.clearHighlight()
        isSearchFocused = false
    }

    /// ハイライト中の候補（なければ先頭）を確定する
    private func confirmHighlightedOrFirst() {
        let target = SidebarSearchInteraction.highlightedTarget(
            in: searchResults,
            highlightedIndex: searchState.highlightedIndex
        )
        if let item = target {
            confirmSelection(item)
        }
    }

    /// 候補を選択して検索状態をリセットする
    private func confirmSelection(_ item: MKMapItem) {
        locationController.select(item)
        setSearchTextProgrammatically(item.name ?? "")
        resetSearchSelectionAndFocus()
    }

    private func handleDownArrow() -> KeyPress.Result {
        searchState.highlightedIndex = SidebarSearchInteraction.nextHighlightedIndex(
            current: searchState.highlightedIndex,
            totalResults: searchResults.count
        )
        return .handled
    }

    private func handleUpArrow() -> KeyPress.Result {
        searchState.highlightedIndex = SidebarSearchInteraction.previousHighlightedIndex(current: searchState.highlightedIndex)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        setSearchTextProgrammatically("")
        resetSearchSelectionAndFocus()
        return .handled
    }

    private func handleSearchTextChanged() {
        searchState.clearHighlight()
        if searchState.consumeSearchSuppression() {
            return
        }
        locationController.search(query: searchState.text)
    }

    // MARK: - Date Section

    private var dateSection: some View {
        SidebarDateSection(selectedDate: $selectedDate)
    }
}

private struct SidebarSearchState {
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

private enum SidebarSearchInteraction {
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

private struct SidebarSearchField: View {
    @Binding var searchText: String
    let isSearching: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onSearchTextChanged: () -> Void
    let onDownArrow: () -> KeyPress.Result
    let onUpArrow: () -> KeyPress.Result
    let onEscape: () -> KeyPress.Result

    var body: some View {
        TextField("場所を検索...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused(isSearchFocused)
            .accessibilityLabel("場所を検索")
            .overlay(alignment: .trailing) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, Spacing.xs)
                }
            }
            .onSubmit(onSubmit)
            .onChange(of: searchText, onSearchTextChanged)
            .onKeyPress(.downArrow, action: onDownArrow)
            .onKeyPress(.upArrow, action: onUpArrow)
            .onKeyPress(.escape, action: onEscape)
    }
}

private extension SidebarView {
    struct SidebarLocationModePicker: View {
        @Binding private var locationInputMode: LocationInputMode
        let isLoadingLightPollution: Bool
        let bortleClass: Double?

        init(
            locationInputMode: Binding<LocationInputMode>,
            isLoadingLightPollution: Bool,
            bortleClass: Double?
        ) {
            self._locationInputMode = locationInputMode
            self.isLoadingLightPollution = isLoadingLightPollution
            self.bortleClass = bortleClass
        }

        var body: some View {
            HStack(spacing: Spacing.xs) {
                Picker("", selection: $locationInputMode) {
                    Text("地図").tag(LocationInputMode.map)
                    Text("光害").tag(LocationInputMode.lightPollutionMap)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("地図表示モード")

                Spacer()

                if locationInputMode == .lightPollutionMap {
                    SidebarBortleLabel(isLoading: isLoadingLightPollution, bortleClass: bortleClass)
                }
            }
        }
    }
}

private struct SidebarBortleLabel: View {
    let isLoading: Bool
    let bortleClass: Double?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("光害データを取得中")
            } else if let bortleClass {
                Text(String(format: "Bortle %.0f", bortleClass))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color(for: bortleClass))
                    .accessibilityLabel(String(format: "光害レベル: Bortle %.0f", bortleClass))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("光害データなし")
            }
        }
        .frame(width: 62, alignment: .trailing)
    }

    private func color(for bortleClass: Double) -> Color {
        switch bortleClass {
        case ..<4:  return .green
        case ..<6:  return .yellow
        case ..<8:  return .orange
        default:    return .red
        }
    }
}

private struct SidebarSelectedLocationSummaryView: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Navigation.locationPinPlain)
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(locationName)
                    .font(.headline)
            }
            Text(String(format: "%.4f°, %.4f°", coordinate.latitude, coordinate.longitude))
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(format: "緯度%.4f度、経度%.4f度", coordinate.latitude, coordinate.longitude))
        }
    }
}

private struct SidebarDateSection: View {
    @Binding var selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("日付", systemImage: AppIcons.Navigation.calendar)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            CalendarView(selectedDate: $selectedDate)
                .padding(.horizontal, -Layout.sidebarHorizontalPadding)
        }
    }
}

private struct SidebarSearchResultsList: View {
    let searchResults: [MKMapItem]
    let highlightedIndex: Int
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(searchResults.prefix(SidebarSearchInteraction.maxVisibleResults).enumerated()), id: \.offset) { index, item in
                searchResultRow(item: item, index: index)
                Divider()
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
    }

    private func searchResultRow(item: MKMapItem, index: Int) -> some View {
        Button { onSelect(item) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name ?? "Unknown")
                    .font(.body)
                    .foregroundStyle(.primary)
                if let address = item.address {
                    Text(address.shortAddress ?? address.fullAddress)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs / 2)
            .contentShape(Rectangle())
            .background(
                highlightedIndex == index ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("場所を選択: \(item.name ?? "Unknown")")
    }
}
