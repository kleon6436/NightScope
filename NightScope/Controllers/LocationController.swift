import CoreLocation
import MapKit

@MainActor
final class LocationController: NSObject, ObservableObject {
    @Published var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503) {
        didSet { locationUpdateID = UUID() }
    }
    @Published var locationUpdateID: UUID = UUID()
    @Published var locationName: String = "東京"
    @Published var searchResults: [MKMapItem] = []

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }
    }

    func select(_ mapItem: MKMapItem) {
        selectedLocation = mapItem.location.coordinate
        searchResults = []
        Task { locationName = await reverseGeocode(coordinate: mapItem.location.coordinate) }
    }

    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectedLocation = coordinate
        searchResults = []
        Task { locationName = await reverseGeocode(coordinate: coordinate) }
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return "現在地" }
        request.preferredLocale = Locale(identifier: "ja_JP")
        let mapItems = try? await request.mapItems
        guard let item = mapItems?.first else { return "現在地" }
        if let repr = item.addressRepresentations,
           let city = repr.cityWithContext, !city.isEmpty {
            return city
        }
        if let addr = item.address {
            let text = addr.shortAddress ?? addr.fullAddress
            if !text.isEmpty { return text }
        }
        return item.name ?? "現在地"
    }
}
