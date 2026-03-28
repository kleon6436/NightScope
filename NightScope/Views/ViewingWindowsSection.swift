import SwiftUI

struct ViewingWindowsSection: View {
    let summary: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("天の川 観測情報")
                .font(.title3.bold())

            if summary.viewingWindows.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("この日は天の川の観測に適した時間帯がありません")
                            .font(.body)
                        Text("銀河系中心が地平線上にある時間帯と天文薄明が重なりませんでした")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(summary.viewingWindows, id: \.start) { window in
                    windowRow(window: window, isMoonFavorable: summary.isMoonFavorable)
                }
            }
        }
    }

    private func windowRow(window: ViewingWindow, isMoonFavorable: Bool) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(timeString(window.start)) 〜 \(timeString(window.end))")
                    .font(.title3.bold())

                HStack(spacing: 12) {
                    Label(String(format: "観測 %.1f時間", window.duration / 3600), systemImage: "clock")
                    Label(String(format: "最大高度 %.0f°", window.peakAltitude), systemImage: "arrow.up")
                    Label("見頃 \(timeString(window.peakTime))", systemImage: "star")
                    Label(window.peakDirectionName, systemImage: "location.north.fill")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if isMoonFavorable {
                    Label("条件良好", systemImage: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.green)
                } else {
                    Label("月明かりあり", systemImage: "moon.fill")
                        .font(.body)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
