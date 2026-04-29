#if os(macOS)
import SwiftUI
import CoreLocation
import AppKit

/// ダッシュボード上で 1 地点分の比較結果を表示するカード。
struct DashboardLocationCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    let location: FavoriteLocation
    let dates: [Date]
    let mapSnapshotCache: MapSnapshotCache
    let onSelect: (UUID, Date) -> Void
    let onDelete: (UUID) -> Void
    @ScaledMetric(relativeTo: .body) private var adaptiveMinimumCellWidth: CGFloat = 42
    @State private var showDeleteAlert = false

    private var timeZone: TimeZone {
        TimeZone(identifier: location.timeZoneIdentifier) ?? .current
    }

    private var firstNightSummary: NightSummary? {
        guard let firstDate = dates.first else { return nil }
        return viewModel.cell(for: location.id, date: firstDate)?.nightSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            Divider()
            dayStrip
            Divider()
            observationWindow
        }
        .glassCard()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(L10n.tr("お気に入りから削除"), systemImage: "trash")
            }
        }
        .alert(L10n.tr("お気に入りから削除しますか？"), isPresented: $showDeleteAlert) {
            Button(L10n.tr("削除"), role: .destructive) {
                onDelete(location.id)
            }
            Button(L10n.tr("キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.format("%@ をお気に入りから削除し、ダッシュボードからも外します", location.name))
        }
        .accessibilityAction(named: Text(L10n.tr("お気に入りから削除"))) {
            showDeleteAlert = true
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
                DashboardMapThumbnail(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    mapSnapshotCache: mapSnapshotCache
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(
                    L10n.format(
                        "%.4f°, %.4f°",
                        location.latitude,
                        location.longitude
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                DashboardBortleLabel(
                    bortleClass: firstLoadedBortleClass
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var firstLoadedBortleClass: Double? {
        for date in dates {
            if let value = viewModel.cell(for: location.id, date: date)?.bortleClass {
                return value
            }
        }
        return nil
    }

    private var dayStrip: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: adaptiveMinimumCellWidth), spacing: Spacing.xs / 2), count: max(dates.count, 1))

        return LazyVGrid(columns: columns, spacing: Spacing.xs / 2) {
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                DashboardDayColumn(
                    location: location,
                    date: date,
                    viewModel: viewModel,
                    timeZone: timeZone,
                    onSelect: onSelect
                )
            }
        }
    }

    private var observationWindow: some View {
        let windowText: String
        if let summary = firstNightSummary, !summary.darkRangeText.isEmpty {
            windowText = summary.darkRangeText
        } else {
            windowText = L10n.tr("—")
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(L10n.tr("今夜の観測ウィンドウ"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(windowText)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .panelTooltip(windowText)
        }
    }
}

/// 地点の周辺を静的サムネイルで示すマップ画像。
private struct DashboardMapThumbnail: View {
    let latitude: Double
    let longitude: Double
    let mapSnapshotCache: MapSnapshotCache

    @State private var snapshot: NSImage?
    @State private var didFail = false
    @State private var isLoading = false
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 96
    private let spanDegrees = 0.4

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .fill(Color.secondary.opacity(0.12))

            if let snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "map")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .panelTooltip(didFail ? L10n.tr("地図サムネイルの取得に失敗しました") : nil)
        .task(id: taskID) {
            await loadSnapshot()
        }
        .accessibilityLabel(L10n.tr("地図サムネイル"))
    }

    private var taskID: String {
        "\(latitude.bitPattern)-\(longitude.bitPattern)-\(Int(thumbSize))x\(Int(thumbSize))-\(spanDegrees.bitPattern)"
    }

    @MainActor
    private func loadSnapshot() async {
        isLoading = true
        didFail = false
        let image = await mapSnapshotCache.snapshot(
            latitude: latitude,
            longitude: longitude,
            sizePoints: CGSize(width: thumbSize, height: thumbSize),
            spanDegrees: spanDegrees
        )
        snapshot = image
        didFail = image == nil
        isLoading = false
    }
}

/// 各日付の比較スコアと補助情報を 1 列で示すセル。
private struct DashboardDayColumn: View {
    let location: FavoriteLocation
    let date: Date
    @ObservedObject var viewModel: DashboardViewModel
    let timeZone: TimeZone
    let onSelect: (UUID, Date) -> Void

    private var weekdayText: String {
        DashboardDateFormatter.weekdayString(for: date, timeZone: timeZone)
    }

    private var cell: ComparisonCell? {
        viewModel.cell(for: location.id, date: date)
    }

    private var isBest: Bool {
        viewModel.bestLocationID(for: date) == location.id
    }

    private var scoreText: String {
        guard let score = cell?.index?.score else { return L10n.tr("—") }
        return "\(score)"
    }

    private var weatherSymbol: String {
        guard let code = cell?.weather?.representativeWeatherCode else {
            return "questionmark.circle"
        }
        return DashboardWeatherSymbol.symbol(for: code)
    }

    private var moonText: String {
        guard let summary = cell?.nightSummary else { return L10n.tr("—") }
        let illumination = Int(round(((1 - cos(summary.moonPhaseAtMidnight * 2 * .pi)) / 2) * 100))
        return L10n.percent(Double(illumination))
    }

    private var weatherDescription: String {
        guard let weather = cell?.weather else { return L10n.tr("不明") }
        return weather.weatherLabel
    }

    private var accessibilityLabel: String {
        guard let cell else {
            return L10n.format("dashboard.cell.loadingAccessibility", location.name, weekdayText)
        }

        switch cell.loadState {
        case .loading:
            return L10n.format("dashboard.cell.loadingAccessibility", location.name, weekdayText)
        case .failed(let message):
            return L10n.format("dashboard.cell.failedAccessibility", location.name, weekdayText, message)
        case .idle:
            return L10n.format("dashboard.cell.loadingAccessibility", location.name, weekdayText)
        case .loaded:
            if let score = cell.index?.score {
                return L10n.format("dashboard.cell.loadedAccessibility", location.name, weekdayText, score, weatherDescription)
            }
            return L10n.format("dashboard.cell.loadedFallbackAccessibility", location.name, weekdayText, weatherDescription)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(weekdayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            scoreButton

            Image(systemName: weatherSymbol)
                .font(.caption)
                .foregroundStyle(weatherColor)
                .accessibilityHidden(true)

            Text(moonText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var weatherColor: Color {
        guard let code = cell?.weather?.representativeWeatherCode else { return .secondary }
        return WeatherPresentation.color(forWeatherCode: code)
    }

    private var scoreButton: some View {
        Button {
            onSelect(location.id, date)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                    .fill(backgroundColor)

                RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                    .strokeBorder(borderColor, lineWidth: isBest ? 1.5 : 1)

                switch cell?.loadState ?? .idle {
                case .loading, .idle:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    VStack(spacing: 2) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(L10n.tr("取得失敗"))
                            .font(.caption2)
                    }
                    .foregroundStyle(.red)
                case .loaded:
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            if isBest {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                            }
                            Text(scoreText)
                                .font(.body.monospacedDigit().bold())
                        }
                        .foregroundStyle(scoreForeground)

                        if let score = cell?.index?.score {
                            Text(L10n.format("スコア %d", score))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .disabled((cell?.loadState ?? .idle) != .loaded)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.tr("メインウィンドウで開く"))
        .panelTooltip(loadStateHelpText)
    }

    private var backgroundColor: Color {
        isBest ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        isBest ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.15)
    }

    private var scoreForeground: Color {
        isBest ? .accentColor : .primary
    }

    private var loadStateHelpText: String? {
        cell?.loadState.helpText
    }
}

private enum DashboardDateFormatter {
    static func weekdayString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("E")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

private enum DashboardWeatherSymbol {
    static func symbol(for weatherCode: Int) -> String {
        switch weatherCode {
        case ..<4: return "sun.max"
        case ..<49: return "cloud"
        case ..<68: return "cloud.rain"
        case ..<78: return "cloud.snow"
        default: return "cloud.bolt"
        }
    }
}

private struct DashboardBortleLabel: View {
    let bortleClass: Double?

    var body: some View {
        Group {
            if let bortleClass {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(for: bortleClass))
                        .frame(width: 8, height: 8)
                        .padding(4)
                        .background(
                            Circle().fill(Color.accentColor.opacity(0.15))
                        )
                    Text(L10n.format("Bortle %@", L10n.number(bortleClass, fractionDigits: 1)))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            } else {
                Text(L10n.tr("光害データなし"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(
            bortleClass.map { L10n.format("光害レベル: %@", L10n.number($0, fractionDigits: 1)) }
                ?? L10n.tr("光害データなし")
        )
    }

    private func color(for bortleClass: Double) -> Color {
        switch bortleClass {
        case ..<4: return .green
        case ..<6: return .yellow
        case ..<8: return .orange
        default: return .red
        }
    }
}

private extension ComparisonCell.LoadState {
    var helpText: String? {
        switch self {
        case .failed(let message):
            return message
        case .loading:
            return L10n.tr("取得中...")
        case .idle, .loaded:
            return nil
        }
    }
}
#endif
