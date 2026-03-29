import SwiftUI

struct MoonPhaseCard: View {
    let summary: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: summary.moonPhaseIcon)
                    .foregroundStyle(Color(NSColor.systemIndigo))
                    .font(.body)
                    .accessibilityHidden(true)
                Text("月の状態")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Text(summary.moonPhaseName)
                .font(.headline)
            Text(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("月の状態: \(summary.moonPhaseName)。\(summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意")")
    }
}

struct DarkTimeCard: View {
    let summary: NightSummary

    private var rangeText: String {
        if let eStart = summary.eveningDarkStart, let mEnd = summary.morningDarkEnd {
            return "\(timeString(eStart)) 〜 \(timeString(mEnd))"
        } else if let eStart = summary.eveningDarkStart {
            return "\(timeString(eStart)) 〜 翌朝"
        } else if let mEnd = summary.morningDarkEnd {
            return "深夜 〜 \(timeString(mEnd))"
        } else {
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: AppIcons.Observation.clock)
                    .foregroundStyle(.green)
                    .font(.body)
                    .accessibilityHidden(true)
                Text("観測可能時間")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if rangeText.isEmpty {
                Text("暗い時間なし")
                    .font(.headline)
            } else {
                Text(rangeText)
                    .font(.headline)
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rangeText.isEmpty
            ? "観測可能時間: 暗い時間なし"
            : "観測可能時間: \(rangeText)、暗い時間\(String(format: "%.1f", summary.totalDarkHours))時間")
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
