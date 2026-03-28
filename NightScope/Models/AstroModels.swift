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
    var galacticCenterVisible: Bool { galacticCenterAltitude > 5.0 && isDark }
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
        case 0..<0.04, 0.96...1: return "moonphase.new.moon"
        case 0.04..<0.25: return "moonphase.waxing.crescent"
        case 0.25..<0.30: return "moonphase.first.quarter"
        case 0.30..<0.46: return "moonphase.waxing.gibbous"
        case 0.46..<0.54: return "moonphase.full.moon"
        case 0.54..<0.70: return "moonphase.waning.gibbous"
        case 0.70..<0.80: return "moonphase.last.quarter"
        default: return "moonphase.waning.crescent"
        }
    }

    var isMoonFavorable: Bool {
        moonPhaseAtMidnight < 0.25 || moonPhaseAtMidnight > 0.75
    }

    var totalDarkHours: Double {
        let count = events.filter { $0.isDark }.count
        return Double(count) * 15.0 / 60.0
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

    var overallRating: Int {
        guard !viewingWindows.isEmpty else { return 0 }
        var score = 0
        if totalViewingHours > 3 { score += 2 } else if totalViewingHours > 1 { score += 1 }
        if (maxAltitude ?? 0) > 30 { score += 2 } else if (maxAltitude ?? 0) > 15 { score += 1 }
        if isMoonFavorable { score += 1 }
        return min(score, 5)
    }
}
