import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
protocol LocationProviding: AnyObject, ObservableObject {
    var selectedLocation: CLLocationCoordinate2D { get set }
    var locationName: String { get set }
    var locationUpdateID: UUID { get }
    var locationUpdateIDPublisher: Published<UUID>.Publisher { get }
    var locationNamePublisher: Published<String>.Publisher { get }
    var anyChangePublisher: AnyPublisher<Void, Never> { get }
    var searchResults: [MKMapItem] { get set }
    var isSearching: Bool { get set }
    var isLocating: Bool { get set }
    var locationError: LocationController.LocationError? { get set }
    var searchFocusTrigger: Int { get set }
    var currentLocationCenterTrigger: Int { get set }

    func requestCurrentLocation()
    func search(query: String)
    func select(_ mapItem: MKMapItem)
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D)
}

@MainActor
final class AppController: ObservableObject, LocationProviding, WeatherProviding {
    // MARK: - Dependencies
    let locationController: LocationController
    let weatherService: WeatherService
    let lightPollutionService: LightPollutionService

    // MARK: - Published State
    @Published var selectedDate: Date = {
        let saved = UserDefaults.standard.double(forKey: "selectedDate")
        return saved > 0 ? Date(timeIntervalSince1970: saved) : Date()
    }() {
        didSet {
            UserDefaults.standard.set(selectedDate.timeIntervalSince1970, forKey: "selectedDate")
        }
    }
    @Published var nightSummary: NightSummary?
    @Published var upcomingNights: [NightSummary] = []
    @Published var starGazingIndex: StarGazingIndex?
    @Published var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var isCalculating = false

    // MARK: - Private State
    private let calculationService: NightCalculating
    private var calculationTask: Task<Void, Never>?
    private var upcomingTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init
    init(locationController: LocationController? = nil,
         weatherService: WeatherService? = nil,
         lightPollutionService: LightPollutionService? = nil,
         calculationService: NightCalculating? = nil) {
        self.locationController = locationController ?? LocationController()
        self.weatherService = weatherService ?? WeatherService()
        self.lightPollutionService = lightPollutionService ?? LightPollutionService()
        self.calculationService = calculationService ?? NightCalculationService()
        setupObservers()
    }

    deinit {
        calculationTask?.cancel()
        upcomingTask?.cancel()
        locationTask?.cancel()
    }

    // MARK: - Public Methods
    func onStart() {
        recalculate()
        recalculateUpcoming()
        Task {
            await refreshExternalData()
        }
    }

    func refreshWeather() async {
        let coordinate = selectedCoordinate
        await weatherService.fetchWeather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    func refreshLightPollution() async {
        let coordinate = selectedCoordinate
        await lightPollutionService.fetch(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    // MARK: - Calculation
    func recalculate() {
        calculationTask?.cancel()
        if nightSummary == nil {
            isCalculating = true
        }
        let date = selectedDate
        let location = selectedCoordinate
        calculationTask = Task {
            let summary = await calculationService.calculateNightSummary(date: date, location: location)
            guard !Task.isCancelled else { return }
            nightSummary = summary
            isCalculating = false
            recomputeStarGazingIndex()
        }
    }

    func recalculateUpcoming() {
        upcomingTask?.cancel()
        let today = Date()
        let location = selectedCoordinate
        upcomingTask = Task {
            let upcoming = await calculationService.calculateUpcomingNights(from: today, location: location, days: 14)
            guard !Task.isCancelled else { return }
            upcomingNights = upcoming
            recomputeUpcomingIndexes()
        }
    }

    func recomputeStarGazingIndex() {
        guard let summary = nightSummary else { return }
        let weather = weatherService.summary(for: selectedDate)
        let bortle = lightPollutionService.bortleClass
        starGazingIndex = StarGazingIndex.compute(
            nightSummary: summary,
            weather: weather,
            bortleClass: bortle
        )
    }

    func recomputeUpcomingIndexes() {
        let bortle = lightPollutionService.bortleClass
        var indexes: [Date: StarGazingIndex] = [:]
        for night in upcomingNights {
            let weather = weatherService.summary(for: night.date)
            let idx = StarGazingIndex.compute(nightSummary: night, weather: weather, bortleClass: bortle)
            indexes[Calendar.current.startOfDay(for: night.date)] = idx
        }
        upcomingIndexes = indexes
    }

    // MARK: - Private
    private var selectedCoordinate: CLLocationCoordinate2D {
        locationController.selectedLocation
    }

    private func refreshExternalData() async {
        await refreshWeather()
        await refreshLightPollution()
    }

    private func recomputeAllIndexes() {
        recomputeStarGazingIndex()
        recomputeUpcomingIndexes()
    }

    private func handleLocationChanged() async {
        recalculate()
        recalculateUpcoming()
        guard !Task.isCancelled else { return }
        await refreshExternalData()
    }

    // MARK: - LocationProviding

    var selectedLocation: CLLocationCoordinate2D {
        get { locationController.selectedLocation }
        set { locationController.selectedLocation = newValue }
    }

    var locationName: String {
        get { locationController.locationName }
        set { locationController.locationName = newValue }
    }

    var locationUpdateID: UUID { locationController.locationUpdateID }
    var locationUpdateIDPublisher: Published<UUID>.Publisher { locationController.locationUpdateIDPublisher }
    var locationNamePublisher: Published<String>.Publisher { locationController.locationNamePublisher }
    var anyChangePublisher: AnyPublisher<Void, Never> { locationController.anyChangePublisher }

    var searchResults: [MKMapItem] {
        get { locationController.searchResults }
        set { locationController.searchResults = newValue }
    }

    var isSearching: Bool {
        get { locationController.isSearching }
        set { locationController.isSearching = newValue }
    }

    var isLocating: Bool {
        get { locationController.isLocating }
        set { locationController.isLocating = newValue }
    }

    var locationError: LocationController.LocationError? {
        get { locationController.locationError }
        set { locationController.locationError = newValue }
    }

    var searchFocusTrigger: Int {
        get { locationController.searchFocusTrigger }
        set { locationController.searchFocusTrigger = newValue }
    }

    var currentLocationCenterTrigger: Int {
        get { locationController.currentLocationCenterTrigger }
        set { locationController.currentLocationCenterTrigger = newValue }
    }

    func requestCurrentLocation() {
        locationController.requestCurrentLocation()
    }

    func search(query: String) {
        locationController.search(query: query)
    }

    func select(_ mapItem: MKMapItem) {
        locationController.select(mapItem)
    }

    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        locationController.selectCoordinate(coordinate)
    }

    // MARK: - WeatherProviding

    var weatherByDate: [String: DayWeatherSummary] {
        weatherService.weatherByDate
    }

    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher {
        weatherService.weatherByDatePublisher
    }

    var isLoading: Bool {
        weatherService.isLoading
    }

    var errorMessage: String? {
        weatherService.errorMessage
    }

    func fetchWeather(latitude: Double, longitude: Double) async {
        await weatherService.fetchWeather(latitude: latitude, longitude: longitude)
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherService.summary(for: date)
    }

    private func setupObservers() {
        locationController.$locationUpdateID
            .dropFirst()
            .sink { [weak self] _ in
                self?.locationTask?.cancel()
                self?.locationTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await handleLocationChanged()
                }
            }
            .store(in: &cancellables)

        weatherService.$weatherByDate
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeAllIndexes()
                }
            }
            .store(in: &cancellables)

        lightPollutionService.bortleClassPublisher
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeAllIndexes()
                }
            }
            .store(in: &cancellables)
    }
}
