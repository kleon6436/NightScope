import SwiftUI

struct NightWeatherCard: View {
    let weather: DayWeatherSummary?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "cloud")
                    .foregroundColor(.cyan)
                    .font(.body)
                Text("天気 (夜間)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 20)
            } else if let w = weather {
                Text(w.weatherLabel == w.cloudLabel
                     ? w.weatherLabel
                     : "\(w.weatherLabel)（\(w.cloudLabel)）")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "雲量 %.0f%%", w.avgCloudCover))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(String(format: "降水 %.1f mm", w.maxPrecipitation))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(String(format: "風速 %.0f km/h", w.avgWindSpeed))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("データなし")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("16日以内のみ")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }
}
