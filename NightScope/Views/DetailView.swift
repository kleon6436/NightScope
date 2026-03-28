import SwiftUI

struct DetailView: View {
    @ObservedObject var appController: AppController

    var body: some View {
        Group {
            if appController.isCalculating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("計算中...")
                        .foregroundColor(.secondary)
                }
            } else if let summary = appController.nightSummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(summary: summary)
                        Divider()
                        viewingWindowsSection(summary: summary)
                        Divider()
                        upcomingSection
                    }
                    .padding(24)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    // MARK: - Header

    func headerSection(summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(appController.locationController.locationName)
                    .font(.largeTitle.bold())
                Text(summary.date, style: .date)
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let index = appController.starGazingIndex {
                Divider()
                Text("星空観測情報")
                    .font(.title3.bold())
                starGazingIndexCard(index: index)
            }

            GlassEffectContainer {
                HStack(alignment: .top, spacing: 6) {
                    infoCard(
                        icon: summary.moonPhaseIcon,
                        iconColor: Color(NSColor.systemIndigo),
                        title: "月の状態",
                        value: summary.moonPhaseName,
                        subtitle: summary.isMoonFavorable ? "撮影に適しています" : "月明かりに注意"
                    )

                    darkTimeCard(summary: summary)

                    weatherCard(for: appController.selectedDate)
                }
            }
        }
    }

    func scoreColor(for tier: StarGazingIndex.Tier) -> Color {
        switch tier {
        case .excellent, .good: return .green
        case .fair:             return .yellow
        case .poor:             return .orange
        case .bad:              return .red
        }
    }

    func weatherIconColor(code: Int) -> Color {
        switch code {
        case 0, 1:       return .yellow
        case 2:          return .secondary
        case 3:          return .secondary
        case 45, 48:     return .secondary
        case 51...65:    return .blue
        case 71...77:    return Color.blue.opacity(0.7)
        case 80...82:    return .blue
        case 85, 86:     return Color.blue.opacity(0.7)
        case 95...99:    return .orange
        default:         return .secondary
        }
    }

    func starGazingIndexCard(index: StarGazingIndex) -> some View {
        let color = scoreColor(for: index.tier)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("星空指数")
                        .font(.body)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(index.score)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                        Text("/ 100")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .frame(height: 50)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { i in
                                Image(systemName: i < index.starCount ? "star.fill" : "star")
                                    .foregroundColor(i < index.starCount ? color : Color.gray.opacity(0.4))
                                    .font(.body)
                            }
                        }
                        Text(index.label)
                            .font(.headline)
                            .foregroundColor(color)
                    }

                    subScoreRow(label: "星空", score: index.constellationScore, maxScore: 50, color: Color(NSColor.systemIndigo))

                    if index.hasWeatherData {
                        subScoreRow(label: "気象", score: index.weatherScore, maxScore: 40, color: .cyan)
                    } else {
                        HStack(spacing: 6) {
                            Text("気象")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text("データなし")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    if index.hasLightPollutionData {
                        subScoreRow(label: "光害", score: index.lightPollutionScore, maxScore: 10, color: .orange)
                    } else {
                        HStack(spacing: 6) {
                            Text("光害")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                            if appController.lightPollutionService.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
                            } else if appController.lightPollutionService.fetchFailed {
                                Text("取得失敗")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("取得中...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    subScoreRow(label: "天の川", score: index.milkyWayScore, maxScore: 25, color: .yellow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    func subScoreRow(label: String, score: Int, maxScore: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: Double(score), total: Double(maxScore))
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: 100)
            Text("\(score)/\(maxScore)")
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    func weatherCard(for date: Date) -> some View {
        let weather = appController.weatherService.summary(for: date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "cloud")
                    .foregroundColor(.cyan)
                    .font(.body)
                Text("天気 (夜間)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            if appController.weatherService.isLoading {
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

    func darkTimeCard(summary: NightSummary) -> some View {
        let rangeText: String
        if let eStart = summary.eveningDarkStart, let mEnd = summary.morningDarkEnd {
            rangeText = "\(timeString(eStart)) 〜 \(timeString(mEnd))"
        } else if let eStart = summary.eveningDarkStart {
            rangeText = "\(timeString(eStart)) 〜 翌朝"
        } else if let mEnd = summary.morningDarkEnd {
            rangeText = "深夜 〜 \(timeString(mEnd))"
        } else {
            rangeText = ""
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .foregroundColor(.green)
                    .font(.body)
                Text("観測可能時間")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            if rangeText.isEmpty {
                Text("暗い時間なし")
                    .font(.headline)
            } else {
                Text(rangeText)
                    .font(.headline)
                Text(String(format: "暗い時間 %.1f時間", summary.totalDarkHours))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    func infoCard(icon: String, iconColor: Color, title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.body)
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Viewing Windows

    func viewingWindowsSection(summary: NightSummary) -> some View {
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

    func windowRow(window: ViewingWindow, isMoonFavorable: Bool) -> some View {
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

    // MARK: - Upcoming Nights

    var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今後2週間の予報")
                    .font(.title3.bold())
                Spacer()
                if !Calendar.current.isDateInToday(appController.selectedDate) {
                    Button("今日") { appController.selectedDate = Date() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            let displayNights = appController.upcomingNights.filter { !$0.viewingWindows.isEmpty }

            if displayNights.isEmpty {
                Text("今後2週間は観測に適した夜がありません")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                        ForEach(displayNights, id: \.date) { night in
                            upcomingNightCard(night: night)
                        }
                    }
                }
            }
        }
    }

    func upcomingNightCard(night: NightSummary) -> some View {
        let weather = appController.weatherService.summary(for: night.date)
        let isSelected = Calendar.current.isDate(night.date, inSameDayAs: appController.selectedDate)
        let index = appController.upcomingIndexes[Calendar.current.startOfDay(for: night.date)]

        return VStack(alignment: .leading, spacing: 6) {
            // ── ヘッダー ──
            HStack {
                Text(night.date, style: .date)
                    .font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 13))
                    Text(weather.map { String(format: "%.0f%%", $0.avgCloudCover) } ?? "—")
                        .font(.system(size: 13))
                }
                .foregroundColor(Color.cyan.opacity(0.9))
            }

            if let w = weather {
                HStack(spacing: 4) {
                    Image(systemName: w.weatherIconName)
                        .foregroundColor(weatherIconColor(code: w.representativeWeatherCode))
                        .font(.body)
                    Text(w.weatherLabel == w.cloudLabel
                         ? w.weatherLabel
                         : "\(w.weatherLabel)（\(w.cloudLabel)）")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: night.moonPhaseIcon)
                    .foregroundColor(Color(NSColor.systemIndigo))
                    .font(.body)
                Text(night.moonPhaseName)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Divider()

            // ── 星空 / 天の川 2カラム ──
            HStack(alignment: .top, spacing: 8) {
                // 左: 星空
                VStack(alignment: .leading, spacing: 3) {
                    Text("星空")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let darkRangeText: String = {
                        if let s = night.eveningDarkStart, let e = night.morningDarkEnd {
                            return "\(timeString(s))〜\(timeString(e))"
                        } else if let s = night.eveningDarkStart {
                            return "\(timeString(s))〜翌朝"
                        } else if let e = night.morningDarkEnd {
                            return "深夜〜\(timeString(e))"
                        } else {
                            return "—"
                        }
                    }()
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 5, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: "sparkles")
                                .frame(width: 14, alignment: .center)
                                .foregroundColor(index.map { scoreColor(for: $0.tier) } ?? .secondary)
                            if let idx = index {
                                Text("\(idx.label)")
                                    .font(.headline)
                                    .foregroundColor(scoreColor(for: idx.tier))
                                    .lineLimit(1)
                            } else {
                                Text("計算中…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        GridRow {
                            Image(systemName: "moon.stars")
                                .frame(width: 14, alignment: .center)
                            Text(darkRangeText)
                                .font(.body)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                // 右: 天の川
                VStack(alignment: .leading, spacing: 3) {
                    Text("天の川")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 5, verticalSpacing: 3) {
                        GridRow {
                            Image(systemName: "star")
                                .frame(width: 14, alignment: .center)
                            Text(night.bestViewingTime.map { "見頃 \(timeString($0))" } ?? "見頃 —")
                                .font(.body)
                                .lineLimit(1)
                        }
                        GridRow {
                            Image(systemName: "clock")
                                .frame(width: 14, alignment: .center)
                            Text(String(format: "観測 %.1f時間", night.totalViewingHours))
                                .font(.body)
                                .lineLimit(1)
                        }
                        if let dir = night.bestDirection {
                            GridRow {
                                Image(systemName: "location.north.fill")
                                    .frame(width: 14, alignment: .center)
                                Text(dir)
                                    .font(.body)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 160)
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appController.selectedDate = night.date
        }
    }

    // MARK: - Helpers

    func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
