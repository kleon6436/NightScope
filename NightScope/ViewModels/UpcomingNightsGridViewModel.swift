import SwiftUI
import Combine
import CoreLocation

@MainActor
final class UpcomingNightsGridViewModel: ObservableObject {
    @Published private(set) var displayNights: [NightSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var selectedDate: Date
    @Published private(set) var upcomingIndexes: [Date: StarGazingIndex]
    @Published private(set) var weatherByDate: [String: DayWeatherSummary]
    @Published private(set) var selectedTimeZone: TimeZone

    private let detailViewModel: DetailViewModel
    private var cancellables = Set<AnyCancellable>()

    init(detailViewModel: DetailViewModel) {
        self.detailViewModel = detailViewModel
        self.selectedDate = detailViewModel.selectedDate
        self.upcomingIndexes = detailViewModel.upcomingIndexes
        self.weatherByDate = detailViewModel.weatherService.weatherByDate
        self.selectedTimeZone = detailViewModel.selectedTimeZone
        setupBindings()
    }

    private func setupBindings() {
        detailViewModel.$upcomingNights
            .sink { [weak self] nights in self?.displayNights = nights }
            .store(in: &cancellables)

        detailViewModel.$selectedDate
            .assign(to: &$selectedDate)

        detailViewModel.$upcomingIndexes
            .assign(to: &$upcomingIndexes)

        detailViewModel.weatherService.$weatherByDate
            .assign(to: &$weatherByDate)

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

    func starGazingIndex(for date: Date) -> StarGazingIndex? {
        let startOfDay = ObservationTimeZone.startOfDay(for: date, timeZone: selectedTimeZone)
        return upcomingIndexes[startOfDay]
    }

    func isDateSelected(_ date: Date) -> Bool {
        ObservationTimeZone.isDate(date, inSameDayAs: selectedDate, timeZone: selectedTimeZone)
    }

    func isSelectedDateToday(referenceDate: Date = Date()) -> Bool {
        ObservationTimeZone.isDateInToday(selectedDate, timeZone: selectedTimeZone, referenceDate: referenceDate)
    }

    func observableRangeText(night: NightSummary, weather: DayWeatherSummary?) -> String {
        if let weather,
           let text = night.weatherAwareRangeText(nighttimeHours: weather.nighttimeHours) {
            return text.isEmpty ? "天候不良" : text
        }
        return night.darkRangeText.isEmpty ? "—" : night.darkRangeText
    }

    func cardAccessibilityLabel(night: NightSummary, weather: DayWeatherSummary?, index: StarGazingIndex?) -> String {
        var parts: [String] = []
        parts.append(DateFormatters.fullDateString(from: night.date, timeZone: selectedTimeZone))
        if let idx = index { parts.append("星空指数\(idx.score)") }
        if let w = weather { parts.append("天気\(w.weatherLabel)") }
        parts.append("月: \(night.moonPhaseName)")
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
