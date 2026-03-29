import CoreLocation
import MapKit

@MainActor
final class LocationController: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503) {
        didSet {
            locationUpdateID = UUID()
            UserDefaults.standard.set(selectedLocation.latitude, forKey: Keys.latitude)
            UserDefaults.standard.set(selectedLocation.longitude, forKey: Keys.longitude)
        }
    }
    /// 場所が変わるたびに更新される ID（View 側での onChange 検知用）
    @Published private(set) var locationUpdateID: UUID = UUID()
    @Published var locationName: String = "東京" {
        didSet { UserDefaults.standard.set(locationName, forKey: Keys.name) }
    }
    @Published var searchResults: [MKMapItem] = []
    @Published var isLocating = false
    @Published var locationError: LocationError?
    @Published var searchFocusTrigger = 0
    /// 検索・現在地取得で場所が確定するたびにインクリメント（マップセンタリングのトリガー）
    @Published var currentLocationCenterTrigger = 0

    // MARK: - Error

    enum LocationError: LocalizedError {
        case denied
        case failed

        var errorDescription: String? {
            switch self {
            case .denied:
                return "位置情報のアクセスが拒否されています。システム設定 > プライバシーとセキュリティ > 位置情報サービスで許可してください。"
            case .failed:
                return "現在地を取得できませんでした。しばらく待ってから再試行してください。"
            }
        }
    }

    // MARK: - Private

    private enum Keys {
        static let latitude  = "location.latitude"
        static let longitude = "location.longitude"
        static let name      = "location.name"
    }

    private let locationManager = CLLocationManager()
    private var locationTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        restorePersistedLocation()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func restorePersistedLocation() {
        let lat = UserDefaults.standard.double(forKey: Keys.latitude)
        let lon = UserDefaults.standard.double(forKey: Keys.longitude)
        if lat != 0 || lon != 0 {
            selectedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let name = UserDefaults.standard.string(forKey: Keys.name) {
            locationName = name
        }
    }

    // MARK: - Public API

    func requestCurrentLocation() {
        let status = locationManager.authorizationStatus
        guard status != .denied && status != .restricted else {
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

    /// 検索候補から場所を確定する（マップをセンタリングする）
    func select(_ mapItem: MKMapItem) {
        selectedLocation = mapItem.location.coordinate
        searchResults = []
        currentLocationCenterTrigger += 1
        Task { locationName = await reverseGeocode(coordinate: mapItem.location.coordinate) }
    }

    /// マップタップなど座標から場所を選択する（センタリングしない）
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

    // MARK: - Private Helpers

    private func startLocationUpdatesWithTimeout() {
        locationManager.startUpdatingLocation()
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
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

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
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
            self.currentLocationCenterTrigger += 1
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
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                if self.isLocating { self.startLocationUpdatesWithTimeout() }
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
