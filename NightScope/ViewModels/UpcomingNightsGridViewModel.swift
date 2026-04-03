import SwiftUI
import Combine

@MainActor
final class UpcomingNightsGridViewModel: ObservableObject {
    @Published private(set) var displayNights: [NightSummary] = []

    private let detailViewModel: DetailViewModel
    private var cancellables = Set<AnyCancellable>()

    init(detailViewModel: DetailViewModel) {
        self.detailViewModel = detailViewModel
        setupBindings()
    }

    private func setupBindings() {
        detailViewModel.$upcomingNights
            .map { nights in nights.filter { !$0.viewingWindows.isEmpty } }
            .sink { [weak self] nights in self?.displayNights = nights }
            .store(in: &cancellables)

        detailViewModel.$selectedDate
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        detailViewModel.$upcomingIndexes
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        detailViewModel.weatherService.$weatherByDate
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Public Properties

    var selectedDate: Date {
        detailViewModel.selectedDate
    }

    // MARK: - Public Methods

    func setSelectedDate(_ date: Date) {
        // DetailViewModel.$selectedDate の sink が appController.selectedDate の更新と
        // recalculate/recalculateUpcoming の呼び出しまで担うため、ここでは 1 行のみ
        detailViewModel.selectedDate = date
    }

    func weatherSummary(for date: Date) -> DayWeatherSummary? {
        detailViewModel.weatherService.summary(for: date)
    }

    func starGazingIndex(for date: Date) -> StarGazingIndex? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return detailViewModel.upcomingIndexes[startOfDay]
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
        parts.append(DateFormatters.fullDate.string(from: night.date))
        if let idx = index { parts.append("星空指数\(idx.score)") }
        if let w = weather { parts.append("天気\(w.weatherLabel)") }
        parts.append("月: \(night.moonPhaseName)")
        return parts.joined(separator: "、")
    }

    func weatherIconColor(code: Int) -> Color {
        switch code {
        case 0, 1:       return .yellow
        case 2:          return .secondary
        case 3:          return .secondary
        case 45, 48:     return .secondary
        case 51...65:    return .blue
        case 71...77:    return Color.blue.opacity(0.7)
        case 80...82:    return .blue
        case 85, 86:     return Color.blue.opacity(0.7)
        case 95...99:    return .orange
        default:         return .secondary
        }
    }
}
