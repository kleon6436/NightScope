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
        L10n.format("雲量 %.0f%%", value)
    }

    func formatPrecipitation(_ value: Double) -> String {
        L10n.format("降水 %.1f mm", value)
    }

    func formatMetrics(precipitation: Double, cloudCover: Double) -> String {
        "\(formatPrecipitation(precipitation)) ・ \(formatCloudCover(cloudCover))"
    }

    func formatWindSpeed(_ value: Double) -> String {
        windSpeedUnit.format(value)
    }

    func unavailableTitle(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? L10n.tr("予報対象外") : L10n.tr("不明")
    }

    func unavailablePrimaryText(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? L10n.tr("この日は天気予報の対象外です") : L10n.tr("データなし")
    }

    func unavailableSecondaryText(isForecastOutOfRange: Bool) -> String {
        isForecastOutOfRange ? L10n.tr("天文情報のみ表示しています") : L10n.tr("10日以内のみ")
    }

    func partialCoverageTitle() -> String {
        L10n.tr("予報一部のみ")
    }

    func partialCoveragePrimaryText() -> String {
        L10n.tr("夜間を最後まで評価できません")
    }

    func partialCoverageSecondaryText() -> String {
        L10n.tr("星空指数には反映していません")
    }

    func errorTitle() -> String {
        L10n.tr("取得失敗")
    }

    func errorPrimaryText(_ message: String) -> String {
        message
    }

    func errorSecondaryText() -> String {
        L10n.tr("再試行してください")
    }

    func accessibilityDescription(
        weather: DayWeatherSummary?,
        isLoading: Bool,
        isForecastOutOfRange: Bool,
        isCoverageIncomplete: Bool,
        errorMessage: String? = nil
    ) -> String {
        if isLoading { return L10n.tr("天気 夜間: 取得中") }
        if isCoverageIncomplete {
            return L10n.tr("天気 夜間: 予報一部のみ、夜間を最後まで評価できません、星空指数には反映していません")
        }
        if let errorMessage, weather == nil {
            return L10n.format("天気 夜間: 取得失敗、%@、再試行してください", errorMessage)
        }
        guard let w = weather else {
            return isForecastOutOfRange
                ? L10n.tr("天気 夜間: 予報対象外、この日は天気予報の対象外です、天文情報のみ表示しています")
                : L10n.tr("天気 夜間: 不明、データなし、10日以内のみ")
        }
        return L10n.format(
            "天気 夜間: %@、降水%.1fmm、雲量%d%%、%@",
            weatherLabel(w),
            w.maxPrecipitation,
            Int(w.avgCloudCover),
            formatWindSpeed(w.avgWindSpeed)
        )
    }
}
