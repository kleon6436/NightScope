import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    @ObservedObject var viewModel: NightWeatherCardViewModel

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

            if let w = weather {
                Text(viewModel.weatherLabel(w))
                    .font(.headline)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(viewModel.formatCloudCover(w.avgCloudCover))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(viewModel.formatPrecipitation(w.maxPrecipitation))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(viewModel.formatWindSpeed(w.avgWindSpeed))
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
        .accessibilityLabel(viewModel.accessibilityDescription(weather: weather, isLoading: false))
    }
}

