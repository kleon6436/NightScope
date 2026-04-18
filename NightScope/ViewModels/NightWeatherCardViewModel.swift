import SwiftUI
import Combine

@MainActor
final class NightWeatherCardViewModel: ObservableObject {
    @AppStorage("windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.kmh.rawValue
    @Published private(set) var windSpeedUnit: WindSpeedUnit
    private var cancellables = Set<AnyCancellable>()

    init() {
        let storedValue = UserDefaults.standard.string(forKey: "windSpeedUnit") ?? WindSpeedUnit.kmh.rawValue
        self.windSpeedUnit = WindSpeedUnit(rawValue: storedValue) ?? .kmh
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWindSpeedUnit()
            }
            .store(in: &cancellables)
    }

    private func syncWindSpeedUnit() {
        let updatedUnit = WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .kmh
        guard updatedUnit != windSpeedUnit else { return }
        windSpeedUnit = updatedUnit
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

    func unavailableTitle(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? "予報対象外" : "不明"
    }

    func unavailablePrimaryText(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? "この日は天気予報の対象外です" : "データなし"
    }

    func unavailableSecondaryText(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? "天文情報のみ表示しています" : "10日以内のみ"
    }

    func partialCoverageTitle() -> String {
        "予報一部のみ"
    }

    func partialCoveragePrimaryText() -> String {
        "夜間を最後まで評価できません"
    }

    func partialCoverageSecondaryText() -> String {
        "星空指数には反映していません"
    }

    func errorTitle() -> String {
        "取得失敗"
    }

    func errorPrimaryText(_ message: String) -> String {
        message
    }

    func errorSecondaryText() -> String {
        "再試行してください"
    }

    func accessibilityDescription(
        weather: DayWeatherSummary?,
        isLoading: Bool,
        isForecastOutOfRange: Bool,
        isCoverageIncomplete: Bool,
        errorMessage: String? = nil
    ) -> String {
        if isLoading { return "天気 夜間: 取得中" }
        if isCoverageIncomplete {
            return "天気 夜間: 予報一部のみ、夜間を最後まで評価できません、星空指数には反映していません"
        }
        if let errorMessage, weather == nil {
            return "天気 夜間: 取得失敗、\(errorMessage)、再試行してください"
        }
        guard let w = weather else {
            return isForecastOutOfRange
                ? "天気 夜間: 予報対象外、この日は天気予報の対象外です、天文情報のみ表示しています"
                : "天気 夜間: 不明、データなし、10日以内のみ"
        }
        return "天気 夜間: \(weatherLabel(w))、降水\(String(format: "%.1f", w.maxPrecipitation))mm、雲量\(Int(w.avgCloudCover))%、\(formatWindSpeed(w.avgWindSpeed))"
    }
}
