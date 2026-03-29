import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    let isLoading: Bool
    @AppStorage("windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.kmh.rawValue

    private var windSpeedUnit: WindSpeedUnit {
        WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .kmh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Weather.cloud)
                    .foregroundStyle(.cyan)
                    .font(.body)
                    .accessibilityHidden(true)
                Text("天気 (夜間)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("天気データを取得中")
            } else if let w = weather {
                Text(w.weatherLabel == w.cloudLabel
                     ? w.weatherLabel
                     : "\(w.weatherLabel)（\(w.cloudLabel)）")
                    .font(.headline)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(String(format: "雲量 %.0f%%", w.avgCloudCover))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(String(format: "降水 %.1f mm", w.maxPrecipitation))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(windSpeedUnit.format(w.avgWindSpeed))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("データなし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("16日以内のみ")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if isLoading { return "天気 夜間: 取得中" }
        guard let w = weather else { return "天気 夜間: データなし" }
        let label = w.weatherLabel == w.cloudLabel ? w.weatherLabel : "\(w.weatherLabel) \(w.cloudLabel)"
        return "天気 夜間: \(label)、雲量\(Int(w.avgCloudCover))%、降水\(String(format: "%.1f", w.maxPrecipitation))mm、風速\(Int(w.avgWindSpeed))km/h"
    }
}
