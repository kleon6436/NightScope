import SwiftUI

struct ViewingWindowsSection: View {
    let summary: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("天の川 観測情報")
                .font(.title3.bold())

            if summary.viewingWindows.isEmpty {
                ContentUnavailableView(
                    "観測に適した時間帯がありません",
                    systemImage: "exclamationmark.triangle",
                    description: Text("銀河系中心が地平線上にある時間帯と天文薄明が重なりませんでした")
                )
            } else {
                ForEach(summary.viewingWindows, id: \.start) { window in
                    windowRow(window: window, isMoonFavorable: summary.isMoonFavorable)
                }
            }
        }
    }

    private func windowRow(window: ViewingWindow, isMoonFavorable: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(timeString(window.start)) 〜 \(timeString(window.end))")
                    .font(.title3.bold())

                HStack(spacing: Spacing.sm) {
                    Label(String(format: "観測 %.1f時間", window.duration / 3600), systemImage: "clock")
                    Label(String(format: "最大高度 %.0f°", window.peakAltitude), systemImage: "arrow.up")
                    Label("見頃 \(timeString(window.peakTime))", systemImage: "star")
                    Label(window.peakDirectionName, systemImage: "location.north.fill")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                if isMoonFavorable {
                    Label("条件良好", systemImage: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                } else {
                    Label("月明かりあり", systemImage: "moon.fill")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(Layout.cardPadding)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(windowAccessibilityLabel(window: window, isMoonFavorable: isMoonFavorable))
    }

    private func windowAccessibilityLabel(window: ViewingWindow, isMoonFavorable: Bool) -> String {
        let timeRange = "\(timeString(window.start))から\(timeString(window.end))"
        let duration = String(format: "観測%.1f時間", window.duration / 3600)
        let altitude = String(format: "最大高度%.0f度", window.peakAltitude)
        let moon = isMoonFavorable ? "月の条件良好" : "月明かりあり"
        return "観測窓: \(timeRange)、\(duration)、\(altitude)、\(moon)"
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
