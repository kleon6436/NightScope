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
            .map { $0 != nil }
            .assign(to: &$hasWeatherError)

        appController.weatherService.$errorMessage
            .assign(to: &$weatherErrorMessage)

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

    // MARK: - Error Handling
}
