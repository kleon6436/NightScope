import SwiftUI

enum LocationInputMode {
    case search, map
}

struct SidebarView: View {
    @ObservedObject var locationController: LocationController
    @Binding var selectedDate: Date
    @State private var searchText: String = ""
    @State private var locationInputMode: LocationInputMode = .map

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

            Picker("", selection: $locationInputMode) {
                Text("検索").tag(LocationInputMode.search)
                Text("地図").tag(LocationInputMode.map)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if locationInputMode == .search {
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
                                        .foregroundColor(.primary)
                                    if let address = pair.element.address {
                                        Text(address.shortAddress ?? address.fullAddress)
                                            .font(.body)
                                            .foregroundColor(.secondary)
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
            } else {
                EquatableMapSection(
                    coordinate: locationController.selectedLocation,
                    onSelect: { coord in locationController.selectCoordinate(coord) }
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin")
                    .foregroundColor(.accentColor)
                    .font(.body)
                Text(locationController.locationName)
                    .font(.headline)
            }

            Text(String(format: "%.4f°, %.4f°",
                        locationController.selectedLocation.latitude,
                        locationController.selectedLocation.longitude))
                .font(.body)
                .foregroundColor(.secondary)
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
