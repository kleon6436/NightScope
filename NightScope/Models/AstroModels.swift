import Foundation
import CoreLocation

// MARK: - Models

/// 1つの時刻における天文イベントの観測条件を表すモデル。
/// - Note: 各角度は度数法で保持する。
struct AstroEvent: Identifiable {
    let id = UUID()
    let date: Date
    let galacticCenterAltitude: Double  // degrees above horizon
    let galacticCenterAzimuth: Double   // degrees from north, clockwise
    let sunAltitude: Double             // degrees
    let moonAltitude: Double            // degrees
    let moonPhase: Double               // 0=新月, 0.5=満月

    var isDark: Bool { sunAltitude < -18.0 }           // 天文薄明終了
    var isNauticalDark: Bool { sunAltitude < -12.0 }   // 航海薄明終了
    var isCivilDark: Bool { sunAltitude < -6.0 }       // 市民薄明終了
    /// 根拠: 高度 < 10° では大気差・地物遮蔽により実用的な観測が困難
    var galacticCenterVisible: Bool { galacticCenterAltitude > 10.0 && isDark }
    var isGoodForPhotography: Bool {
        galacticCenterAltitude > 15.0 && isDark && (moonPhase < 0.25 || moonPhase > 0.75)
    }
}

/// 星空マップの視野方向（サイドバーマップのオーバーレイに使用）
/// 星空マップの視野方向を表す補助モデル。
struct ViewingDirection: Equatable {
    /// 画面中心が向く方位角 (度, 0=北, 90=東)
    let azimuth: Double
    /// 水平視野角 (度)
    let fov: Double
    /// 星空マップが表示中か
    let isActive: Bool
}

/// 銀河中心が観測しやすい時間帯を表すウィンドウ。
struct ViewingWindow {
    let start: Date
    let end: Date
    let peakTime: Date
    let peakAltitude: Double
    let peakAzimuth: Double
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// 16方位名（22.5° 刻み）
    private static let directionNames = ["北","北北東","北東","東北東","東","東南東","南東","南南東","南","南南西","南西","西南西","西","西北西","北西","北北西"]

    var peakDirectionName: String {
        let index = Int((peakAzimuth + 11.25) / 22.5) % 16
        return L10n.tr(Self.directionNames[index])
    }

    func accessibilityDescription(timeZone: TimeZone = .current) -> String {
        let timeRange = L10n.format("%@から%@", start.nightTimeString(timeZone: timeZone), end.nightTimeString(timeZone: timeZone))
        let altitude = L10n.format("最大高度%.0f度", peakAltitude)
        let peak = L10n.format("見頃 %@", peakTime.nightTimeString(timeZone: timeZone))
        let direction = L10n.format("方角%@", peakDirectionName)
        return L10n.format("観測窓: %@、%@、%@、%@", timeRange, altitude, peak, direction)
    }
}

/// 1夜分の天文条件と観測可能時間をまとめた集計モデル。
struct NightSummary {
    private typealias WeatherByHour = [Date: HourlyWeather]

    let date: Date
    let location: CLLocationCoordinate2D
    let events: [AstroEvent]
    let viewingWindows: [ViewingWindow]
    let moonPhaseAtMidnight: Double
    /// 日付計算に使う IANA タイムゾーン識別子。
    let timeZoneIdentifier: String

    init(
        date: Date,
        location: CLLocationCoordinate2D,
        events: [AstroEvent],
        viewingWindows: [ViewingWindow],
        moonPhaseAtMidnight: Double,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.date = date
        self.location = location
        self.events = events
        self.viewingWindows = viewingWindows
        self.moonPhaseAtMidnight = moonPhaseAtMidnight
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// `timeZoneIdentifier` が無効な場合は現在のタイムゾーンに退避する。
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    private var bestWindow: ViewingWindow? {
        viewingWindows.max(by: { $0.peakAltitude < $1.peakAltitude })
    }
    var bestViewingWindow: ViewingWindow? { bestWindow }
    var bestViewingTime: Date?  { bestWindow?.peakTime }
    var maxAltitude: Double?    { bestWindow?.peakAltitude }
    var bestDirection: String?  { bestWindow?.peakDirectionName }
    var totalViewingHours: Double {
        viewingWindows.reduce(0) { $0 + $1.duration } / 3600
    }

    var moonPhaseName: String {
        switch moonPhaseAtMidnight {
        case 0..<0.04, 0.96...1: return L10n.tr("新月")
        case 0.04..<0.12: return L10n.tr("繊月")
        case 0.12..<0.22: return L10n.tr("三日月")
        case 0.22..<0.30: return L10n.tr("上弦の月")
        case 0.30..<0.46: return L10n.tr("十日月")
        case 0.46..<0.54: return L10n.tr("満月")
        case 0.54..<0.70: return L10n.tr("十六夜")
        case 0.70..<0.80: return L10n.tr("下弦の月")
        case 0.80..<0.96: return L10n.tr("有明月")
        default: return ""
        }
    }

    var moonPhaseIcon: String {
        switch moonPhaseAtMidnight {
        case 0..<0.04, 0.96...1: return AppIcons.Astronomy.moonPhaseNew
        case 0.04..<0.12: return AppIcons.Astronomy.moonPhaseWaxingCrescent
        case 0.12..<0.22: return AppIcons.Astronomy.moonPhaseWaxingCrescent
        case 0.22..<0.30: return AppIcons.Astronomy.moonPhaseFirstQuarter
        case 0.30..<0.46: return AppIcons.Astronomy.moonPhaseWaxingGibbous
        case 0.46..<0.54: return AppIcons.Astronomy.moonPhaseFull
        case 0.54..<0.70: return AppIcons.Astronomy.moonPhaseWaningGibbous
        case 0.70..<0.80: return AppIcons.Astronomy.moonPhaseLastQuarter
        case 0.80..<0.96: return AppIcons.Astronomy.moonPhaseWaningCrescent
        default: return AppIcons.Astronomy.moonPhaseWaningCrescent
        }
    }

    var isMoonFavorable: Bool {
        moonPhaseAtMidnight < 0.25 || moonPhaseAtMidnight > 0.75
    }

    var totalDarkHours: Double {
        let count = events.filter { $0.isDark }.count
        return Double(count) * 15.0 / 60.0
    }

    /// 天文薄明中に月が地平線上（高度 > 0°）にある時間の割合 (0.0–1.0)
    /// 根拠: 月が地平線以下の時間帯は照明影響を受けないため、スコア計算で減点不要
    var moonAboveHorizonFractionDuringDark: Double {
        let darkEvents = events.filter { $0.isDark }
        guard !darkEvents.isEmpty else { return 0 }
        let visibleCount = darkEvents.filter { $0.moonAltitude > 0 }.count
        return Double(visibleCount) / Double(darkEvents.count)
    }

    private var darkEvents: [AstroEvent] { events.filter { $0.isDark } }

    /// 夕方側の暗い時間の開始（12時以降の最初の isDark イベント）
    var eveningDarkStart: Date? {
        let cal = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        return darkEvents.first { cal.component(.hour, from: $0.date) >= 12 }?.date
    }

    /// 早朝側の暗い時間の終了（12時前の最後の isDark イベントの次の区間）
    var morningDarkEnd: Date? {
        let cal = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        return darkEvents.last { cal.component(.hour, from: $0.date) < 12 }.map {
            $0.date.addingTimeInterval(MilkyWayCalculator.Constants.sampleIntervalSeconds)
        }
    }

    /// 天気を考慮した最長連続観測可能ウィンドウ（暗闇 + 晴れ間）
    /// - Parameter nighttimeHours: DayWeatherSummary.nighttimeHours
    /// - Returns: (start, end) または nil（観測可能な時間帯なし）
    func weatherAwareObservableWindow(
        nighttimeHours: [HourlyWeather],
        referenceDate: Date = Date()
    ) -> (start: Date, end: Date)? {
        let clearDarkEvents = weatherFilteredDarkEvents(
            nighttimeHours: nighttimeHours,
            referenceDate: referenceDate,
            includeMoonFilter: true
        )
        guard let clearDarkEvents, !clearDarkEvents.isEmpty else { return nil }
        return longestMergedWindow(
            from: clearDarkEvents.map(\.date),
            mergeGap: MilkyWayCalculator.Constants.windowMergeGapSeconds
        )
    }

    /// 天気を考慮した観測可能時間帯の範囲文字列（例: "22:00 〜 04:15"）
    /// - Returns:
    ///   - nil    : 天気データなし（呼び出し元で天文学的時間にフォールバック）
    ///   - ""     : 天候不良で観測不可
    ///   - "月明かり": 天気は良好だが月が明るすぎる
    ///   - その他 : 観測可能な時間帯文字列
    func weatherAwareRangeText(
        nighttimeHours: [HourlyWeather],
        referenceDate: Date = Date()
    ) -> String? {
        guard hasUsableWeatherData(nighttimeHours: nighttimeHours, referenceDate: referenceDate) else { return nil }
        if let w = weatherAwareObservableWindow(nighttimeHours: nighttimeHours, referenceDate: referenceDate) {
            return "\(w.start.nightTimeString(timeZone: timeZone)) 〜 \(w.end.nightTimeString(timeZone: timeZone))"
        }
        // 観測可能ウィンドウなし — 月フィルタなしで再チェックし原因を判定
        let weatherOnlyClearEvents = weatherFilteredDarkEvents(
            nighttimeHours: nighttimeHours,
            referenceDate: referenceDate,
            includeMoonFilter: false
        )
        let hasWeatherClearDarkHour = weatherOnlyClearEvents.map { !$0.isEmpty } ?? false
        return hasWeatherClearDarkHour ? L10n.tr("月明かり") : ""
    }

    /// 天気フィルタを適用した暗いイベントを返す（共通ヘルパー）
    /// - Returns: nil = 天気データ不十分, [] = 条件を満たすイベントなし
    private func weatherFilteredDarkEvents(
        nighttimeHours: [HourlyWeather],
        referenceDate: Date,
        includeMoonFilter: Bool
    ) -> [AstroEvent]? {
        guard let context = usableWeatherContext(
            nighttimeHours: nighttimeHours,
            referenceDate: referenceDate
        ) else {
            return nil
        }
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let weatherByHour = makeWeatherByHour(nighttimeHours: context.weather.nighttimeHours, calendar: calendar)
        let coveredEvents = coveredDarkEvents(nighttimeHours: context.weather.nighttimeHours, calendar: calendar)
        return filteredDarkEvents(
            events: coveredEvents,
            weatherByHour: weatherByHour,
            calendar: calendar,
            includeMoonFilter: includeMoonFilter
        )
    }

    func hasReliableWeatherData(nighttimeHours: [HourlyWeather]) -> Bool {
        let coverage = darkWeatherCoverage(nighttimeHours: nighttimeHours)
        return coverage.hasFullCoverage && !coverage.hours.isEmpty
    }

    func hasUsableWeatherData(
        nighttimeHours: [HourlyWeather],
        referenceDate: Date = Date()
    ) -> Bool {
        usableWeatherContext(nighttimeHours: nighttimeHours, referenceDate: referenceDate) != nil
    }

    func usableWeatherContext(
        nighttimeHours: [HourlyWeather],
        referenceDate: Date = Date()
    ) -> (summary: NightSummary, weather: DayWeatherSummary, isPartial: Bool)? {
        let coverage = darkWeatherCoverage(nighttimeHours: nighttimeHours)
        guard !coverage.hours.isEmpty else { return nil }

        if coverage.hasFullCoverage {
            return (
                self,
                DayWeatherSummary(date: date, nighttimeHours: coverage.hours),
                false
            )
        }

        guard ObservationTimeZone.isDateInToday(date, timeZone: timeZone, referenceDate: referenceDate),
              let partialSummary = clippedToCoveredDarkHours(coverage.hours) else {
            return nil
        }

        return (
            partialSummary,
            DayWeatherSummary(date: date, nighttimeHours: coverage.hours),
            true
        )
    }

    private func makeWeatherByHour(nighttimeHours: [HourlyWeather], calendar: Calendar) -> WeatherByHour {
        Dictionary(
            uniqueKeysWithValues: nighttimeHours.compactMap { weather in
                guard let hourStart = calendar.dateInterval(of: .hour, for: weather.date)?.start else {
                    return nil
                }
                return (hourStart, weather)
            }
        )
    }

    private func darkWeatherCoverage(nighttimeHours: [HourlyWeather]) -> (hours: [HourlyWeather], hasFullCoverage: Bool) {
        let expectedHourStarts = darkHourStarts
        guard !expectedHourStarts.isEmpty else {
            return ([], false)
        }

        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let matchedHours = nighttimeHours.filter { weather in
            guard let hourStart = calendar.dateInterval(of: .hour, for: weather.date)?.start else {
                return false
            }
            return expectedHourStarts.contains(hourStart)
        }

        let matchedHourStarts = Set(matchedHours.compactMap { weather in
            calendar.dateInterval(of: .hour, for: weather.date)?.start
        })

        return (
            matchedHours.sorted { $0.date < $1.date },
            matchedHourStarts == expectedHourStarts
        )
    }

    private var darkHourStarts: Set<Date> {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        return Set(darkEvents.compactMap { event in
            calendar.dateInterval(of: .hour, for: event.date)?.start
        })
    }

    private func coveredDarkEvents(nighttimeHours: [HourlyWeather], calendar: Calendar) -> [AstroEvent] {
        let coveredHourStarts = Set(nighttimeHours.compactMap { weather in
            calendar.dateInterval(of: .hour, for: weather.date)?.start
        })
        return events.filter { event in
            guard event.isDark,
                  let hourStart = calendar.dateInterval(of: .hour, for: event.date)?.start else {
                return false
            }
            return coveredHourStarts.contains(hourStart)
        }
    }

    private func clippedToCoveredDarkHours(_ nighttimeHours: [HourlyWeather]) -> NightSummary? {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let coveredEvents = coveredDarkEvents(nighttimeHours: nighttimeHours, calendar: calendar)
        guard !coveredEvents.isEmpty else { return nil }

        return NightSummary(
            date: date,
            location: location,
            events: coveredEvents,
            viewingWindows: MilkyWayCalculator.findViewingWindows(events: coveredEvents),
            moonPhaseAtMidnight: moonPhaseAtMidnight,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func filteredDarkEvents(
        events: [AstroEvent],
        weatherByHour: WeatherByHour,
        calendar: Calendar,
        includeMoonFilter: Bool
    ) -> [AstroEvent] {
        events.filter { event in
            guard passesWeatherFilter(event: event, weatherByHour: weatherByHour, calendar: calendar) else {
                return false
            }
            if includeMoonFilter {
                return passesMoonFilter(event: event)
            }
            return true
        }
    }

    private func passesWeatherFilter(event: AstroEvent, weatherByHour: WeatherByHour, calendar: Calendar) -> Bool {
        guard let hourStart = calendar.dateInterval(of: .hour, for: event.date)?.start else {
            return true
        }
        guard let weather = weatherByHour[hourStart] else {
            return true
        }
        // 根拠: 75% 未満が星空指数の雲量スコアで 0点 超（≥75% = 完全不可）の境界
        //       星空指数は夜間全体の平均を使うが、ここは1時間ごとのチェックのため
        //       より緩い 75% を適用して一貫性を保つ
        return weather.cloudCoverPercent < 75
        && weather.precipitationMM < 0.1
        && weather.weatherCode < 45
    }

    private func passesMoonFilter(event: AstroEvent) -> Bool {
        // ── 月フィルタ（星空指数と同一基準） ──
        // illumination = (1 - cos(phase × 2π)) / 2
        // 根拠: Krisciunas & Schaefer (1991): illumination ≥ 0.30（上弦付近）で
        //       空輝度が自然夜空の30〜50倍に達し観測不可
        let illumination = (1.0 - cos(event.moonPhase * 2.0 * .pi)) / 2.0
        return !(event.moonAltitude > 0 && illumination >= 0.30)
    }

    private func longestMergedWindow(
        from dates: [Date],
        mergeGap: TimeInterval
    ) -> (start: Date, end: Date)? {
        let sorted = dates.sorted()
        guard let first = sorted.first else { return nil }

        var bestStart = first
        var bestEnd = first
        var currentStart = first
        var currentEnd = first

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]

            if current.timeIntervalSince(previous) <= mergeGap {
                currentEnd = current
                continue
            }

            if currentEnd.timeIntervalSince(currentStart) > bestEnd.timeIntervalSince(bestStart) {
                bestStart = currentStart
                bestEnd = currentEnd
            }
            currentStart = current
            currentEnd = current
        }

        if currentEnd.timeIntervalSince(currentStart) > bestEnd.timeIntervalSince(bestStart) {
            bestStart = currentStart
            bestEnd = currentEnd
        }

        return (start: bestStart, end: bestEnd.addingTimeInterval(MilkyWayCalculator.Constants.sampleIntervalSeconds))
    }

    /// 暗い観測時間帯の範囲文字列（例: "21:00 〜 03:30"）
    var darkRangeText: String {
        if let eStart = eveningDarkStart, let mEnd = morningDarkEnd {
            return "\(eStart.nightTimeString(timeZone: timeZone)) 〜 \(mEnd.nightTimeString(timeZone: timeZone))"
        } else if let eStart = eveningDarkStart {
            return L10n.format("%@ 〜 翌朝", eStart.nightTimeString(timeZone: timeZone))
        } else if let mEnd = morningDarkEnd {
            return L10n.format("深夜 〜 %@", mEnd.nightTimeString(timeZone: timeZone))
        } else {
            return ""
        }
    }

    /// スケルトン表示用のプレースホルダー
    static var placeholder: NightSummary {
        NightSummary(
            date: Date(),
            location: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            events: [],
            viewingWindows: [],
            moonPhaseAtMidnight: 0.0
        )
    }
}

// MARK: - Planet Position

/// 太陽系天体の見かけの位置と光度を表すモデル。
struct PlanetPosition: Identifiable {
    let name: String
    let altitude: Double          // degrees (-90〜90)
    let azimuth: Double           // degrees (0=北, 90=東)
    let magnitude: Double         // apparent magnitude
    let geocentricDistAU: Double  // geocentric distance in AU
    var id: String { name }

    var localizedName: String {
        L10n.tr(name)
    }
}
