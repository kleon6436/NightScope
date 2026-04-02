import SwiftUI
import MapKit

struct SidebarView: View {

    @StateObject var viewModel: SidebarViewModel
    @Binding var selectedDate: Date
    @FocusState private var isSearchFocused: Bool

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
            .onAppear {
                viewModel.handleLocationSectionAppear(selectedCoordinate: viewModel.selectedCoordinate)
            }
            .onChange(of: viewModel.locationController.locationUpdateID) {
                viewModel.handleLocationUpdateIDChanged()
            }
            .onChange(of: viewModel.locationInputMode) {
                viewModel.handleLocationInputModeChanged()
            }
            .alert(
                "位置情報エラー",
                isPresented: locationErrorAlertBinding,
                presenting: viewModel.locationController.locationError
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
            get: { viewModel.locationController.locationError != nil },
            set: { isPresented in
                if !isPresented {
                    clearLocationError()
                }
            }
        )
    }

    private func handleLocationSectionAppear() {
        viewModel.handleLocationSectionAppear(selectedCoordinate: viewModel.selectedCoordinate)
    }

    private func handleLocationUpdateIDChanged() {
        viewModel.handleLocationUpdateIDChanged()
    }

    private func handleLocationInputModeChanged() {
        viewModel.handleLocationInputModeChanged()
    }

    private func clearLocationError() {
        viewModel.clearLocationError()
    }

    private var mapModePickerRow: some View {
        SidebarLocationModePicker(
            locationInputMode: $viewModel.locationInputMode,
            isLoadingLightPollution: viewModel.lightPollutionService.isLoading,
            bortleClass: viewModel.lightPollutionService.bortleClass
        )
    }

    private var searchField: some View {
        SidebarSearchField(
            searchText: $viewModel.searchState.text,
            isSearching: viewModel.isSearching,
            isSearchFocused: $isSearchFocused,
            onSubmit: confirmHighlightedOrFirst,
            onSearchTextChanged: viewModel.handleSearchTextChanged,
            onDownArrow: viewModel.handleDownArrow,
            onUpArrow: viewModel.handleUpArrow,
            onEscape: viewModel.handleEscape
        )
        .onChange(of: viewModel.searchFocusTrigger) { handleSearchFocusTriggerChanged() }
    }

    private func handleSearchFocusTriggerChanged() {
        isSearchFocused = true
    }

    private var searchResults: [MKMapItem] {
        viewModel.searchResults
    }

    private var hasSearchResults: Bool {
        !searchResults.isEmpty
    }

    private var selectedCoordinate: CLLocationCoordinate2D {
        viewModel.selectedCoordinate
    }

    private var selectedLocationName: String {
        viewModel.selectedLocationName
    }

    private var isSearching: Bool {
        viewModel.isSearching
    }

    private var isLocating: Bool {
        viewModel.isLocating
    }

    private var searchFocusTrigger: Int {
        viewModel.searchFocusTrigger
    }

    private var currentLocationCenterTrigger: Int {
        viewModel.currentLocationCenterTrigger
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if hasSearchResults {
            SidebarSearchResultsList(
                searchResults: searchResults,
                highlightedIndex: viewModel.searchState.highlightedIndex,
                onSelect: confirmSelection
            )
        } else if SidebarSearchInteraction.shouldShowEmptyState(
            searchText: viewModel.searchState.text,
            isSearching: isSearching,
            hasResults: hasSearchResults
        ) {
            ContentUnavailableView.search(text: viewModel.searchState.text)
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
            trigger: viewModel.mapKitSyncTrigger,
            center: viewModel.viewport.center,
            span: viewModel.viewport.span
        )
    }

    private var shouldShowLightPollutionOverlay: Bool {
        viewModel.locationInputMode == .lightPollutionMap
    }

    private func handleMapCoordinateSelection(_ coordinate: CLLocationCoordinate2D) {
        viewModel.locationController.selectCoordinate(coordinate)
    }

    private func handleMapRegionChanged(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        viewModel.viewport.center = center
        viewModel.viewport.span = span
    }

    private func handleCurrentLocationRequest() {
        viewModel.locationController.requestCurrentLocation()
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
        _ = viewModel.searchState.setProgrammaticText(text)
    }

    private func resetSearchSelectionAndFocus() {
        viewModel.searchState.clearHighlight()
        isSearchFocused = false
    }

    /// ハイライト中の候補（なければ先頭）を確定する
    private func confirmHighlightedOrFirst() {
        let target = SidebarSearchInteraction.highlightedTarget(
            in: searchResults,
            highlightedIndex: viewModel.searchState.highlightedIndex
        )
        if let item = target {
            confirmSelection(item)
        }
    }

    /// 候補を選択して検索状態をリセットする
    private func confirmSelection(_ item: MKMapItem) {
        viewModel.locationController.select(item)
        setSearchTextProgrammatically(item.name ?? "")
        resetSearchSelectionAndFocus()
    }

    private func handleDownArrow() -> KeyPress.Result {
        viewModel.searchState.highlightedIndex = SidebarSearchInteraction.nextHighlightedIndex(
            current: viewModel.searchState.highlightedIndex,
            totalResults: searchResults.count
        )
        return .handled
    }

    private func handleUpArrow() -> KeyPress.Result {
        viewModel.searchState.highlightedIndex = SidebarSearchInteraction.previousHighlightedIndex(current: viewModel.searchState.highlightedIndex)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        setSearchTextProgrammatically("")
        resetSearchSelectionAndFocus()
        return .handled
    }

    private func handleSearchTextChanged() {
        viewModel.searchState.clearHighlight()
        if viewModel.searchState.consumeSearchSuppression() {
            return
        }
        viewModel.locationController.search(query: viewModel.searchState.text)
    }

    // MARK: - Date Section

    private var dateSection: some View {
        SidebarDateSection(selectedDate: $selectedDate)
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
