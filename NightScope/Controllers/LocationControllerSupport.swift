import Combine
import CoreLocation
import MapKit

protocol LocationSearchServicing: Sendable {
    func search(query: String) async throws -> [MKMapItem]
}

struct MKLocationSearchService: LocationSearchServicing {
    func search(query: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }
}

struct LocationSearchState {
    enum Phase: Equatable {
        case idle
        case loading
        case results
        case empty
        case failure
    }

    let phase: Phase
    let query: String
    let results: [MKMapItem]
    let errorMessage: String?

    static var idle: LocationSearchState {
        LocationSearchState(phase: .idle, query: "", results: [], errorMessage: nil)
    }

    static func loading(query: String) -> LocationSearchState {
        LocationSearchState(phase: .loading, query: query, results: [], errorMessage: nil)
    }

    static func results(query: String, items: [MKMapItem]) -> LocationSearchState {
        LocationSearchState(phase: .results, query: query, results: items, errorMessage: nil)
    }

    static func empty(query: String) -> LocationSearchState {
        LocationSearchState(phase: .empty, query: query, results: [], errorMessage: nil)
    }

    static func failure(query: String, errorMessage: String) -> LocationSearchState {
        LocationSearchState(phase: .failure, query: query, results: [], errorMessage: errorMessage)
    }

    var isSearching: Bool {
        phase == .loading
    }
}

struct ResolvedLocationDetails: Sendable, Equatable {
    let name: String
    let timeZoneIdentifier: String?
}

enum MapItemLocationDetailsExtractor {
    static func details(from item: MKMapItem) -> ResolvedLocationDetails {
        let timeZoneIdentifier = item.timeZone?.identifier

        if let repr = item.addressRepresentations,
           let city = repr.cityWithContext,
           !city.isEmpty {
            return ResolvedLocationDetails(name: city, timeZoneIdentifier: timeZoneIdentifier)
        }

        if let address = item.address {
            let text = address.shortAddress ?? address.fullAddress
            if !text.isEmpty {
                return ResolvedLocationDetails(name: text, timeZoneIdentifier: timeZoneIdentifier)
            }
        }

        return ResolvedLocationDetails(
            name: item.name ?? "現在地",
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

protocol LocationNameResolving: Sendable {
    func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails
}

struct ReverseGeocodingLocationNameResolver: LocationNameResolving {
    func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return await resolveMapItemDetails(for: location)
    }

    private func resolveMapItemDetails(for location: CLLocation) async -> ResolvedLocationDetails {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return ResolvedLocationDetails(name: "現在地", timeZoneIdentifier: nil)
        }

        request.preferredLocale = Locale(identifier: "ja_JP")
        let mapItems = try? await request.mapItems
        guard let item = mapItems?.first else {
            return ResolvedLocationDetails(name: "現在地", timeZoneIdentifier: nil)
        }

        return MapItemLocationDetailsExtractor.details(from: item)
    }
}

protocol LocationStorage: AnyObject {
    var latitude: Double? { get set }
    var longitude: Double? { get set }
    var name: String? { get set }
    var timeZoneIdentifier: String? { get set }
}

final class UserDefaultsLocationStorage: LocationStorage {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var latitude: Double? {
        get {
            guard userDefaults.object(forKey: "location.latitude") != nil else { return nil }
            return userDefaults.double(forKey: "location.latitude")
        }
        set {
            if let value = newValue {
                userDefaults.set(value, forKey: "location.latitude")
            } else {
                userDefaults.removeObject(forKey: "location.latitude")
            }
        }
    }

    var longitude: Double? {
        get {
            guard userDefaults.object(forKey: "location.longitude") != nil else { return nil }
            return userDefaults.double(forKey: "location.longitude")
        }
        set {
            if let value = newValue {
                userDefaults.set(value, forKey: "location.longitude")
            } else {
                userDefaults.removeObject(forKey: "location.longitude")
            }
        }
    }

    var name: String? {
        get { userDefaults.string(forKey: "location.name") }
        set {
            if let value = newValue {
                userDefaults.set(value, forKey: "location.name")
            } else {
                userDefaults.removeObject(forKey: "location.name")
            }
        }
    }

    var timeZoneIdentifier: String? {
        get { userDefaults.string(forKey: "location.timeZoneIdentifier") }
        set {
            if let value = newValue {
                userDefaults.set(value, forKey: "location.timeZoneIdentifier")
            } else {
                userDefaults.removeObject(forKey: "location.timeZoneIdentifier")
            }
        }
    }
}
