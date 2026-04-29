import SwiftUI
import Combine

/// 夜間天気カードの表示ロジックと設定同期を担う ViewModel。
@MainActor
final class NightWeatherCardViewModel: ObservableObject {
    /// ユーザー設定に追従する風速単位。
    @AppStorage("windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.kmh.rawValue
    @Published private(set) var windSpeedUnit: WindSpeedUnit
    private var cancellables = Set<AnyCancellable>()

    /// 保存済みの単位を初期化し、設定変更通知も購読する。
    init() {
        let storedValue = UserDefaults.standard.string(forKey: "windSpeedUnit") ?? WindSpeedUnit.kmh.rawValue
        self.windSpeedUnit = WindSpeedUnit(rawValue: storedValue) ?? .kmh
        // AppStorage 以外の経路で設定が変わっても、表示単位を即時に追従させる。
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWindSpeedUnit()
            }
            .store(in: &cancellables)
    }

    /// UserDefaults 上の値を現在の表示単位へ反映する。
    private func syncWindSpeedUnit() {
        let updatedUnit = WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .kmh
        guard updatedUnit != windSpeedUnit else { return }
        windSpeedUnit = updatedUnit
    }

    // MARK: - Formatting Methods

    /// 天気サマリーの主ラベルを返す。
    func weatherLabel(_ weather: DayWeatherSummary) -> String {
        WeatherPresentation.primaryLabel(for: weather)
    }

    /// 雲量をパーセント表記に整形する。
    func formatCloudCover(_ value: Double) -> String {
        L10n.format("weather.cloudCover.label", L10n.percent(value))
    }

    /// 降水量を mm 単位で整形する。
    func formatPrecipitation(_ value: Double) -> String {
        L10n.format("降水 %.1f mm", value)
    }

    func formatMetrics(precipitation: Double, cloudCover: Double) -> String {
        "\(formatPrecipitation(precipitation)) ・ \(formatCloudCover(cloudCover))"
    }

    /// 選択済み単位で風速を整形する。
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

    /// 状態に応じた VoiceOver 用説明文を組み立てる。
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
            "weather.night.accessibility.metrics",
            weatherLabel(w),
            L10n.format("weather.precipitation.compact", L10n.number(w.maxPrecipitation, fractionDigits: 1)),
            L10n.format("weather.cloudCover.compact", L10n.percent(w.avgCloudCover)),
            formatWindSpeed(w.avgWindSpeed)
        )
    }
}
