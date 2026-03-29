import SwiftUI
import MapKit

struct SidebarView: View {

    private enum LocationInputMode {
        case map, lightPollutionMap
    }

    @ObservedObject var locationController: LocationController
    @ObservedObject var lightPollutionService: LightPollutionService
    @Binding var selectedDate: Date
    @State private var searchText: String = ""
    @State private var locationInputMode: LocationInputMode = .map
    @State private var highlightedSearchIndex: Int = -1
    /// searchText をコードから書き換えた際に onChange の再検索を抑制するフラグ
    @State private var suppressNextSearch = false
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
        .onAppear {
            viewport.center = locationController.selectedLocation
        }
        .onChange(of: locationController.locationUpdateID) {
            setSearchText("")
        }
        .onChange(of: locationInputMode) {
            mapKitSyncTrigger += 1
        }
        .alert(
            "位置情報エラー",
            isPresented: Binding(
                get: { locationController.locationError != nil },
                set: { if !$0 { locationController.locationError = nil } }
            ),
            presenting: locationController.locationError
        ) { _ in
            Button("OK") { locationController.locationError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var mapModePickerRow: some View {
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
                bortleLabel
            }
        }
    }

    private var searchField: some View {
        TextField("場所を検索...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .accessibilityLabel("場所を検索")
            .overlay(alignment: .trailing) {
                if locationController.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, Spacing.xs)
                }
            }
            .onSubmit(confirmHighlightedOrFirst)
            .onChange(of: searchText) {
                highlightedSearchIndex = -1
                if suppressNextSearch {
                    suppressNextSearch = false
                    return
                }
                locationController.search(query: searchText)
            }
            .onChange(of: locationController.searchFocusTrigger) {
                isSearchFocused = true
            }
            .onKeyPress(.downArrow) {
                let count = min(locationController.searchResults.count, 5)
                if count > 0 {
                    highlightedSearchIndex = min(highlightedSearchIndex + 1, count - 1)
                }
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlightedSearchIndex = max(highlightedSearchIndex - 1, -1)
                return .handled
            }
            .onKeyPress(.escape) {
                setSearchText("")
                highlightedSearchIndex = -1
                isSearchFocused = false
                return .handled
            }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if !locationController.searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(locationController.searchResults.prefix(5).enumerated()), id: \.offset) { index, item in
                    searchResultRow(item: item, index: index)
                    Divider()
                }
            }
            .glassEffect(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        }
    }

    private func searchResultRow(item: MKMapItem, index: Int) -> some View {
        Button { confirmSelection(item) } label: {
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
                highlightedSearchIndex == index ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("場所を選択: \(item.name ?? "Unknown")")
    }

    private var mapView: some View {
        MapLocationPicker(
            selectedCoordinate: locationController.selectedLocation,
            onSelect: { coord in locationController.selectCoordinate(coord) },
            isVisible: true,
            syncState: MapKitSyncState(
                trigger: mapKitSyncTrigger,
                center: viewport.center,
                span: viewport.span
            ),
            onRegionChange: { center, span in
                viewport.center = center
                viewport.span = span
            },
            showLightPollution: locationInputMode == .lightPollutionMap,
            onCurrentLocation: { locationController.requestCurrentLocation() },
            isLocating: locationController.isLocating,
            centerTrigger: locationController.currentLocationCenterTrigger
        )
        .equatable()
    }

    private var selectedLocationLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Navigation.locationPinPlain)
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(locationController.locationName)
                    .font(.headline)
            }
            Text(String(format: "%.4f°, %.4f°",
                        locationController.selectedLocation.latitude,
                        locationController.selectedLocation.longitude))
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(format: "緯度%.4f度、経度%.4f度",
                    locationController.selectedLocation.latitude,
                    locationController.selectedLocation.longitude))
        }
    }

    // MARK: - Search Helpers

    private func setSearchText(_ text: String) {
        // text が変化しない場合 onChange が発火しないため、suppressNextSearch を
        // セットしても解除されずに次のユーザー入力が抑制されてしまう
        guard text != searchText else { return }
        suppressNextSearch = true
        searchText = text
    }

    /// ハイライト中の候補（なければ先頭）を確定する
    private func confirmHighlightedOrFirst() {
        let results = locationController.searchResults
        let target = results.indices.contains(highlightedSearchIndex) ? results[highlightedSearchIndex] : results.first
        if let item = target {
            confirmSelection(item)
        }
    }

    /// 候補を選択して検索状態をリセットする
    private func confirmSelection(_ item: MKMapItem) {
        locationController.select(item)
        setSearchText(item.name ?? "")
        highlightedSearchIndex = -1
        isSearchFocused = false
    }

    // MARK: - Bortle Label

    private var bortleLabel: some View {
        Group {
            if lightPollutionService.isLoading {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("光害データを取得中")
            } else if let bortle = lightPollutionService.bortleClass {
                Text(String(format: "Bortle %.0f", bortle))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(bortleColor(bortle))
                    .accessibilityLabel(String(format: "光害レベル: Bortle %.0f", bortle))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("光害データなし")
            }
        }
        .frame(width: 62, alignment: .trailing)
    }

    private func bortleColor(_ bortle: Double) -> Color {
        switch bortle {
        case ..<4:  return .green
        case ..<6:  return .yellow
        case ..<8:  return .orange
        default:    return .red
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
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
