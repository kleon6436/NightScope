import Foundation
import CoreLocation

// MARK: - Models

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
struct ViewingDirection: Equatable {
    /// 画面中心が向く方位角 (度, 0=北, 90=東)
    let azimuth: Double
    /// 水平視野角 (度)
    let fov: Double
    /// 星空マップが表示中か
    let isActive: Bool
}

struct ViewingWindow {
    let start: Date
    let end: Date
    let peakTime: Date
    let peakAltitude: Double
    let peakAzimuth: Double
    var duration: TimeInterval { end.timeIntervalSince(start) }

    var peakDirectionName: String {
        let directions = ["北","北北東","北東","東北東","東","東南東","南東","南南東","南","南南西","南西","西南西","西","西北西","北西","北北西"]
        let index = Int((peakAzimuth + 11.25) / 22.5) % 16
        return directions[index]
    }

    func accessibilityDescription() -> String {
        let timeRange = "\(start.nightTimeString())から\(end.nightTimeString())"
        let altitude = String(format: "最大高度%.0f度", peakAltitude)
        let peak = "見頃\(peakTime.nightTimeString())"
        let direction = "方角\(peakDirectionName)"
        return "観測窓: \(timeRange)、\(altitude)、\(peak)、\(direction)"
    }
}

struct NightSummary {
    private typealias WeatherByHour = [Int: HourlyWeather]
    private typealias AdjustedNightEvent = (original: Date, sortKey: Date)

    let date: Date
    let location: CLLocationCoordinate2D
    let events: [AstroEvent]
    let viewingWindows: [ViewingWindow]
    let moonPhaseAtMidnight: Double

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
        case 0..<0.04, 0.96...1: return "新月"
        case 0.04..<0.12: return "繊月"
        case 0.12..<0.22: return "三日月"
        case 0.22..<0.30: return "上弦の月"
        case 0.30..<0.46: return "十日月"
        case 0.46..<0.54: return "満月"
        case 0.54..<0.70: return "十六夜"
        case 0.70..<0.80: return "下弦の月"
        case 0.80..<0.96: return "有明月"
        default: return ""
        }
    }

    var moonPhaseIcon: String {
        switch moonPhaseAtMidnight {
        case 0..<0.04, 0.96...1: return AppIcons.Astronomy.moonPhaseNew
        case 0.04..<0.25: return AppIcons.Astronomy.moonPhaseWaxingCrescent
        case 0.25..<0.30: return AppIcons.Astronomy.moonPhaseFirstQuarter
        case 0.30..<0.46: return AppIcons.Astronomy.moonPhaseWaxingGibbous
        case 0.46..<0.54: return AppIcons.Astronomy.moonPhaseFull
        case 0.54..<0.70: return AppIcons.Astronomy.moonPhaseWaningGibbous
        case 0.70..<0.80: return AppIcons.Astronomy.moonPhaseLastQuarter
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
        let cal = Calendar.current
        return darkEvents.first { cal.component(.hour, from: $0.date) >= 12 }?.date
    }

    /// 早朝側の暗い時間の終了（12時前の最後の isDark イベントの次の区間）
    var morningDarkEnd: Date? {
        let cal = Calendar.current
        return darkEvents.last { cal.component(.hour, from: $0.date) < 12 }.map {
            $0.date.addingTimeInterval(15 * 60)
        }
    }

    /// 天気を考慮した最長連続観測可能ウィンドウ（暗闇 + 晴れ間）
    /// - Parameter nighttimeHours: DayWeatherSummary.nighttimeHours
    /// - Returns: (start, end) または nil（観測可能な時間帯なし）
    func weatherAwareObservableWindow(nighttimeHours: [HourlyWeather]) -> (start: Date, end: Date)? {
        guard !nighttimeHours.isEmpty else { return nil }
        let calendar = Calendar.current
        let weatherByHour = makeWeatherByHour(nighttimeHours: nighttimeHours, calendar: calendar)
        let clearDarkEvents = filteredDarkEvents(
            weatherByHour: weatherByHour,
            calendar: calendar,
            includeMoonFilter: true
        )
        guard !clearDarkEvents.isEmpty else { return nil }
        let adjusted = adjustForNightBoundary(events: clearDarkEvents, calendar: calendar)
        return longestMergedWindow(from: adjusted, mergeGap: MilkyWayCalculator.Constants.windowMergeGapSeconds)
    }

    /// 天気を考慮した観測可能時間帯の範囲文字列（例: "22:00 〜 04:15"）
    /// - Returns:
    ///   - nil    : 天気データなし（呼び出し元で天文学的時間にフォールバック）
    ///   - ""     : 天候不良で観測不可
    ///   - "月明かり": 天気は良好だが月が明るすぎる
    ///   - その他 : 観測可能な時間帯文字列
    func weatherAwareRangeText(nighttimeHours: [HourlyWeather]) -> String? {
        guard !nighttimeHours.isEmpty else { return nil }
        if let w = weatherAwareObservableWindow(nighttimeHours: nighttimeHours) {
            return "\(w.start.nightTimeString()) 〜 \(w.end.nightTimeString())"
        }
        // 観測可能ウィンドウなし — 原因を判定して適切なメッセージを返す
        // 天気フィルタのみ（月フィルタなし）で暗いイベントが存在すれば月が原因
        let calendar = Calendar.current
        let weatherByHour = makeWeatherByHour(nighttimeHours: nighttimeHours, calendar: calendar)
        let hasWeatherClearDarkHour = !filteredDarkEvents(
            weatherByHour: weatherByHour,
            calendar: calendar,
            includeMoonFilter: false
        ).isEmpty
        return hasWeatherClearDarkHour ? "月明かり" : ""
    }

    private func makeWeatherByHour(nighttimeHours: [HourlyWeather], calendar: Calendar) -> WeatherByHour {
        // 時刻（0-23）をキーにする。
        // 根拠: nighttimeHours は 18-23 時（当日）と 0-6 時（翌日 → 前日キー）で重複なし。
        //       UTCタイムスタンプをキーにすると翌日分の朝時間が一致しないため、
        //       時刻のみでマッチングすることで日付をまたいでも正しく対応できる。
        Dictionary(
            nighttimeHours.map { (calendar.component(.hour, from: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func filteredDarkEvents(
        weatherByHour: WeatherByHour,
        calendar: Calendar,
        includeMoonFilter: Bool
    ) -> [AstroEvent] {
        events.filter { event in
            guard event.isDark else { return false }
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
        let hour = calendar.component(.hour, from: event.date)
        guard let weather = weatherByHour[hour] else {
            return true
        }
        // 実効雲量: 層別データがあれば加重計算（星空指数と同一ロジック）、なければ総合雲量
        // 根拠: 75% 未満が星空指数の雲量スコアで 0点 超（≥75% = 完全不可）の境界
        //       星空指数は夜間全体の平均を使うが、ここは1時間ごとのチェックのため
        //       より緩い 75% を適用して一貫性を保つ
        return weather.effectiveCloudCover < 75
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

    private func adjustForNightBoundary(events: [AstroEvent], calendar: Calendar) -> [AdjustedNightEvent] {
        // 夜をまたぐ連続性を正しく判定するため、深夜前（hour < 12）のイベントに24時間を加算して
        // 夕方イベントの後に連続するものとして扱う。
        // 根拠: 天文学的な1夜は前日夕方〜翌朝にわたるためカレンダー上の0時で分断してはいけない。
        //       例) 夕方23:45 → 翌朝00:00 の間隔は15分（連続）だが、
        //           タイムスタンプ差はマイナスになるため+24h補正が必要。
        events.map { event in
            let hour = calendar.component(.hour, from: event.date)
            let sortKey = hour < 12 ? event.date.addingTimeInterval(86400) : event.date
            return (original: event.date, sortKey: sortKey)
        }
    }

    private func longestMergedWindow(
        from adjustedEvents: [AdjustedNightEvent],
        mergeGap: TimeInterval
    ) -> (start: Date, end: Date)? {
        let sorted = adjustedEvents.sorted { $0.sortKey < $1.sortKey }
        guard let first = sorted.first else { return nil }

        var bestStart = first
        var bestEnd = first
        var currentStart = first
        var currentEnd = first

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]

            if current.sortKey.timeIntervalSince(previous.sortKey) <= mergeGap {
                currentEnd = current
                continue
            }

            if currentEnd.sortKey.timeIntervalSince(currentStart.sortKey) > bestEnd.sortKey.timeIntervalSince(bestStart.sortKey) {
                bestStart = currentStart
                bestEnd = currentEnd
            }
            currentStart = current
            currentEnd = current
        }

        if currentEnd.sortKey.timeIntervalSince(currentStart.sortKey) > bestEnd.sortKey.timeIntervalSince(bestStart.sortKey) {
            bestStart = currentStart
            bestEnd = currentEnd
        }

        return (start: bestStart.original, end: bestEnd.original.addingTimeInterval(15 * 60))
    }

    /// 暗い観測時間帯の範囲文字列（例: "21:00 〜 03:30"）
    var darkRangeText: String {
        if let eStart = eveningDarkStart, let mEnd = morningDarkEnd {
            return "\(eStart.nightTimeString()) 〜 \(mEnd.nightTimeString())"
        } else if let eStart = eveningDarkStart {
            return "\(eStart.nightTimeString()) 〜 翌朝"
        } else if let mEnd = morningDarkEnd {
            return "深夜 〜 \(mEnd.nightTimeString())"
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

struct PlanetPosition: Identifiable {
    let name: String
    let altitude: Double          // degrees (-90〜90)
    let azimuth: Double           // degrees (0=北, 90=東)
    let magnitude: Double         // apparent magnitude
    let geocentricDistAU: Double  // geocentric distance in AU
    var id: String { name }
}
