import SwiftUI
import Combine

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var nightSummary: NightSummary?
    @Published private(set) var starGazingIndex: StarGazingIndex?
    @Published private(set) var isCalculating = false
    @Published private(set) var upcomingNights: [NightSummary] = []
    @Published private(set) var upcomingIndexes: [Date: StarGazingIndex] = [:]
    @Published var selectedDate: Date
    @Published private(set) var locationName: String = ""
    @Published private(set) var hasWeatherError: Bool = false
    @Published private(set) var weatherErrorMessage: String? = nil
    @Published private(set) var hasLightPollutionError: Bool = false
    @Published private(set) var currentWeather: DayWeatherSummary?
    @Published private(set) var isWeatherLoading: Bool = false

    private let appController: AppController
    private var cancellables = Set<AnyCancellable>()

    init(appController: AppController) {
        self.appController = appController
        self.selectedDate = appController.selectedDate
        bind()
    }

    private func bind() {
        appController.$nightSummary
            .assign(to: &$nightSummary)

        appController.$starGazingIndex
            .assign(to: &$starGazingIndex)

        appController.$upcomingNights
            .assign(to: &$upcomingNights)

        appController.$upcomingIndexes
            .assign(to: &$upcomingIndexes)

        appController.$selectedDate
            .removeDuplicates()
            .assign(to: &$selectedDate)

        Publishers.CombineLatest(
            appController.$selectedDate.removeDuplicates(),
            appController.weatherService.$weatherByDate
        )
        .sink { [weak self] date, _ in
            guard let self else { return }
            self.currentWeather = self.appController.weatherService.summary(for: date)
        }
        .store(in: &cancellables)

        $selectedDate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] date in
                guard let self else { return }
                guard self.appController.selectedDate != date else { return }
                self.appController.selectedDate = date
                self.appController.recalculate()
                self.appController.recalculateUpcoming()
            }
            .store(in: &cancellables)

        appController.$isCalculating
            .assign(to: &$isCalculating)

        appController.locationController.$locationName
            .assign(to: &$locationName)

        appController.weatherService.$errorMessage
            .sink { [weak self] errorMessage in
                self?.weatherErrorMessage = errorMessage
                self?.hasWeatherError = errorMessage != nil
            }
            .store(in: &cancellables)

        appController.weatherService.$isLoading
            .assign(to: &$isWeatherLoading)

        appController.lightPollutionService.$fetchFailed
            .assign(to: &$hasLightPollutionError)
    }

    var weatherService: WeatherService {
        appController.weatherService
    }

    var lightPollutionService: LightPollutionService {
        appController.lightPollutionService
    }

    func refreshWeather() async {
        await appController.refreshWeather()
    }

    func refreshLightPollution() async {
        await appController.refreshLightPollution()
    }

    func retryWeatherInBackground() {
        Task {
            await refreshWeather()
        }
    }

    func retryLightPollutionInBackground() {
        Task {
            await refreshLightPollution()
        }
    }

    // MARK: - Error Handling
}
