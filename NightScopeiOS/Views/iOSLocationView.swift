import SwiftUI
import MapKit

@MainActor
struct iOSLocationViewModel {
    private let locationController: any LocationProviding
    private let clearSearchText: (String) -> Void

    init(
        locationController: some LocationProviding,
        clearSearchText: @escaping (String) -> Void
    ) {
        self.locationController = locationController
        self.clearSearchText = clearSearchText
    }

    func selectSearchResult(_ item: MKMapItem) {
        locationController.select(item)
        clearSearchText("")
    }

    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        locationController.selectCoordinate(coordinate)
    }

    func requestCurrentLocation() {
        locationController.requestCurrentLocation()
    }
}

struct iOSLocationView: View {
    @ObservedObject var sidebarViewModel: SidebarViewModel
    private let viewModel: iOSLocationViewModel
    @State private var showLightPollution = false
    @FocusState private var isSearchFocused: Bool

    private var lightPollutionService: any LightPollutionProviding { sidebarViewModel.lightPollutionService }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { sidebarViewModel.searchState.text },
            set: { newValue in
                sidebarViewModel.searchState.text = newValue
                sidebarViewModel.handleSearchTextChanged()
            }
        )
    }

    init(sidebarViewModel: SidebarViewModel) {
        self.sidebarViewModel = sidebarViewModel
        self.viewModel = iOSLocationViewModel(
            locationController: sidebarViewModel.locationController,
            clearSearchText: { text in
                sidebarViewModel.setSearchTextProgrammatically(text)
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerSection
                searchSection
                searchResultsList
                mapArea
                bottomBar
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: "場所",
            verticalPadding: Spacing.xs,
            bottomPadding: Spacing.xs / 2,
            subtitleSpacing: Spacing.xs / 2
        ) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("検索して観測地点を選択します")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        } trailing: {
            Button {
                viewModel.requestCurrentLocation()
            } label: {
                Group {
                    if sidebarViewModel.isLocating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.headline)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .disabled(sidebarViewModel.isLocating)
            .accessibilityLabel("現在地を取得")
            .accessibilityHint("地図を現在地へ移動します")
        }
    }

    private var searchSection: some View {
        LocationSearchField(
            searchText: searchTextBinding,
            isSearching: sidebarViewModel.isSearching,
            isSearchFocused: $isSearchFocused,
            onClear: {
                sidebarViewModel.setSearchTextProgrammatically("")
            }
        )
        .onChange(of: sidebarViewModel.searchFocusTrigger) {
            isSearchFocused = true
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsList: some View {
        let results = sidebarViewModel.searchResults
        if !results.isEmpty {
            searchResultsCard(results)
        } else if !sidebarViewModel.searchState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sidebarViewModel.isSearching {
            ContentUnavailableView.search(text: sidebarViewModel.searchState.text)
                .padding(.vertical, Spacing.xs)
        }
    }

    private func searchResultsCard(_ results: [MKMapItem]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                    searchResultRow(item)
                    if index < results.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: IOSDesignTokens.Location.searchResultsMaxHeight)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func searchResultRow(_ item: MKMapItem) -> some View {
        Button {
            viewModel.selectSearchResult(item)
            isSearchFocused = false
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: IOSDesignTokens.Location.searchResultLineSpacing) {
                    Text(item.name ?? "")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let address = item.address,
                       let subtitle = address.shortAddress ?? address.fullAddress.nilIfEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Map

    private var mapArea: some View {
        ZStack(alignment: .bottomTrailing) {
            iOSMapView(
                pinCoordinate: sidebarViewModel.selectedCoordinate,
                onTap: { coord in
                    viewModel.selectCoordinate(coord)
                },
                syncState: MapKitSyncState(
                    trigger: sidebarViewModel.mapViewportSyncTrigger,
                    center: sidebarViewModel.viewport.center,
                    span: sidebarViewModel.viewport.span
                ),
                onRegionChange: { center, span in
                    updateViewportIfNeeded(center: center, span: span)
                },
                showLightPollution: showLightPollution,
                centerTrigger: sidebarViewModel.currentLocationCenterTrigger
            )
            .ignoresSafeArea(edges: .horizontal)
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            Picker("地図モード", selection: $showLightPollution) {
                Text("地図").tag(false)
                Text("光害").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: showLightPollution) {
                sidebarViewModel.handleLocationInputModeChanged()
            }

            infoRow
        }
        .padding(Spacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var infoRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Navigation.locationPin)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(sidebarViewModel.selectedLocationName.isEmpty ? "場所が選択されていません" : sidebarViewModel.selectedLocationName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if showLightPollution {
                if lightPollutionService.isLoading {
                    ProgressView().controlSize(.mini)
                } else if let bortle = lightPollutionService.bortleClass {
                    Text("ボルトル\(Int(bortle.rounded()))級")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if lightPollutionService.fetchFailed {
                    Text("取得失敗")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func updateViewportIfNeeded(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let currentCenter = sidebarViewModel.viewport.center
        let currentSpan = sidebarViewModel.viewport.span

        let shouldUpdateCenter =
            abs(currentCenter.latitude - center.latitude) > IOSDesignTokens.Location.viewportCoordinateEpsilon
            || abs(currentCenter.longitude - center.longitude) > IOSDesignTokens.Location.viewportCoordinateEpsilon

        let shouldUpdateSpan =
            abs(currentSpan.latitudeDelta - span.latitudeDelta) > IOSDesignTokens.Location.viewportSpanEpsilon
            || abs(currentSpan.longitudeDelta - span.longitudeDelta) > IOSDesignTokens.Location.viewportSpanEpsilon

        if shouldUpdateCenter {
            sidebarViewModel.viewport.center = center
        }
        if shouldUpdateSpan {
            sidebarViewModel.viewport.span = span
        }
    }
}

private struct LocationSearchField: View {
    @Binding var searchText: String
    let isSearching: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("場所を検索...", text: $searchText)
                .textFieldStyle(.plain)
                .focused(isSearchFocused)
                .accessibilityLabel("場所を検索")

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, Spacing.xs)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索語を消去")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

#Preview("Location - Loading") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .loading))
}

#Preview("Location - Empty") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .empty))
}

#Preview("Location - Content") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .content))
}
