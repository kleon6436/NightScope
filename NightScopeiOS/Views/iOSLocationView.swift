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
            VStack(spacing: 0) {
                searchResultsList
                mapArea
                bottomBar
            }
            .navigationTitle("場所")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: searchTextBinding,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "場所を検索..."
            )
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsList: some View {
        let results = sidebarViewModel.searchResults
        if !results.isEmpty {
            List(results, id: \.self) { item in
                searchResultRow(item)
            }
            .listStyle(.plain)
            .frame(maxHeight: IOSDesignTokens.Location.searchResultsMaxHeight)
        }
    }

    private func searchResultRow(_ item: MKMapItem) -> some View {
        Button {
            viewModel.selectSearchResult(item)
        } label: {
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

            currentLocationButton
        }
    }

    private var currentLocationButton: some View {
        Button {
            viewModel.requestCurrentLocation()
        } label: {
            Group {
                if sidebarViewModel.isLocating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: Layout.mapIconSize))
                }
            }
            .frame(width: Layout.mapButtonSize, height: Layout.mapButtonSize)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.mapButtonCornerRadius))
        .padding([.trailing, .bottom], Spacing.sm)
        .disabled(sidebarViewModel.isLocating)
        .accessibilityLabel("現在地を取得")
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
        .background(.regularMaterial)
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

#Preview("Location - Loading") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .loading))
}

#Preview("Location - Empty") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .empty))
}

#Preview("Location - Content") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .content))
}
