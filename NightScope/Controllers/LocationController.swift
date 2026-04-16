import Combine
import CoreLocation
import MapKit

@MainActor
final class LocationController: NSObject, ObservableObject, LocationProviding {
    private struct SelectionRequest {
        let coordinate: CLLocationCoordinate2D
        let fallbackName: String?
        let preferredDetails: ResolvedLocationDetails
        let preferredTimeZoneIdentifierForResolution: String?
        let incrementsCenterTrigger: Bool
    }

    // MARK: - Published State

    private let storage: LocationStorage
    private let searchService: LocationSearchServicing
    private let locationNameResolver: LocationNameResolving

    @Published var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503) {
        didSet {
            storage.latitude = selectedLocation.latitude
            storage.longitude = selectedLocation.longitude
        }
    }
    @Published private(set) var selectedTimeZoneIdentifier = TimeZone.current.identifier {
        didSet {
            storage.timeZoneIdentifier = selectedTimeZoneIdentifier
        }
    }
    /// 再計算が必要な場所変更が起きるたびに更新される ID（View 側での onChange 検知用）
    @Published private(set) var locationUpdateID: UUID = UUID()
    var selectedLocationPublisher: AnyPublisher<CLLocationCoordinate2D, Never> {
        $selectedLocation.eraseToAnyPublisher()
    }
    var locationNamePublisher: AnyPublisher<String, Never> {
        $locationName.eraseToAnyPublisher()
    }
    var searchStatePublisher: AnyPublisher<LocationSearchState, Never> {
        $searchState.eraseToAnyPublisher()
    }
    var searchResultsPublisher: AnyPublisher<[MKMapItem], Never> {
        $searchState
            .map(\.results)
            .eraseToAnyPublisher()
    }
    var isSearchingPublisher: AnyPublisher<Bool, Never> {
        $searchState
            .map(\.isSearching)
            .eraseToAnyPublisher()
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
    @Published var searchState: LocationSearchState = .idle
    @Published var isLocating = false
    @Published var locationError: LocationError?
    @Published var searchFocusTrigger = 0
    /// 検索・現在地取得で場所が確定するたびにインクリメント（マップセンタリングのトリガー）
    @Published var currentLocationCenterTrigger = 0

    var searchResults: [MKMapItem] {
        get { searchState.results }
        set {
            let query = effectiveSearchQuery
            if newValue.isEmpty {
                searchState = query.isEmpty ? .idle : .empty(query: query)
            } else {
                searchState = .results(query: query, items: newValue)
            }
        }
    }

    var isSearching: Bool {
        get { searchState.isSearching }
        set {
            guard newValue != searchState.isSearching else { return }
            if newValue {
                searchState = .loading(query: effectiveSearchQuery)
            } else {
                let query = effectiveSearchQuery
                searchState = query.isEmpty ? .idle : .empty(query: query)
            }
        }
    }

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
    private static let searchFailureMessage = "場所を検索できませんでした。通信状況を確認して、もう一度お試しください。"

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

    /// 現在地取得を開始します。未許可の場合は権限ダイアログを要求します。
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

    /// クエリを正規化して場所検索を開始します。
    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            clearSearch()
            return
        }

        let isSameAsLatestQuery = normalizedQuery == latestSearchQuery
        if isSameAsLatestQuery && (searchState.isSearching || searchState.phase == .results) {
            return
        }

        latestSearchQuery = normalizedQuery
        searchTask?.cancel()
        searchState = .loading(query: normalizedQuery)

        searchTask = Task { [normalizedQuery] in
            // デバウンス: 150ms 以内に次の入力があればキャンセルされる
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            do {
                let mapItems = try await searchService.search(query: normalizedQuery)
                guard !Task.isCancelled else { return }
                guard latestSearchQuery == normalizedQuery else { return }
                searchState = mapItems.isEmpty
                    ? .empty(query: normalizedQuery)
                    : .results(query: normalizedQuery, items: mapItems)
            } catch {
                guard !Task.isCancelled else { return }
                guard latestSearchQuery == normalizedQuery else { return }
                searchState = .failure(
                    query: normalizedQuery,
                    errorMessage: Self.searchFailureMessage
                )
            }
        }
    }

    /// 検索状態を初期化し、進行中の検索を取り消します。
    func clearSearch() {
        searchTask?.cancel()
        latestSearchQuery = ""
        searchState = .idle
    }

    /// 検索候補から場所を確定する（マップをセンタリングする）
    func select(_ mapItem: MKMapItem) {
        let preferredDetails = MapItemLocationDetailsExtractor.details(from: mapItem)
        applySelection(
            SelectionRequest(
                coordinate: mapItem.location.coordinate,
                fallbackName: mapItem.name,
                preferredDetails: preferredDetails,
                preferredTimeZoneIdentifierForResolution: preferredDetails.timeZoneIdentifier,
                incrementsCenterTrigger: true
            )
        )
    }

    /// マップタップなど座標から場所を選択する（センタリングしない）
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectCoordinate(coordinate, provisionalName: "選択した地点")
    }

    private func selectCoordinate(_ coordinate: CLLocationCoordinate2D, provisionalName: String) {
        let approximateTimeZoneIdentifier = approximateTimeZoneIdentifier(for: coordinate)
        applySelection(
            SelectionRequest(
                coordinate: coordinate,
                fallbackName: provisionalName,
                preferredDetails: ResolvedLocationDetails(
                    name: provisionalName,
                    timeZoneIdentifier: approximateTimeZoneIdentifier
                ),
                preferredTimeZoneIdentifierForResolution: approximateTimeZoneIdentifier,
                incrementsCenterTrigger: false
            )
        )
    }

    // MARK: - Private Helpers

    /// 場所確定時の共通フローです。即時反映と非同期の詳細解決をまとめて扱います。
    private func applySelection(_ request: SelectionRequest) {
        if isLocating { stopLocating() }
        clearSearch()
        let didChangeCoordinate = applyCoordinateSelection(request.coordinate)
        let didChangeTimeZone = applyResolvedLocationDetails(
            for: request.coordinate,
            details: request.preferredDetails,
            fallbackName: request.fallbackName
        )
        if didChangeCoordinate || didChangeTimeZone {
            commitLocationUpdate()
        }
        if request.incrementsCenterTrigger {
            currentLocationCenterTrigger += 1
        }
        resolveLocationDetails(
            for: request.coordinate,
            fallbackName: request.fallbackName,
            preferredTimeZoneIdentifier: request.preferredTimeZoneIdentifierForResolution
        )
    }

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

    private func commitLocationUpdate() {
        locationUpdateID = UUID()
    }

    @discardableResult
    private func applyCoordinateSelection(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard selectedLocation.latitude != coordinate.latitude
                || selectedLocation.longitude != coordinate.longitude else {
            return false
        }
        selectedLocation = coordinate
        return true
    }

    @discardableResult
    private func applyResolvedLocationDetails(
        for coordinate: CLLocationCoordinate2D,
        details: ResolvedLocationDetails,
        fallbackName: String?
    ) -> Bool {
        locationName = resolvedLocationName(details.name, fallbackName: fallbackName)
        let timeZoneIdentifier = resolvedTimeZoneIdentifier(
            for: coordinate,
            preferredIdentifier: details.timeZoneIdentifier
        )
        let didChangeTimeZone = selectedTimeZoneIdentifier != timeZoneIdentifier
        selectedTimeZoneIdentifier = timeZoneIdentifier
        return didChangeTimeZone
    }

    private func resolveLocationDetails(
        for coordinate: CLLocationCoordinate2D,
        fallbackName: String?,
        preferredTimeZoneIdentifier: String?
    ) {
        locationNameTask?.cancel()
        locationNameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let details = await self.locationNameResolver.resolveDetails(for: coordinate)
            guard !Task.isCancelled else { return }
            guard self.selectedLocation.latitude == coordinate.latitude,
                  self.selectedLocation.longitude == coordinate.longitude else { return }
            let didChangeTimeZone = self.applyResolvedLocationDetails(
                for: coordinate,
                details: ResolvedLocationDetails(
                    name: details.name,
                    timeZoneIdentifier: details.timeZoneIdentifier ?? preferredTimeZoneIdentifier
                ),
                fallbackName: fallbackName
            )
            if didChangeTimeZone {
                self.commitLocationUpdate()
            }
        }
    }

    private func resolvedLocationName(_ preferredName: String, fallbackName: String?) -> String {
        let trimmedPreferredName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallbackName = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedPreferredName == "現在地", !trimmedFallbackName.isEmpty {
            return trimmedFallbackName
        }

        if !trimmedPreferredName.isEmpty {
            return trimmedPreferredName
        }

        return trimmedFallbackName.isEmpty ? "選択した地点" : trimmedFallbackName
    }

    private func resolvedTimeZoneIdentifier(
        for coordinate: CLLocationCoordinate2D,
        preferredIdentifier: String?
    ) -> String {
        ApproximateTimeZoneResolver.bestIdentifier(
            for: coordinate,
            preferredIdentifier: preferredIdentifier
        )
    }

    private func approximateTimeZoneIdentifier(for coordinate: CLLocationCoordinate2D) -> String {
        ApproximateTimeZoneResolver.identifier(for: coordinate)
    }

    private var effectiveSearchQuery: String {
        if !latestSearchQuery.isEmpty {
            return latestSearchQuery
        }
        return searchState.query
    }

}

// MARK: - CLLocationManagerDelegate

extension LocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        Task { @MainActor in
            self.selectCoordinate(location.coordinate, provisionalName: "現在地")
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
