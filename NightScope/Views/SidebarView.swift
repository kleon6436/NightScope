import SwiftUI
import MapKit

enum LocationInputMode {
    case map, lightPollutionMap
}

struct SidebarView: View {
    @ObservedObject var locationController: LocationController
    @ObservedObject var lightPollutionService: LightPollutionService
    @Binding var selectedDate: Date
    @State private var searchText: String = ""
    @State private var locationInputMode: LocationInputMode = .map
    /// パン中の SwiftUI 再描画を発生させずにビューポートを保持する参照型コンテナ
    @State private var viewport = ViewportBox()
    @State private var mapKitSyncTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            locationSection
            Divider()
            dateSection
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("場所", systemImage: "mappin.circle.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("", selection: $locationInputMode) {
                    Text("地図").tag(LocationInputMode.map)
                    Text("光害").tag(LocationInputMode.lightPollutionMap)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if locationInputMode == .lightPollutionMap {
                    bortleLabel
                }
            }

            TextField("場所を検索...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await locationController.search(query: searchText) }
                }

            if !locationController.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(locationController.searchResults.prefix(5).enumerated()), id: \.offset) { pair in
                        Button {
                            locationController.select(pair.element)
                            searchText = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.element.name ?? "Unknown")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if let address = pair.element.address {
                                    Text(address.shortAddress ?? address.fullAddress)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .glassEffect(in: RoundedRectangle(cornerRadius: 6))
            }

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
                showLightPollution: locationInputMode == .lightPollutionMap
            )
            .equatable()

            HStack(spacing: 6) {
                Image(systemName: "mappin")
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
                Text(locationController.locationName)
                    .font(.headline)
            }

            Text(String(format: "%.4f°, %.4f°",
                        locationController.selectedLocation.latitude,
                        locationController.selectedLocation.longitude))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            viewport.center = locationController.selectedLocation
        }
        .onChange(of: locationInputMode) {
            mapKitSyncTrigger += 1
        }
    }

    private var bortleLabel: some View {
        Group {
            if lightPollutionService.isLoading {
                ProgressView().controlSize(.small)
            } else if let bortle = lightPollutionService.bortleClass {
                Text(String(format: "Bortle %.0f", bortle))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(bortleColor(bortle))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("日付", systemImage: "calendar")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            CalendarView(selectedDate: $selectedDate)
                .padding(.horizontal, -12)
        }
    }
}
