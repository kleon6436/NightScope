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
            selectedLocationRow
            favoritesSection
        }
    }

    private var locationErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.locationError != nil },
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
            isLoadingLightPollution: viewModel.isLightPollutionLoading,
            bortleClass: viewModel.lightPollutionBortleClass
        )
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
        switch viewModel.searchPresentation {
        case .hidden, .loading:
            EmptyView()
        case .results(let results):
            SidebarSearchResultsList(
                searchResults: results,
                highlightedIndex: highlightedIndex,
                onSelect: confirmSelection
            )
        case .empty(let query):
            ContentUnavailableView.search(text: query)
                .padding(.vertical, Spacing.xs)
        case .error(let query, let message):
            ContentUnavailableView {
                Label("場所を検索できませんでした", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text(L10n.format("\"%@\" の検索に失敗しました。%@", query, message))
            } actions: {
                Button("再試行") {
                    viewModel.retrySearch()
                }
            }
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
            viewingDirection: starMapViewModel.viewingDirection,
            mapMinHeight: viewModel.dynamicMapMinHeight,
            mapMaxHeight: viewModel.dynamicMapMaxHeight
        )
        .equatable()
    }

    private var mapSyncState: MapKitSyncState {
        // 地図と光害オーバーレイは同じ MKMapView を使い続けるため、
        // モード切り替え時に viewModel 側の古い viewport を再適用しない。
        MapKitSyncState(
            trigger: 0,
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

    private var selectedLocationRow: some View {
        HStack {
            selectedLocationLabel
            Spacer()
            Button {
                viewModel.toggleCurrentLocationFavorite()
            } label: {
                Image(systemName: viewModel.isCurrentLocationFavorited ? "star.fill" : "star")
                    .foregroundStyle(viewModel.isCurrentLocationFavorited ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                viewModel.isCurrentLocationFavorited ? L10n.tr("お気に入りから削除") : L10n.tr("お気に入りに追加")
            )
            .accessibilityHint(L10n.tr("現在の場所をお気に入りに保存します"))
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !viewModel.favorites.isEmpty {
            SidebarFavoritesListView(
                favorites: viewModel.favorites,
                onSelect: viewModel.selectFavorite,
                onDelete: viewModel.removeFavorite
            )
        }
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
        SidebarDateSection(selectedDate: $selectedDate, timeZone: viewModel.selectedTimeZone, cellHeight: viewModel.calendarCellHeight)
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
        TextField("場所を検索", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused(isSearchFocused)
            .accessibilityLabel(L10n.tr("場所を検索"))
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
                .accessibilityLabel(L10n.tr("地図表示モード"))

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
                    .accessibilityLabel(L10n.tr("光害データを取得中"))
            } else if let bortleClass {
                Text(String(format: "Bortle %.0f", bortleClass))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color(for: bortleClass))
                    .accessibilityLabel(L10n.format("光害レベル: Bortle %.0f", bortleClass))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.tr("光害データなし"))
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
        SelectedLocationSummaryContent(locationName: locationName, coordinate: coordinate)
    }
}

private struct SidebarDateSection: View {
    @Binding var selectedDate: Date
    let timeZone: TimeZone
    var cellHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("日付", systemImage: AppIcons.Navigation.calendar)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            CalendarView(selectedDate: $selectedDate, timeZone: timeZone, cellHeight: cellHeight)
                .padding(.horizontal, -Layout.sidebarHorizontalPadding)
        }
    }
}

private struct SidebarSearchResultsList: View {
    let searchResults: [MKMapItem]
    let highlightedIndex: Int
    let onSelect: (MKMapItem) -> Void

    private static let rowHeight: CGFloat = 52
    private static let maxVisibleRows: CGFloat = 2

    private var effectiveMaxHeight: CGFloat {
        let items = searchResults.prefix(SidebarSearchInteraction.maxVisibleResults)
        return min(CGFloat(items.count) * Self.rowHeight, Self.rowHeight * Self.maxVisibleRows)
    }

    var body: some View {
        let items = Array(searchResults.prefix(SidebarSearchInteraction.maxVisibleResults).enumerated())

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.offset) { index, item in
                    searchResultRow(item: item, index: index)
                    if index < items.count - 1 { Divider() }
                }
            }
        }
        .frame(maxHeight: effectiveMaxHeight)
        .scrollBounceBehavior(.basedOnSize)
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
    }

    private func searchResultRow(item: MKMapItem, index: Int) -> some View {
        SearchResultRowButton(item: item, isHighlighted: highlightedIndex == index, onSelect: onSelect)
    }
}

private struct SearchResultRowButton: View {
    let item: MKMapItem
    let isHighlighted: Bool
    let onSelect: (MKMapItem) -> Void
    @State private var isHovered = false

    var body: some View {
        Button { onSelect(item) } label: {
            LocationSearchResultContent(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs / 2)
                .contentShape(Rectangle())
                .background(
                    isHighlighted ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(
            L10n.format("場所を選択: %@", item.name ?? L10n.tr("不明"))
        )
    }
}

private struct SidebarFavoritesListView: View {
    let favorites: [FavoriteLocation]
    let onSelect: (FavoriteLocation) -> Void
    let onDelete: (FavoriteLocation) -> Void

    private static let rowHeight: CGFloat = 44
    private static let maxVisibleRows: CGFloat = 2

    /// 件数に応じた表示高さ。上限を超えるとスクロールになる。
    private var effectiveMaxHeight: CGFloat {
        min(CGFloat(favorites.count) * Self.rowHeight, Self.rowHeight * Self.maxVisibleRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("お気に入り", systemImage: "star.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ScrollView {
                favoritesContent
            }
            .frame(maxHeight: effectiveMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
            .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        }
    }

    private var favoritesContent: some View {
        VStack(spacing: 0) {
            ForEach(favorites) { favorite in
                FavoriteRowButton(
                    favorite: favorite,
                    onSelect: onSelect,
                    onDelete: onDelete
                )

                if favorite.id != favorites.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct FavoriteRowButton: View {
    let favorite: FavoriteLocation
    let onSelect: (FavoriteLocation) -> Void
    let onDelete: (FavoriteLocation) -> Void
    @State private var isHovered = false

    var body: some View {
        Button { onSelect(favorite) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name)
                        .font(.callout)
                        .lineLimit(1)
                    Text(
                        L10n.format(
                            "%.4f, %.4f",
                            favorite.latitude,
                            favorite.longitude
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs / 2)
            .contentShape(Rectangle())
            .background(
                isHovered ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(role: .destructive) {
                onDelete(favorite)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .accessibilityLabel(
            L10n.format("お気に入りの場所: %@", favorite.name)
        )
    }
}
