import SwiftUI

struct DarkTimeCard: View {
    let summary: NightSummary
    let weather: DayWeatherSummary?

    private var viewModel: DarkTimeCardViewModel {
        DarkTimeCardViewModel(summary: summary, weather: weather)
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
            Text(viewModel.displayText)
                .font(.headline)
                .foregroundStyle(viewModel.isUnavailable ? .secondary : .primary)
            if !viewModel.isUnavailable {
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundStyle(.secondary)
                NightTimelineBar(summary: summary)
                    .frame(height: 8)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityLabel)
    }
}

// MARK: - Night Timeline Bar

private struct NightTimelineBar: View {
    let summary: NightSummary

    private func fraction(for date: Date) -> Double {
        let cal = Calendar.current
        let components = cal.dateComponents([.hour, .minute], from: date)
        var hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        if hour < 18 { hour += 24 }
        return (hour - 18) / 12.0
    }

    private var nowMarkerFraction: Double? {
        let cal = Calendar.current
        let todayComponents = cal.dateComponents([.year, .month, .day], from: summary.date)
        guard let dayMidnight = cal.date(from: todayComponents),
              let dayStart = cal.date(byAdding: .hour, value: 18, to: dayMidnight),
              let dayEnd   = cal.date(byAdding: .hour, value: 12, to: dayStart)
        else { return nil }
        let now = Date()
        guard now >= dayStart && now <= dayEnd else { return nil }
        return fraction(for: now)
    }

    var body: some View {
        let startFrac = summary.eveningDarkStart.map { fraction(for: $0) } ?? 0
        let endFrac   = summary.morningDarkEnd.map   { fraction(for: $0) } ?? 1
        let s = min(max(startFrac, 0), 1)
        let e = min(max(endFrac,   0), 1)

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Track
            RoundedRectangle(cornerRadius: h / 2)
                .fill(Color.white.opacity(0.12))
                .frame(height: h)

            // Dark band
            if e > s {
                RoundedRectangle(cornerRadius: h / 2)
                    .fill(LinearGradient(
                        colors: [Color.green.opacity(0.7), Color.teal.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * (e - s), height: h)
                    .offset(x: w * s)
            }

            // Current time marker
            if let nowFrac = nowMarkerFraction {
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: h * 1.6)
                    .offset(x: w * min(max(nowFrac, 0), 1) - 1, y: -h * 0.3)
            }
        }
    }
}

