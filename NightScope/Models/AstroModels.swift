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
}

struct NightSummary {
    let date: Date
    let location: CLLocationCoordinate2D
    let events: [AstroEvent]
    let viewingWindows: [ViewingWindow]
    let moonPhaseAtMidnight: Double

    private var bestWindow: ViewingWindow? {
        viewingWindows.max(by: { $0.peakAltitude < $1.peakAltitude })
    }
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
        let cal = Calendar.current
        // 時刻（0-23）をキーにする。
        // 根拠: nighttimeHours は 18-23 時（当日）と 0-6 時（翌日 → 前日キー）で重複なし。
        //       UTCタイムスタンプをキーにすると翌日分の朝時間が一致しないため、
        //       時刻のみでマッチングすることで日付をまたいでも正しく対応できる。
        let weatherByHour: [Int: HourlyWeather] = Dictionary(
            nighttimeHours.map { (cal.component(.hour, from: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let clearDarkEvents = events.filter { event in
            guard event.isDark else { return false }
            // ── 天気フィルタ ──
            let hour = cal.component(.hour, from: event.date)
            if let w = weatherByHour[hour] {
                // 実効雲量: 層別データがあれば加重計算（星空指数と同一ロジック）、なければ総合雲量
                // 根拠: 75% 未満が星空指数の雲量スコアで 0点 超（≥75% = 完全不可）の境界
                //       星空指数は夜間全体の平均を使うが、ここは1時間ごとのチェックのため
                //       より緩い 75% を適用して一貫性を保つ
                let effectiveCloud: Double
                if let low = w.cloudCoverLowPercent, let mid = w.cloudCoverMidPercent, let high = w.cloudCoverHighPercent {
                    effectiveCloud = low * 1.0 + mid * 0.7 + high * 0.3
                } else {
                    effectiveCloud = w.cloudCoverPercent
                }
                guard effectiveCloud < 75 && w.precipitationMM < 0.1 && w.weatherCode < 45 else { return false }
            }
            // ── 月フィルタ（星空指数と同一基準） ──
            // illumination = (1 - cos(phase × 2π)) / 2
            // 根拠: Krisciunas & Schaefer (1991): illumination ≥ 0.30（上弦付近）で
            //       空輝度が自然夜空の30〜50倍に達し観測不可
            let illumination = (1.0 - cos(event.moonPhase * 2.0 * .pi)) / 2.0
            if event.moonAltitude > 0 && illumination >= 0.30 { return false }
            return true
        }
        guard !clearDarkEvents.isEmpty else { return nil }
        // 夜をまたぐ連続性を正しく判定するため、深夜前（hour < 12）のイベントに24時間を加算して
        // 夕方イベントの後に連続するものとして扱う。
        // 根拠: 天文学的な1夜は前日夕方〜翌朝にわたるためカレンダー上の0時で分断してはいけない。
        //       例) 夕方23:45 → 翌朝00:00 の間隔は15分（連続）だが、
        //           タイムスタンプ差はマイナスになるため+24h補正が必要。
        typealias NightEvent = (original: Date, sortKey: Date)
        let adjusted: [NightEvent] = clearDarkEvents.map { event in
            let hour = cal.component(.hour, from: event.date)
            let key = hour < 12 ? event.date.addingTimeInterval(86400) : event.date
            return (event.date, key)
        }
        let sorted = adjusted.sorted { $0.sortKey < $1.sortKey }
        let mergeGap = MilkyWayCalculator.Constants.windowMergeGapSeconds
        var bestStart = sorted[0]
        var bestEnd   = sorted[0]
        var curStart  = sorted[0]
        var curEnd    = sorted[0]
        for i in 1..<sorted.count {
            if sorted[i].sortKey.timeIntervalSince(sorted[i - 1].sortKey) <= mergeGap {
                curEnd = sorted[i]
            } else {
                if curEnd.sortKey.timeIntervalSince(curStart.sortKey) > bestEnd.sortKey.timeIntervalSince(bestStart.sortKey) {
                    bestStart = curStart; bestEnd = curEnd
                }
                curStart = sorted[i]; curEnd = sorted[i]
            }
        }
        if curEnd.sortKey.timeIntervalSince(curStart.sortKey) > bestEnd.sortKey.timeIntervalSince(bestStart.sortKey) {
            bestStart = curStart; bestEnd = curEnd
        }
        return (start: bestStart.original, end: bestEnd.original.addingTimeInterval(15 * 60))
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
        let cal = Calendar.current
        let weatherByHour: [Int: HourlyWeather] = Dictionary(
            nighttimeHours.map { (cal.component(.hour, from: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hasWeatherClearDarkHour = events.contains { event in
            guard event.isDark else { return false }
            let hour = cal.component(.hour, from: event.date)
            guard let w = weatherByHour[hour] else { return true }
            let effectiveCloud: Double
            if let low = w.cloudCoverLowPercent, let mid = w.cloudCoverMidPercent, let high = w.cloudCoverHighPercent {
                effectiveCloud = low * 1.0 + mid * 0.7 + high * 0.3
            } else {
                effectiveCloud = w.cloudCoverPercent
            }
            return effectiveCloud < 75 && w.precipitationMM < 0.1 && w.weatherCode < 45
        }
        return hasWeatherClearDarkHour ? "月明かり" : ""
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
