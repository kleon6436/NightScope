import SwiftUI
import CoreLocation
#if os(iOS)
import Charts
#endif

// MARK: - PlanetVisibilityView

/// 今夜の惑星可視情報セクション（macOS / iOS 共通）。
struct PlanetVisibilityView: View {
    let selectedDate: Date
    let location: CLLocationCoordinate2D
    let timeZone: TimeZone

    @State private var summaries: [PlanetNightSummary] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader
            if isLoading {
                loadingCard
            } else {
                planetsCard
            }
        }
        .task(id: taskID) {
            isLoading = true
            // Sendable 境界を越えるため値をローカルにコピー
            let capturedDate     = selectedDate
            let capturedLocation = location
            let capturedTimeZone = timeZone
            let result = await Task.detached(priority: .userInitiated) {
                MilkyWayCalculator.planetNightSummaries(
                    date: capturedDate,
                    location: capturedLocation,
                    timeZone: capturedTimeZone
                )
            }.value
            summaries = result
            isLoading = false
        }
    }

    // MARK: - Private Subviews

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr("今夜の惑星"))
                .font(.title3.bold())
            Spacer()
            Text(nightDateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var planetsCard: some View {
        VStack(spacing: 0) {
            ForEach(summaries) { summary in
                PlanetRow(summary: summary, timeZone: timeZone)
                    .frame(height: PlanetStyle.rowHeight)
                if summary.id != summaries.last?.id {
                    Divider()
                        .opacity(0.4)
                        .padding(.horizontal, Spacing.xs)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    private var loadingCard: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(height: PlanetStyle.rowHeight * 5 + Spacing.xs * 2)
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    // MARK: - Helpers

    /// 再計算を起動するキー。日付・緯度・経度が変わったら変化する。
    private var taskID: String {
        "\(selectedDate.timeIntervalSinceReferenceDate)-\(location.latitude)-\(location.longitude)"
    }

    private var nightDateLabel: String {
        let cal   = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let month = cal.component(.month, from: selectedDate)
        let day   = cal.component(.day,   from: selectedDate)
        return L10n.format("%d月%d日", month, day)
    }
}

// MARK: - PlanetRow

private struct PlanetRow: View {
    let summary: PlanetNightSummary
    let timeZone: TimeZone

    @State private var isHovered = false
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: summary.observationDifficulty.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(summary.observationDifficulty.color)
            Text(summary.localizedName)
                .font(.callout)
                .frame(width: PlanetStyle.nameWidth, alignment: .leading)
                .lineLimit(1)
            Spacer()
            timeEntry(symbol: "↑", date: summary.riseTime)
            timeEntry(symbol: "▲", date: summary.transitTime)
            timeEntry(symbol: "↓", date: summary.setTime)
            Text(altitudeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: PlanetStyle.altWidth, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.xs)
        .opacity(summary.isVisibleTonight ? 1 : 0.4)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
#if os(macOS)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottomTrailing) {
            if isHovered { hoverTooltip }
        }
#endif
#if os(iOS)
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            PlanetDetailSheet(summary: summary, timeZone: timeZone)
        }
#endif
        .zIndex(isHovered ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Components

    private func timeEntry(symbol: String, date: Date?) -> some View {
        HStack(spacing: 2) {
            Text(symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date.map { $0.nightTimeString(timeZone: timeZone) } ?? "—")
                .font(.subheadline.monospacedDigit())
        }
        .frame(width: PlanetStyle.timeWidth, alignment: .leading)
    }

    // MARK: Hover Tooltip (macOS)

    private var hoverTooltip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.localizedName)
                .font(.caption.bold())
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(iconColor)
                Text(L10n.format("等級 %.1f", summary.magnitude))
            }
            .font(.caption)
            HStack(spacing: 4) {
                Image(systemName: summary.observationDifficulty.systemImage)
                    .foregroundStyle(summary.observationDifficulty.color)
                Text(summary.observationDifficulty.localizedLabel)
            }
            .font(.caption)
            Text(L10n.format("最大高度 %.1f°", summary.peakAltitude))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(summary.transitAzimuthLabel())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        .offset(y: PlanetStyle.rowHeight - 4)
        .padding(.trailing, Spacing.xs)
        .fixedSize()
    }

    // MARK: Helpers

    private var iconColor: Color {
        switch summary.name {
        case "水星": return .gray
        case "金星": return .yellow
        case "火星": return .red
        case "木星": return .orange
        case "土星": return .blue
        default:     return .primary
        }
    }

    private var altitudeLabel: String {
        String(format: "%.1f°", summary.peakAltitude)
    }

    private var accessibilityDescription: String {
        let rise    = summary.riseTime?.nightTimeString(timeZone: timeZone)    ?? "—"
        let transit = summary.transitTime?.nightTimeString(timeZone: timeZone) ?? "—"
        let set     = summary.setTime?.nightTimeString(timeZone: timeZone)     ?? "—"
        let alt     = String(format: "%.1f", summary.peakAltitude)
        return L10n.format("%@、出 %@、南中 %@、没 %@、最大高度 %@度",
                           summary.localizedName, rise, transit, set, alt)
    }
}

// MARK: - PlanetDetailSheet (iOS)

private struct PlanetDetailSheet: View {
    let summary: PlanetNightSummary
    let timeZone: TimeZone

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Text(summary.localizedName)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(label: "出",      value: summary.riseTime?.nightTimeString(timeZone: timeZone) ?? "—")
                    infoRow(label: "出 方位", value: summary.riseAzimuthLabel())
                    infoRow(label: "南中",    value: summary.transitTime?.nightTimeString(timeZone: timeZone) ?? "—")
                    infoRow(label: "南中 方位", value: summary.transitAzimuthLabel())
                    infoRow(label: "没",      value: summary.setTime?.nightTimeString(timeZone: timeZone) ?? "—")
                    infoRow(label: "没 方位", value: summary.setAzimuthLabel())
                    infoRow(label: "最大高度", value: String(format: "%.1f°", summary.peakAltitude))
                    infoRow(label: "等級",    value: String(format: "%.1f",   summary.magnitude))
                    infoRow(label: "観測難易度", value: summary.observationDifficulty.localizedLabel)
                }

#if os(iOS)
                altitudeChart
#endif
            }
            .padding()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
    }

#if os(iOS)
    private var altitudeChart: some View {
        Chart {
            ForEach(summary.altitudeSamples, id: \.time) { sample in
                LineMark(
                    x: .value("時刻", sample.time),
                    y: .value("高度", sample.altitude)
                )
            }
            RuleMark(y: .value("地平線", 0.0))
                .foregroundStyle(.secondary)
            RuleMark(y: .value("観測閾値", 10.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                .foregroundStyle(.orange)
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
            }
        }
        // 観測地タイムゾーンを適用して、rise/transit/set 時刻と一致させる
        .environment(\.timeZone, timeZone)
        .frame(height: 140)
        .padding(.top, 8)
    }
#endif

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(L10n.tr(label))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

extension ObservationDifficulty {
    var color: Color {
        switch self {
        case .nakedEye: return .green
        case .binoculars: return .yellow
        case .telescope: return .orange
        }
    }
}

// MARK: - PlanetStyle

private enum PlanetStyle {
    static let rowHeight: CGFloat = 36
    static let nameWidth: CGFloat = 52
    static let timeWidth: CGFloat = 60
    static let altWidth:  CGFloat = 52
}

// MARK: - Preview

#Preview {
    ScrollView {
        PlanetVisibilityView(
            selectedDate: Date(),
            location: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        .padding()
    }
    .frame(width: 600, height: 300)
}
