import SwiftUI
import MapKit
import Combine

struct SidebarView: View {

    @StateObject var viewModel: SidebarViewModel
    @ObservedObject var starMapViewModel: StarMapViewModel
    @Binding var selectedDate: Date
    @State private var highlightedIndex = SidebarSearchInteraction.noSelectionIndex
    @FocusState private var isSearchFocused: Bool
    @State private var locationInputMode: LocationInputMode = .map
    @State private var mapViewportSyncTrigger = 0

    init(
        viewModel: SidebarViewModel,
        selectedDate: Binding<Date>,
        starMapViewModel: StarMapViewModel
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.starMapViewModel = starMapViewModel
        self._selectedDate = selectedDate
    }

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
            .alert(
                "位置情報エラー",
                isPresented: locationErrorAlertBinding,
                presenting: viewModel.locationError
            ) { _ in
                Button("OK") {
                    viewModel.clearLocationError()
                }
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
                    viewModel.clearLocationError()
                }
            }
        )
    }

    private var mapModePickerRow: some View {
        SidebarLocationModePicker(
            locationInputMode: Binding(
                get: { locationInputMode },
                set: { locationInputMode = $0 }
            ),
            isLoadingLightPollution: viewModel.lightPollutionService.isLoading,
            bortleClass: viewModel.lightPollutionService.bortleClass
        )
        .onChange(of: locationInputMode) {
            mapViewportSyncTrigger += 1
        }
    }

    private var searchField: some View {
        SidebarSearchField(
            searchText: searchTextBinding,
            isSearching: viewModel.isSearching,
            isSearchFocused: $isSearchFocused,
            onSubmit: confirmHighlightedOrFirst,
            onDownArrow: handleSearchDownArrow,
            onUpArrow: handleSearchUpArrow,
            onEscape: handleSearchEscape
        )
        .onChange(of: viewModel.searchFocusTrigger) {
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if !viewModel.isShowingCommittedSelection && !viewModel.searchResults.isEmpty {
            SidebarSearchResultsList(
                searchResults: viewModel.searchResults,
                highlightedIndex: highlightedIndex,
                onSelect: confirmSelection
            )
        } else if viewModel.shouldShowSearchEmptyState(
            isShowingCommittedSelection: viewModel.isShowingCommittedSelection
        ) {
            ContentUnavailableView.search(text: viewModel.searchText)
                .padding(.vertical, Spacing.xs)
        }
    }

    private var mapView: some View {
        MapLocationPicker(
            selectedCoordinate: viewModel.selectedCoordinate,
            onSelect: viewModel.selectCoordinate,
            syncState: mapSyncState,
            onRegionChange: handleMapRegionChanged,
            showLightPollution: shouldShowLightPollutionOverlay,
            onCurrentLocation: viewModel.requestCurrentLocation,
            isLocating: viewModel.isLocating,
            centerTrigger: viewModel.currentLocationCenterTrigger,
            viewingDirection: starMapViewModel.viewingDirection
        )
        .equatable()
    }

    private var mapSyncState: MapKitSyncState {
        MapKitSyncState(
            trigger: mapViewportSyncTrigger,
            center: viewModel.viewport.center,
            span: viewModel.viewport.span
        )
    }

    private var shouldShowLightPollutionOverlay: Bool {
        locationInputMode == .lightPollutionMap
    }

    private func handleMapRegionChanged(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        viewModel.updateViewportIfNeeded(center: center, span: span)
    }

    private var selectedLocationLabel: some View {
        SidebarSelectedLocationSummaryView(
            locationName: viewModel.selectedLocationName,
            coordinate: viewModel.selectedCoordinate
        )
    }

    // MARK: - Search Helpers

    private func resetSearchSelection() {
        highlightedIndex = SidebarSearchInteraction.noSelectionIndex
    }

    /// ハイライト中の候補（なければ先頭）を確定する
    private func confirmHighlightedOrFirst() {
        let target = SidebarSearchInteraction.highlightedTarget(
            in: viewModel.searchResults,
            highlightedIndex: highlightedIndex
        )
        if let item = target {
            confirmSelection(item)
        }
    }

    /// 候補を選択して検索状態をリセットする
    private func confirmSelection(_ item: MKMapItem) {
        viewModel.selectSearchResult(item, searchTextBehavior: .fillSelectionName)
        resetSearchSelection()
        isSearchFocused = false
    }

    private func handleSearchDownArrow() -> KeyPress.Result {
        highlightedIndex = SidebarSearchInteraction.nextHighlightedIndex(
            current: highlightedIndex,
            totalResults: viewModel.searchResults.count
        )
        return .handled
    }

    private func handleSearchUpArrow() -> KeyPress.Result {
        highlightedIndex = SidebarSearchInteraction.previousHighlightedIndex(
            current: highlightedIndex
        )
        return .handled
    }

    private func handleSearchEscape() -> KeyPress.Result {
        clearSearchInteraction()
        resetSearchSelection()
        isSearchFocused = false
        return .handled
    }

    private func clearSearchInteraction() {
        highlightedIndex = SidebarSearchInteraction.noSelectionIndex
        viewModel.clearSearch()
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
            .onKeyPress(.downArrow, action: onDownArrow)
            .onKeyPress(.upArrow, action: onUpArrow)
            .onKeyPress(.escape, action: onEscape)
    }
}

private extension SidebarView {
    var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.searchText },
            set: { newValue in
                highlightedIndex = SidebarSearchInteraction.noSelectionIndex
                viewModel.updateSearchText(newValue)
            }
        )
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
        .frame(width: Layout.sidebarStatusWidth, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
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

    private static let rowHeight: CGFloat = 52
    private static let maxVisibleRows: CGFloat = 2.5

    var body: some View {
        let items = Array(searchResults.prefix(SidebarSearchInteraction.maxVisibleResults).enumerated())
        let needsScroll = searchResults.count >= 2

        Group {
            if needsScroll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.offset) { index, item in
                            searchResultRow(item: item, index: index)
                            if index < items.count - 1 { Divider() }
                        }
                    }
                }
                .frame(maxHeight: Self.rowHeight * Self.maxVisibleRows)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.offset) { index, item in
                        searchResultRow(item: item, index: index)
                    }
                }
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
