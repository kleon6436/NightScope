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

    static func loading(query: String, previousResults: [MKMapItem] = []) -> LocationSearchState {
        LocationSearchState(phase: .loading, query: query, results: previousResults, errorMessage: nil)
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
        let coordinate: CLLocationCoordinate2D
        let regionIdentifier: String?
        if #available(iOS 26, macOS 26, *) {
            coordinate = item.location.coordinate
            regionIdentifier = item.addressRepresentations?.region?.identifier
        } else {
            coordinate = item.placemark.coordinate
            regionIdentifier = nil
        }

        let timeZoneIdentifier = ApproximateTimeZoneResolver.exactIdentifier(
            for: coordinate,
            preferredIdentifier: item.timeZone?.identifier,
            regionIdentifier: regionIdentifier
        )

        if #available(iOS 26, macOS 26, *) {
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
        }

        return ResolvedLocationDetails(
            name: item.name ?? L10n.tr("現在地"),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

enum ApproximateTimeZoneResolver {
    static func bestIdentifier(
        for coordinate: CLLocationCoordinate2D,
        preferredIdentifier: String?,
        regionIdentifier: String? = nil
    ) -> String {
        exactIdentifier(
            for: coordinate,
            preferredIdentifier: preferredIdentifier,
            regionIdentifier: regionIdentifier
        ) ?? provisionalIdentifier(for: coordinate)
    }

    static func exactIdentifier(
        for coordinate: CLLocationCoordinate2D,
        preferredIdentifier: String? = nil,
        regionIdentifier: String? = nil
    ) -> String? {
        if let preferredIdentifier,
           TimeZone(identifier: preferredIdentifier) != nil,
           !isProvisionalIdentifier(preferredIdentifier) {
            return preferredIdentifier
        }

        if let regionIdentifier,
           let regionBackedIdentifier = regionBackedIdentifier(
            for: coordinate,
            regionIdentifier: regionIdentifier
           ) {
            return regionBackedIdentifier
        }
        return nil
    }

    static func identifier(
        for coordinate: CLLocationCoordinate2D,
        regionIdentifier: String? = nil
    ) -> String {
        exactIdentifier(for: coordinate, regionIdentifier: regionIdentifier)
            ?? approximateIdentifier(for: coordinate)
    }

    static func approximateIdentifier(for coordinate: CLLocationCoordinate2D) -> String {
        heuristicIdentifier(for: coordinate) ?? provisionalIdentifier(for: coordinate)
    }

    static func provisionalIdentifier(for coordinate: CLLocationCoordinate2D) -> String {
        fixedOffsetTimeZoneIdentifier(forHoursFromGMT: wholeHourOffset(for: coordinate))
    }

    static func isProvisionalIdentifier(_ identifier: String) -> Bool {
        identifier == "Etc/GMT" || identifier.hasPrefix("Etc/GMT+") || identifier.hasPrefix("Etc/GMT-")
    }

    private static func regionBackedIdentifier(
        for coordinate: CLLocationCoordinate2D,
        regionIdentifier: String
    ) -> String? {
        let normalizedRegionIdentifier = regionIdentifier.uppercased()

        switch normalizedRegionIdentifier {
        case "AU":
            return heuristicIdentifier(for: coordinate) ?? "Australia/Sydney"
        case "NZ":
            return heuristicIdentifier(for: coordinate) ?? "Pacific/Auckland"
        default:
            return singleRegionTimeZoneIdentifiers[normalizedRegionIdentifier]
        }
    }

    private static func heuristicIdentifier(for coordinate: CLLocationCoordinate2D) -> String? {
        let matches = timeZoneHeuristics.filter { $0.contains(coordinate: coordinate) }
        guard let firstMatch = matches.first else { return nil }

        let ambiguousContinentalUSMatches = Set(matches.map(\.identifier))
            .intersection(continentalUSHeuristicIdentifiers)
        guard ambiguousContinentalUSMatches.count <= 1 else { return nil }

        return firstMatch.identifier
    }

    private static func wholeHourOffset(for coordinate: CLLocationCoordinate2D) -> Int {
        min(max(Int((coordinate.longitude / 15.0).rounded()), -12), 14)
    }

    private static func fixedOffsetTimeZoneIdentifier(forHoursFromGMT hourOffset: Int) -> String {
        guard hourOffset != 0 else { return "Etc/GMT" }
        let sign = hourOffset > 0 ? "-" : "+"
        return "Etc/GMT\(sign)\(abs(hourOffset))"
    }

    private static let singleRegionTimeZoneIdentifiers = [
        "AF": "Asia/Kabul",
        "AT": "Europe/Vienna",
        "AE": "Asia/Dubai",
        "BD": "Asia/Dhaka",
        "BE": "Europe/Brussels",
        "BG": "Europe/Sofia",
        "BH": "Asia/Bahrain",
        "AR": "America/Argentina/Buenos_Aires",
        "CH": "Europe/Zurich",
        "CN": "Asia/Shanghai",
        "CZ": "Europe/Prague",
        "DE": "Europe/Berlin",
        "DK": "Europe/Copenhagen",
        "EG": "Africa/Cairo",
        "EE": "Europe/Tallinn",
        "FI": "Europe/Helsinki",
        "GR": "Europe/Athens",
        "HK": "Asia/Hong_Kong",
        "HU": "Europe/Budapest",
        "IE": "Europe/Dublin",
        "IN": "Asia/Kolkata",
        "IR": "Asia/Tehran",
        "IS": "Atlantic/Reykjavik",
        "IT": "Europe/Rome",
        "IL": "Asia/Jerusalem",
        "JP": "Asia/Tokyo",
        "KR": "Asia/Seoul",
        "KW": "Asia/Kuwait",
        "LK": "Asia/Colombo",
        "LT": "Europe/Vilnius",
        "LU": "Europe/Luxembourg",
        "LV": "Europe/Riga",
        "MO": "Asia/Macau",
        "MY": "Asia/Kuala_Lumpur",
        "NL": "Europe/Amsterdam",
        "NO": "Europe/Oslo",
        "NP": "Asia/Kathmandu",
        "OM": "Asia/Muscat",
        "PH": "Asia/Manila",
        "PK": "Asia/Karachi",
        "PL": "Europe/Warsaw",
        "QA": "Asia/Qatar",
        "RO": "Europe/Bucharest",
        "SA": "Asia/Riyadh",
        "SE": "Europe/Stockholm",
        "SG": "Asia/Singapore",
        "SK": "Europe/Bratislava",
        "TH": "Asia/Bangkok",
        "TR": "Europe/Istanbul",
        "TW": "Asia/Taipei",
        "UA": "Europe/Kyiv",
        "UY": "America/Montevideo",
        "VN": "Asia/Ho_Chi_Minh",
        "ZA": "Africa/Johannesburg"
    ]

    private static let timeZoneHeuristics = [
        TimeZoneHeuristic(latitudeRange: 26...31.5, longitudeRange: 80...89.5, identifier: "Asia/Kathmandu"),
        TimeZoneHeuristic(latitudeRange: 9...29, longitudeRange: 92...101, identifier: "Asia/Yangon"),
        TimeZoneHeuristic(latitudeRange: -32 ... -30, longitudeRange: 158...160.8, identifier: "Australia/Lord_Howe"),
        TimeZoneHeuristic(latitudeRange: -33.5 ... -30, longitudeRange: 126...129.5, identifier: "Australia/Eucla"),
        TimeZoneHeuristic(latitudeRange: -26 ... -10, longitudeRange: 129...139.5, identifier: "Australia/Darwin"),
        TimeZoneHeuristic(latitudeRange: -39 ... -26, longitudeRange: 129...141, identifier: "Australia/Adelaide"),
        TimeZoneHeuristic(latitudeRange: 46...53, longitudeRange: -60.5 ... -52, identifier: "America/St_Johns"),
        TimeZoneHeuristic(latitudeRange: 43...49.5, longitudeRange: -66.5 ... -56, identifier: "America/Halifax"),
        TimeZoneHeuristic(latitudeRange: -11 ... -6, longitudeRange: -142 ... -138, identifier: "Pacific/Marquesas"),
        TimeZoneHeuristic(latitudeRange: -45.5 ... -42, longitudeRange: -177.5 ... -175, identifier: "Pacific/Chatham"),
        TimeZoneHeuristic(latitudeRange: 24...40, longitudeRange: 43...64, identifier: "Asia/Tehran"),
        TimeZoneHeuristic(latitudeRange: 29...39.5, longitudeRange: 60...75, identifier: "Asia/Kabul"),
        TimeZoneHeuristic(latitudeRange: 5...38, longitudeRange: 67...92, identifier: "Asia/Kolkata"),
        TimeZoneHeuristic(latitudeRange: 31...38, longitudeRange: -115 ... -109, identifier: "America/Phoenix"),
        TimeZoneHeuristic(latitudeRange: 51...72, longitudeRange: -171 ... -129, identifier: "America/Anchorage"),
        TimeZoneHeuristic(latitudeRange: 25...52, longitudeRange: -129 ... -113, identifier: "America/Los_Angeles"),
        TimeZoneHeuristic(latitudeRange: 25...52, longitudeRange: -115 ... -101, identifier: "America/Denver"),
        TimeZoneHeuristic(latitudeRange: 25...52, longitudeRange: -106 ... -84, identifier: "America/Chicago"),
        TimeZoneHeuristic(latitudeRange: 25...52, longitudeRange: -90 ... -60, identifier: "America/New_York"),
        TimeZoneHeuristic(latitudeRange: 35...72, longitudeRange: -11 ... 0, identifier: "Europe/London"),
        TimeZoneHeuristic(latitudeRange: 35...72, longitudeRange: 0...20, identifier: "Europe/Paris"),
        TimeZoneHeuristic(latitudeRange: 35...72, longitudeRange: 20...36, identifier: "Europe/Athens"),
        TimeZoneHeuristic(latitudeRange: -44 ... -28, longitudeRange: 141...154.5, identifier: "Australia/Sydney"),
        TimeZoneHeuristic(latitudeRange: -48 ... -33, longitudeRange: 166...179.9, identifier: "Pacific/Auckland"),
        TimeZoneHeuristic(latitudeRange: -56 ... -17, longitudeRange: -76 ... -65, identifier: "America/Santiago"),
        TimeZoneHeuristic(latitudeRange: -56 ... -21, longitudeRange: -73 ... -52, identifier: "America/Argentina/Buenos_Aires"),
        TimeZoneHeuristic(latitudeRange: -35 ... 7, longitudeRange: -51 ... -34, identifier: "America/Sao_Paulo"),
        TimeZoneHeuristic(latitudeRange: -14 ... 6, longitudeRange: -75 ... -58, identifier: "America/Bogota"),
        TimeZoneHeuristic(latitudeRange: 22 ... 32, longitudeRange: 24 ... 37, identifier: "Africa/Cairo"),
        TimeZoneHeuristic(latitudeRange: 20 ... 34, longitudeRange: 34 ... 36.5, identifier: "Asia/Jerusalem"),
        TimeZoneHeuristic(latitudeRange: 22 ... 27, longitudeRange: 51 ... 56.5, identifier: "Asia/Dubai"),
        TimeZoneHeuristic(latitudeRange: -35 ... -21, longitudeRange: 16 ... 33, identifier: "Africa/Johannesburg")
    ]

    private static let continentalUSHeuristicIdentifiers: Set<String> = [
        "America/Los_Angeles",
        "America/Denver",
        "America/Chicago",
        "America/New_York",
        "America/Phoenix"
    ]
}

private struct TimeZoneHeuristic {
    let latitudeRange: ClosedRange<Double>
    let longitudeRange: ClosedRange<Double>
    let identifier: String

    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        latitudeRange.contains(coordinate.latitude) && longitudeRange.contains(coordinate.longitude)
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
        if #available(iOS 26, macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return ResolvedLocationDetails(name: L10n.tr("現在地"), timeZoneIdentifier: nil)
            }

            request.preferredLocale = .autoupdatingCurrent
            let mapItems = try? await request.mapItems
            guard let item = mapItems?.first else {
                return ResolvedLocationDetails(name: L10n.tr("現在地"), timeZoneIdentifier: nil)
            }

            return MapItemLocationDetailsExtractor.details(from: item)
        } else {
            let geocoder = CLGeocoder()
            let placemarks: [CLPlacemark]? = try? await withCheckedThrowingContinuation { continuation in
                geocoder.reverseGeocodeLocation(location, preferredLocale: .autoupdatingCurrent) { placemarks, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: placemarks ?? [])
                    }
                }
            }
            guard let placemark = placemarks?.first else {
                return ResolvedLocationDetails(name: L10n.tr("現在地"), timeZoneIdentifier: nil)
            }
            let name = placemark.locality ?? placemark.name ?? L10n.tr("現在地")
            return ResolvedLocationDetails(name: name, timeZoneIdentifier: placemark.timeZone?.identifier)
        }
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
