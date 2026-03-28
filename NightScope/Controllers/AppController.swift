import Foundation
import Combine

@MainActor
final class AppController: ObservableObject {
    let locationController: LocationController
    let weatherService: WeatherService
    let lightPollutionService: LightPollutionService

    @Published var selectedDate: Date = Date()
    @Published var nightSummary: NightSummary?
    @Published var upcomingNights: [NightSummary] = []
    @Published var starGazingIndex: StarGazingIndex?
    @Published var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var isCalculating: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init(locationController: LocationController? = nil,
         weatherService: WeatherService? = nil,
         lightPollutionService: LightPollutionService? = nil) {
        self.locationController = locationController ?? LocationController()
        self.weatherService = weatherService ?? WeatherService()
        self.lightPollutionService = lightPollutionService ?? LightPollutionService()
        setupObservers()
    }

    func onStart() {
        recalculate()
        recalculateUpcoming()
        Task {
            await refreshWeather()
            await refreshLightPollution()
        }
    }

    func refreshWeather() async {
        await weatherService.fetchWeather(
            latitude: locationController.selectedLocation.latitude,
            longitude: locationController.selectedLocation.longitude
        )
    }

    func refreshLightPollution() async {
        await lightPollutionService.fetch(
            latitude: locationController.selectedLocation.latitude,
            longitude: locationController.selectedLocation.longitude
        )
    }

    func recalculate() {
        if nightSummary == nil {
            isCalculating = true
        }
        let date = selectedDate
        let location = locationController.selectedLocation
        Task.detached(priority: .userInitiated) { [weak self] in
            let summary = MilkyWayCalculator.calculateNightSummary(date: date, location: location)
            await MainActor.run { [weak self] in
                self?.nightSummary = summary
                self?.isCalculating = false
                self?.recomputeStarGazingIndex()
            }
        }
    }

    func recalculateUpcoming() {
        let today = Date()
        let location = locationController.selectedLocation
        Task.detached(priority: .background) { [weak self] in
            let upcoming = MilkyWayCalculator.calculateUpcomingNights(from: today, location: location, days: 14)
            await MainActor.run { [weak self] in
                self?.upcomingNights = upcoming
                self?.recomputeUpcomingIndexes()
            }
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

    private func setupObservers() {
        locationController.$locationUpdateID
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recalculate()
                    self?.recalculateUpcoming()
                    await self?.refreshWeather()
                    await self?.refreshLightPollution()
                }
            }
            .store(in: &cancellables)

        weatherService.$weatherByDate
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeStarGazingIndex()
                    self?.recomputeUpcomingIndexes()
                }
            }
            .store(in: &cancellables)

        lightPollutionService.$bortleClass
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recomputeStarGazingIndex()
                    self?.recomputeUpcomingIndexes()
                }
            }
            .store(in: &cancellables)
    }
}
