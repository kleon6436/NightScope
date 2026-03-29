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
    @Published var isLocating: Bool = false
    @Published var locationError: LocationError? = nil

    enum LocationError: LocalizedError {
        case denied
        case failed

        var errorDescription: String? {
            switch self {
            case .denied:  return "位置情報のアクセスが拒否されています。システム設定 > プライバシーとセキュリティ > 位置情報サービスで許可してください。"
            case .failed:  return "現在地を取得できませんでした。しばらく待ってから再試行してください。"
            }
        }
    }

    private let locationManager = CLLocationManager()
    private var locationTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() {
        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            locationError = .denied
            return
        }
        isLocating = true
        locationError = nil
        locationManager.requestWhenInUseAuthorization()
        // 既に許可済みなら即開始、未決定なら locationManagerDidChangeAuthorization で開始する
        if status == .authorized || status == .authorizedAlways {
            startLocationUpdatesWithTimeout()
        }
    }

    private func startLocationUpdatesWithTimeout() {
        locationManager.startUpdatingLocation()
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            if self.isLocating {
                self.locationManager.stopUpdatingLocation()
                self.isLocating = false
                self.locationError = .failed
            }
        }
    }

    private func cancelLocationTimeout() {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
    }

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
        if isLocating {
            cancelLocationTimeout()
            isLocating = false
            locationManager.stopUpdatingLocation()
        }
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

// MARK: - CLLocationManagerDelegate

extension LocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        manager.stopUpdatingLocation()
        Task { @MainActor in
            self.cancelLocationTimeout()
            self.isLocating = false
            self.selectCoordinate(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        Task { @MainActor in
            if clError?.code == .denied {
                // 権限エラーは致命的なので停止してエラー表示
                self.cancelLocationTimeout()
                manager.stopUpdatingLocation()
                self.isLocating = false
                self.locationError = .denied
            }
            // kCLErrorLocationUnknown など一時的なエラーは無視して待ち続ける
            // (startUpdatingLocation は内部で再試行するため、ここでは何もしない)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorized, .authorizedAlways:
                if self.isLocating {
                    self.startLocationUpdatesWithTimeout()
                }
            case .denied, .restricted:
                if self.isLocating {
                    self.cancelLocationTimeout()
                    self.isLocating = false
                    self.locationError = .denied
                }
            default:
                break
            }
        }
    }
}
