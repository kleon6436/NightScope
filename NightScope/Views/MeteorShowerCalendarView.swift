import SwiftUI

// MARK: - MeteorShowerIntensity + Color (View 層のみで使用)

private extension MeteorShowerIntensity {
    var color: Color {
        switch self {
        case .high:   return .orange
        case .medium: return .blue
        case .low:    return .teal
        }
    }
}

// MARK: - MeteorShowerCalendarView

/// 流星群の年間スケジュールをガントチャート形式で表示する共有ビュー（macOS / iOS 共通）。
struct MeteorShowerCalendarView: View {

    // 月ごとの日数（非閏年）
    private static let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    private static let totalDays = 365

    let selectedDate: Date

    init(selectedDate: Date = Date()) {
        self.selectedDate = selectedDate
    }

    private let showers = MeteorShowerCatalog.all

    /// 選択日の day-of-year（1〜365）
    private var selectedDOY: Int {
        let cal = Calendar.current
        return MeteorShowerCatalog.dayOfYear(
            month: cal.component(.month, from: selectedDate),
            day: cal.component(.day, from: selectedDate)
        )
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader
            calendarCard
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr("流星群カレンダー"))
                .font(.title3.bold())
            Spacer()
            Text(L10n.tr("年間スケジュール"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
                .padding(.horizontal, Spacing.xs)
            showerRowList
            Divider()
                .padding(.horizontal, Spacing.xs)
            legendRow
        }
        .padding(.vertical, Spacing.xs)
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    private var headerRow: some View {
        GeometryReader { geo in
            let timelineWidth = timelineWidth(total: geo.size.width)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: CalendarStyle.labelWidth)
                monthLabels(width: timelineWidth)
            }
            .padding(.horizontal, Spacing.xs)
        }
        .frame(height: CalendarStyle.headerHeight)
        .padding(.bottom, Spacing.xs / 2)
    }

    private func monthLabels(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { i in
                let w = CGFloat(Self.monthDays[i]) / CGFloat(Self.totalDays) * width
                Text("\(i + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: w, alignment: .leading)
            }
        }
    }

    private var showerRowList: some View {
        ForEach(showers) { shower in
            ShowerTimelineRow(shower: shower, selectedDOY: selectedDOY)
                .frame(height: CalendarStyle.rowHeight)

            if shower.id != showers.last?.id {
                Divider()
                    .opacity(0.4)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            legendItem(color: .orange, label: "活発")
            legendItem(color: .blue,   label: "中程度")
            legendItem(color: .teal,   label: "散発的")
            selectedDateLegendItem
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, Spacing.xs / 2)
        .padding(.horizontal, Spacing.xs)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }

    private var selectedDateLegendItem: some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(Color.primary.opacity(0.4))
                .frame(width: 1.5, height: 10)
            Text(isToday ? L10n.tr("今日") : L10n.tr("選択日"))
        }
    }

    // MARK: - Helpers

    private func timelineWidth(total: CGFloat) -> CGFloat {
        max(0, total - CalendarStyle.labelWidth - Spacing.xs * 2)
    }
}

// MARK: - ShowerTimelineRow

private struct ShowerTimelineRow: View {
    let shower: MeteorShower
    let selectedDOY: Int

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geo in
            let timelineW = max(0, geo.size.width - CalendarStyle.labelWidth - Spacing.xs * 2)

            HStack(spacing: 0) {
                showerLabel
                    .frame(width: CalendarStyle.labelWidth, alignment: .leading)

                Canvas { ctx, size in
                    drawRow(in: ctx, size: size)
                }
                .frame(width: timelineW)
                .allowsHitTesting(false)
            }
            .padding(.horizontal, Spacing.xs)
        }
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottomTrailing) {
            if isHovered {
                hoverTooltip
            }
        }
        .zIndex(isHovered ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Hover Tooltip

    private var hoverTooltip: some View {
        let peak  = dateLabel(month: shower.peakMonth,          day: shower.peakDay)
        let start = dateLabel(month: shower.activityStartMonth, day: shower.activityStartDay)
        let end   = dateLabel(month: shower.activityEndMonth,   day: shower.activityEndDay)
        return VStack(alignment: .leading, spacing: 3) {
            Text(shower.localizedName)
                .font(.caption.bold())
            HStack(spacing: 4) {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(shower.intensity.color)
                Text("極大: \(peak)")
            }
            .font(.caption)
            Text("活動期間: \(start) 〜 \(end)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("最大 約\(shower.zhr)/h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        .offset(y: CalendarStyle.rowHeight - 4)
        .padding(.trailing, Spacing.xs)
        .fixedSize()
    }

    private var accessibilityDescription: String {
        let start = dateLabel(month: shower.activityStartMonth, day: shower.activityStartDay)
        let end   = dateLabel(month: shower.activityEndMonth,   day: shower.activityEndDay)
        let peak  = dateLabel(month: shower.peakMonth,          day: shower.peakDay)
        return L10n.format(
            "%@、活動期間 %@から%@、極大 %@、最大 1時間あたり約%d個",
            shower.localizedName, start, end, peak, shower.zhr
        )
    }

    private func dateLabel(month: Int, day: Int) -> String {
        L10n.format("%d月%d日", month, day)
    }

    private var showerLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shower.localizedName)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                Text("最大 約\(shower.zhr)/h")
                    .font(.system(size: 9))
            }
            .foregroundStyle(shower.intensity.color.opacity(0.9))
        }
        .padding(.leading, 2)
    }

    // MARK: Canvas Drawing

    private func drawRow(in ctx: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let midY = h / 2

        drawTodayLine(ctx: ctx, w: w, h: h)
        drawActivityBars(ctx: ctx, w: w, midY: midY)
        drawPeakMarker(ctx: ctx, w: w, midY: midY)
    }

    private func drawTodayLine(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        // 日の中心に今日ラインを配置
        let x = xForCenter(doy: selectedDOY, width: w)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: h))
        ctx.stroke(path, with: .color(.primary.opacity(0.35)), lineWidth: 1.5)
    }

    private func drawActivityBars(ctx: GraphicsContext, w: CGFloat, midY: CGFloat) {
        let startDOY = shower.activityStartDOY
        let endDOY = shower.activityEndDOY
        let barColor = shower.intensity.color.opacity(0.3)
        let bh = CalendarStyle.barHeight
        let r = bh / 2

        if endDOY <= 365 {
            // 通常: 年内で完結
            let rect = barRect(from: startDOY, to: endDOY, midY: midY, w: w, bh: bh)
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(barColor))
        } else {
            // 年跨ぎ: 2 本に分割
            let r1 = barRect(from: startDOY, to: 365, midY: midY, w: w, bh: bh)
            ctx.fill(Path(roundedRect: r1, cornerRadius: r), with: .color(barColor))

            let r2 = barRect(from: 1, to: endDOY - 365, midY: midY, w: w, bh: bh)
            ctx.fill(Path(roundedRect: r2, cornerRadius: r), with: .color(barColor))
        }
    }

    private func drawPeakMarker(ctx: GraphicsContext, w: CGFloat, midY: CGFloat) {
        let peakDOY = MeteorShowerCatalog.dayOfYear(
            month: shower.peakMonth, day: shower.peakDay
        )
        // 日の中心に極大マーカーを配置
        let x = xForCenter(doy: peakDOY, width: w)
        let pr = CalendarStyle.peakRadius
        let rect = CGRect(x: x - pr, y: midY - pr, width: pr * 2, height: pr * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(shower.intensity.color))

        // 極大日のアウトライン
        ctx.stroke(
            Path(ellipseIn: rect),
            with: .color(.white.opacity(0.6)),
            lineWidth: 0.8
        )
    }

    // MARK: Geometry Helpers

    /// 日区間の左端 X 座標（バー描画用）。
    private func xFor(doy: Int, width: CGFloat) -> CGFloat {
        CGFloat(doy - 1) / 365.0 * width
    }

    /// 日の中心 X 座標（マーカー・今日ライン用）。
    private func xForCenter(doy: Int, width: CGFloat) -> CGFloat {
        (CGFloat(doy) - 0.5) / 365.0 * width
    }

    private func barRect(from startDOY: Int, to endDOY: Int, midY: CGFloat, w: CGFloat, bh: CGFloat) -> CGRect {
        let x = xFor(doy: startDOY, width: w)
        let endX = xFor(doy: endDOY + 1, width: w)
        return CGRect(x: x, y: midY - bh / 2, width: max(endX - x, 2), height: bh)
    }
}

// MARK: - CalendarStyle

private enum CalendarStyle {
    static let labelWidth: CGFloat = 110
    static let rowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 18
    static let barHeight: CGFloat = 10
    static let peakRadius: CGFloat = 5
}

// MARK: - Preview

#Preview {
    ScrollView {
        MeteorShowerCalendarView()
            .padding()
    }
    .frame(width: 600, height: 400)
}
