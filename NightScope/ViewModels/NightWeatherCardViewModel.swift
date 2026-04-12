import SwiftUI
import Combine

@MainActor
final class NightWeatherCardViewModel: ObservableObject {
    @AppStorage("windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.kmh.rawValue
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var windSpeedUnit: WindSpeedUnit {
        WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .kmh
    }

    // MARK: - Formatting Methods

    func weatherLabel(_ weather: DayWeatherSummary) -> String {
        WeatherPresentation.primaryLabel(for: weather)
    }

    func formatCloudCover(_ value: Double) -> String {
        String(format: "雲量 %.0f%%", value)
    }

    func formatPrecipitation(_ value: Double) -> String {
        String(format: "降水 %.1f mm", value)
    }

    func formatMetrics(precipitation: Double, cloudCover: Double) -> String {
        "\(formatPrecipitation(precipitation)) ・ \(formatCloudCover(cloudCover))"
    }

    func formatWindSpeed(_ value: Double) -> String {
        windSpeedUnit.format(value)
    }

    func accessibilityDescription(weather: DayWeatherSummary?, isLoading: Bool) -> String {
        if isLoading { return "天気 夜間: 取得中" }
        guard let w = weather else { return "天気 夜間: 不明、データなし、10日以内のみ" }
        return "天気 夜間: \(weatherLabel(w))、降水\(String(format: "%.1f", w.maxPrecipitation))mm、雲量\(Int(w.avgCloudCover))%、風速\(Int(w.avgWindSpeed))km/h"
    }
}
