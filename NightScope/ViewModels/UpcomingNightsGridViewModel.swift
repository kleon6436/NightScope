import SwiftUI
import Combine
import CoreLocation

@MainActor
final class UpcomingNightsGridViewModel: ObservableObject {
    @Published private(set) var displayNights: [NightSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var selectedDate: Date
    @Published private(set) var observationMode: ObservationMode
    @Published private(set) var upcomingIndexes: [Date: StarGazingIndex]
    @Published private(set) var weatherByDate: [String: DayWeatherSummary]
    @Published private(set) var weatherErrorMessage: String?
    @Published private(set) var selectedTimeZone: TimeZone

    private let detailViewModel: DetailViewModel
    private var cancellables = Set<AnyCancellable>()

    init(detailViewModel: DetailViewModel) {
        self.detailViewModel = detailViewModel
        self.selectedDate = detailViewModel.selectedDate
        self.observationMode = detailViewModel.observationMode
        self.upcomingIndexes = detailViewModel.upcomingIndexes
        self.weatherByDate = detailViewModel.weatherService.weatherByDate
        self.weatherErrorMessage = detailViewModel.weatherErrorMessage
        self.selectedTimeZone = detailViewModel.selectedTimeZone
        setupBindings()
    }

    private func setupBindings() {
        detailViewModel.$upcomingNights
            .sink { [weak self] nights in self?.displayNights = nights }
            .store(in: &cancellables)

        detailViewModel.$selectedDate
            .assign(to: &$selectedDate)

        detailViewModel.$observationMode
            .assign(to: &$observationMode)

        detailViewModel.$upcomingIndexes
            .assign(to: &$upcomingIndexes)

        detailViewModel.weatherService.weatherByDatePublisher
            .assign(to: &$weatherByDate)

        detailViewModel.$weatherErrorMessage
            .assign(to: &$weatherErrorMessage)

        detailViewModel.$selectedTimeZone
            .assign(to: &$selectedTimeZone)

        detailViewModel.$isUpcomingLoading
            .assign(to: &$isLoading)
    }

    // MARK: - Public Properties

    // MARK: - Public Methods

    func setSelectedDate(_ date: Date) {
        // DetailViewModel.$selectedDate の sink が appController.selectedDate 更新と
        // 当日詳細の再計算を担うため、ここでは選択日だけを更新する
        detailViewModel.selectedDate = date
    }

    func weatherSummary(for date: Date) -> DayWeatherSummary? {
        let key = detailViewModel.weatherService.dateKey(date, timeZone: selectedTimeZone)
        return weatherByDate[key]
    }

    func hasReliableWeatherData(for night: NightSummary, weather: DayWeatherSummary?) -> Bool {
        guard let weather else { return false }
        return night.hasUsableWeatherData(nighttimeHours: weather.nighttimeHours)
    }

    func hasPartialWeatherData(for night: NightSummary, weather: DayWeatherSummary?) -> Bool {
        guard let weather else { return false }
        return !night.hasUsableWeatherData(nighttimeHours: weather.nighttimeHours)
    }

    func isForecastOutOfRange(for night: NightSummary, weather: DayWeatherSummary?) -> Bool {
        guard weather == nil else { return false }
        return detailViewModel.weatherService.isForecastOutOfRange(
            for: night.date,
            in: weatherByDate,
            timeZone: selectedTimeZone
        )
    }

    func starGazingIndex(for date: Date) -> StarGazingIndex? {
        let startOfDay = ObservationTimeZone.startOfDay(for: date, timeZone: selectedTimeZone)
        guard let baseIndex = upcomingIndexes[startOfDay] else { return nil }
        guard let night = displayNights.first(where: {
            ObservationTimeZone.isDate($0.date, inSameDayAs: date, timeZone: selectedTimeZone)
        }) else {
            return baseIndex
        }
        return baseIndex.adjusted(
            for: observationMode,
            nightSummary: night,
            weather: weatherSummary(for: date)
        )
    }

    func isDateSelected(_ date: Date) -> Bool {
        ObservationTimeZone.isDate(date, inSameDayAs: selectedDate, timeZone: selectedTimeZone)
    }

    func isSelectedDateToday(referenceDate: Date = Date()) -> Bool {
        ObservationTimeZone.isDateInToday(selectedDate, timeZone: selectedTimeZone, referenceDate: referenceDate)
    }

    func observableRangeText(night: NightSummary, weather: DayWeatherSummary?) -> String {
        // 暗時間ゼロ（白夜等）は専用テキスト
        if night.totalDarkHours <= 0 {
            return L10n.tr("暗い時間なし")
        }
        if let weather,
           let text = night.weatherAwareRangeText(nighttimeHours: weather.nighttimeHours) {
            return text.isEmpty ? L10n.tr("天候不良") : text
        }
        return night.darkRangeText.isEmpty ? "—" : night.darkRangeText
    }

    func cardAccessibilityLabel(night: NightSummary, weather: DayWeatherSummary?, index: StarGazingIndex?) -> String {
        var parts: [String] = []
        parts.append(DateFormatters.fullDateString(from: night.date, timeZone: selectedTimeZone))
        if night.totalDarkHours <= 0 {
            parts.append(L10n.tr("暗い時間なし"))
            parts.append(L10n.format("月: %@", night.moonPhaseName))
            return parts.joined(separator: "、")
        }
        if let idx = index { parts.append(L10n.format("星空指数%d", idx.score)) }
        if hasReliableWeatherData(for: night, weather: weather), let w = weather {
            parts.append(L10n.format("天気%@", w.weatherLabel))
        } else if hasPartialWeatherData(for: night, weather: weather) {
            parts.append(L10n.tr("天気予報一部のみ"))
        } else if isForecastOutOfRange(for: night, weather: weather) {
            parts.append(L10n.tr("天気予報対象外"))
        }
        parts.append(L10n.format("月: %@", night.moonPhaseName))
        return parts.joined(separator: "、")
    }

    func weatherIconColor(code: Int) -> Color {
        WeatherPresentation.color(forWeatherCode: code)
    }

    func placeholderNight(at offset: Int) -> NightSummary {
        let baseDate = ObservationTimeZone.startOfDay(for: selectedDate, timeZone: selectedTimeZone)
        let date = ObservationTimeZone.date(byAdding: .day, value: offset, to: baseDate, timeZone: selectedTimeZone) ?? baseDate
        return NightSummary(
            date: date,
            location: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            events: [],
            viewingWindows: [],
            moonPhaseAtMidnight: 0,
            timeZoneIdentifier: selectedTimeZone.identifier
        )
    }
}
