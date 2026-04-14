import Combine
import CoreLocation
import MapKit

@MainActor
final class LocationController: NSObject, ObservableObject, LocationProviding {

    // MARK: - Published State

    private let storage: LocationStorage
    private let searchService: LocationSearchServicing
    private let locationNameResolver: LocationNameResolving

    @Published var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503) {
        didSet {
            locationUpdateID = UUID()
            storage.latitude = selectedLocation.latitude
            storage.longitude = selectedLocation.longitude
        }
    }
    @Published private(set) var selectedTimeZoneIdentifier = TimeZone.current.identifier {
        didSet {
            storage.timeZoneIdentifier = selectedTimeZoneIdentifier
        }
    }
    /// 場所が変わるたびに更新される ID（View 側での onChange 検知用）
    @Published private(set) var locationUpdateID: UUID = UUID()
    var selectedLocationPublisher: AnyPublisher<CLLocationCoordinate2D, Never> {
        $selectedLocation.eraseToAnyPublisher()
    }
    var locationNamePublisher: AnyPublisher<String, Never> {
        $locationName.eraseToAnyPublisher()
    }
    var searchResultsPublisher: AnyPublisher<[MKMapItem], Never> {
        $searchResults.eraseToAnyPublisher()
    }
    var isSearchingPublisher: AnyPublisher<Bool, Never> {
        $isSearching.eraseToAnyPublisher()
    }
    var isLocatingPublisher: AnyPublisher<Bool, Never> {
        $isLocating.eraseToAnyPublisher()
    }
    var locationErrorPublisher: AnyPublisher<LocationError?, Never> {
        $locationError.eraseToAnyPublisher()
    }
    var searchFocusTriggerPublisher: AnyPublisher<Int, Never> {
        $searchFocusTrigger.eraseToAnyPublisher()
    }
    var currentLocationCenterTriggerPublisher: AnyPublisher<Int, Never> {
        $currentLocationCenterTrigger.eraseToAnyPublisher()
    }
    var selectedTimeZonePublisher: AnyPublisher<TimeZone, Never> {
        $selectedTimeZoneIdentifier
            .map { TimeZone(identifier: $0) ?? .current }
            .eraseToAnyPublisher()
    }
    var selectedTimeZone: TimeZone {
        TimeZone(identifier: selectedTimeZoneIdentifier) ?? .current
    }

    @Published var locationName: String = "東京" {
        didSet { storage.name = locationName }
    }
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false
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

    private let locationManager = CLLocationManager()
    private var locationTimeoutTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var locationNameTask: Task<Void, Never>?
    private var latestSearchQuery = ""

    // MARK: - Init

    init(
        storage: LocationStorage = UserDefaultsLocationStorage(),
        searchService: LocationSearchServicing = MKLocationSearchService(),
        locationNameResolver: LocationNameResolving = ReverseGeocodingLocationNameResolver()
    ) {
        self.storage = storage
        self.searchService = searchService
        self.locationNameResolver = locationNameResolver
        super.init()
        restorePersistedLocation()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func restorePersistedLocation() {
        if let lat = storage.latitude, let lon = storage.longitude {
            selectedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let name = storage.name {
            locationName = name
        }
        if let timeZoneIdentifier = storage.timeZoneIdentifier,
           TimeZone(identifier: timeZoneIdentifier) != nil {
            selectedTimeZoneIdentifier = timeZoneIdentifier
        }
    }

    // MARK: - Public API

    func requestCurrentLocation() {
        let status = locationManager.authorizationStatus
        guard status != .denied, status != .restricted else {
            locationError = .denied
            return
        }
        isLocating = true
        locationError = nil
        #if os(iOS)
        locationManager.requestWhenInUseAuthorization()
        #else
        locationManager.requestAlwaysAuthorization()
        #endif
        // 既に許可済みなら即開始、未決定なら locationManagerDidChangeAuthorization で開始する
        let alreadyAuthorized: Bool
        #if os(iOS)
        alreadyAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        alreadyAuthorized = status == .authorized || status == .authorizedAlways
        #endif
        if alreadyAuthorized {
            startLocationUpdatesWithTimeout()
        }
    }

    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            clearSearch()
            return
        }

        let isSameAsLatestQuery = normalizedQuery == latestSearchQuery
        if isSameAsLatestQuery && (isSearching || !searchResults.isEmpty) {
            return
        }

        latestSearchQuery = normalizedQuery
        searchTask?.cancel()
        isSearching = true

        searchTask = Task { [normalizedQuery] in
            // キャンセルされた場合は isSearching をリセットしない（次の検索が既に true にセット済み）
            defer {
                if !Task.isCancelled, latestSearchQuery == normalizedQuery {
                    isSearching = false
                }
            }
            // デバウンス: 150ms 以内に次の入力があればキャンセルされる
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            do {
                let mapItems = try await searchService.search(query: normalizedQuery)
                guard !Task.isCancelled else { return }
                guard latestSearchQuery == normalizedQuery else { return }
                searchResults = mapItems
            } catch {
                guard !Task.isCancelled else { return }
                guard latestSearchQuery == normalizedQuery else { return }
                searchResults = []
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        latestSearchQuery = ""
        searchResults = []
        isSearching = false
    }

    /// 検索候補から場所を確定する（マップをセンタリングする）
    func select(_ mapItem: MKMapItem) {
        if isLocating { stopLocating() }
        selectedLocation = mapItem.location.coordinate
        if let name = mapItem.name, !name.isEmpty {
            locationName = name
        }
        currentLocationCenterTrigger += 1
        resolveLocationDetails(for: mapItem.location.coordinate, fallbackName: mapItem.name)
    }

    /// マップタップなど座標から場所を選択する（センタリングしない）
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        if isLocating { stopLocating() }
        clearSearch()
        selectedLocation = coordinate
        resolveLocationDetails(for: coordinate, fallbackName: nil)
    }

    // MARK: - Private Helpers

    private func stopLocating() {
        cancelLocationTimeout()
        isLocating = false
        locationManager.stopUpdatingLocation()
    }

    private func startLocationUpdatesWithTimeout() {
        cancelLocationTimeout()
        locationManager.startUpdatingLocation()
        locationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            if self.isLocating {
                self.stopLocating()
                self.locationError = .failed
            }
        }
    }

    private func cancelLocationTimeout() {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
    }

    private func resolveLocationDetails(for coordinate: CLLocationCoordinate2D, fallbackName: String?) {
        locationNameTask?.cancel()
        locationNameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let details = await self.locationNameResolver.resolveDetails(for: coordinate)
            guard !Task.isCancelled else { return }
            guard self.selectedLocation.latitude == coordinate.latitude,
                  self.selectedLocation.longitude == coordinate.longitude else { return }
            self.locationName = details.name.isEmpty ? (fallbackName ?? "現在地") : details.name
            self.selectedTimeZoneIdentifier = resolvedTimeZoneIdentifier(
                for: coordinate,
                preferredIdentifier: details.timeZoneIdentifier
            )
        }
    }

    private func resolvedTimeZoneIdentifier(
        for coordinate: CLLocationCoordinate2D,
        preferredIdentifier: String?
    ) -> String {
        if let preferredIdentifier,
           TimeZone(identifier: preferredIdentifier) != nil {
            return preferredIdentifier
        }

        return approximateTimeZone(for: coordinate).identifier
    }

    private func approximateTimeZone(for coordinate: CLLocationCoordinate2D) -> TimeZone {
        let halfHourOffset = Int((coordinate.longitude / 15.0 * 2.0).rounded())
        let secondsFromGMT = min(max(halfHourOffset * 1_800, -12 * 3_600), 14 * 3_600)
        return TimeZone(secondsFromGMT: secondsFromGMT) ?? .current
    }

}

// MARK: - CLLocationManagerDelegate

extension LocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        Task { @MainActor in
            self.selectCoordinate(location.coordinate)
            self.currentLocationCenterTrigger += 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code == .denied else {
            // kCLErrorLocationUnknown など一時的なエラーは無視して待ち続ける
            // (startUpdatingLocation は内部で再試行するため)
            return
        }
        Task { @MainActor in
            // 権限エラーは致命的なので停止してエラー表示
            self.stopLocating()
            self.locationError = .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let isAuthorized: Bool
            #if os(iOS)
            isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
            #else
            isAuthorized = status == .authorized || status == .authorizedAlways
            #endif
            if isAuthorized {
                if self.isLocating { self.startLocationUpdatesWithTimeout() }
            } else if status == .denied || status == .restricted {
                if self.isLocating {
                    self.stopLocating()
                    self.locationError = .denied
                }
            }
        }
    }
}
