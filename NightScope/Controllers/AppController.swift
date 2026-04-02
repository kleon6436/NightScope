import Foundation
import Combine
import CoreLocation

@MainActor
final class AppController: ObservableObject {
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

        lightPollutionService.$bortleClass
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeAllIndexes()
                }
            }
            .store(in: &cancellables)
    }
}
