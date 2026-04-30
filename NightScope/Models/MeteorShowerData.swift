import Foundation

/// 流星群 1 件分の観測カタログ情報。
struct MeteorShower: Identifiable {
    let id: String
    let name: String                  // 表示名（日本語）
    let radiantRA: Double             // 放射点 赤経 (度)
    let radiantDec: Double            // 放射点 赤緯 (度)
    let peakMonth: Int                // ピーク月
    let peakDay: Int                  // ピーク日
    let activityDays: Int             // 活動期間（ピーク前後 ±activityDays 日）
    let activityStartMonth: Int       // 活動開始月
    let activityStartDay: Int         // 活動開始日
    let activityEndMonth: Int         // 活動終了月
    let activityEndDay: Int           // 活動終了日
    let zhr: Int                      // 極大 ZHR (Zenithal Hourly Rate)
    let symbol: String                // SF Symbol or emoji

    var localizedName: String {
        L10n.tr(name)
    }

    /// 年間 (1〜365) での活動開始 day-of-year。
    var activityStartDOY: Int {
        MeteorShowerCatalog.dayOfYear(month: activityStartMonth, day: activityStartDay)
    }

    /// 年間 (1〜365) での活動終了 day-of-year。年跨ぎの場合は 365 超になる。
    var activityEndDOY: Int {
        let end = MeteorShowerCatalog.dayOfYear(month: activityEndMonth, day: activityEndDay)
        let start = activityStartDOY
        // 年跨ぎ検出: 終了が開始より小さければ翌年扱い
        return end >= start ? end : end + 365
    }

    /// 指定した day-of-year (1〜365) がこの流星群の活動期間内かを返す。
    func contains(dayOfYear doy: Int) -> Bool {
        let startDOY = activityStartDOY
        let endDOY   = activityEndDOY
        if endDOY <= 365 {
            return doy >= startDOY && doy <= endDOY
        } else {
            // 年跨ぎ: 12月末 or 1月初め
            return doy >= startDOY || doy <= (endDOY - 365)
        }
    }

    /// ZHR 強度カテゴリ。
    var intensity: MeteorShowerIntensity {
        switch zhr {
        case 100...: return .high
        case 50...:  return .medium
        default:     return .low
        }
    }
}

/// ZHR 強度カテゴリ。
enum MeteorShowerIntensity {
    case high    // ZHR ≥ 100
    case medium  // ZHR ≥ 50
    case low     // ZHR < 50
}

// MARK: - Major Meteor Showers Catalog

/// 主要流星群の静的カタログ。
enum MeteorShowerCatalog {
    static let all: [MeteorShower] = [
        MeteorShower(
            id: "quadrantids",   name: "しぶんぎ座流星群",
            radiantRA: 230.1, radiantDec: 48.5,
            peakMonth:  1, peakDay:  4, activityDays: 2,
            activityStartMonth: 12, activityStartDay: 28,
            activityEndMonth:    1, activityEndDay:  12,
            zhr: 120, symbol: "✦"
        ),
        MeteorShower(
            id: "lyrids",        name: "こと座流星群",
            radiantRA: 271.4, radiantDec: 33.6,
            peakMonth:  4, peakDay: 22, activityDays: 3,
            activityStartMonth:  4, activityStartDay: 16,
            activityEndMonth:    4, activityEndDay:  25,
            zhr:  18, symbol: "✦"
        ),
        MeteorShower(
            id: "eta_aquarids",  name: "みずがめ座流星群",
            radiantRA: 338.0, radiantDec: -1.0,
            peakMonth:  5, peakDay:  6, activityDays: 5,
            activityStartMonth:  4, activityStartDay: 19,
            activityEndMonth:    5, activityEndDay:  28,
            zhr:  50, symbol: "✦"
        ),
        MeteorShower(
            id: "perseids",      name: "ペルセウス座流星群",
            radiantRA:  48.2, radiantDec: 58.1,
            peakMonth:  8, peakDay: 13, activityDays: 5,
            activityStartMonth:  7, activityStartDay: 17,
            activityEndMonth:    8, activityEndDay:  24,
            zhr: 100, symbol: "✦"
        ),
        MeteorShower(
            id: "orionids",      name: "オリオン座流星群",
            radiantRA:  95.0, radiantDec: 16.0,
            peakMonth: 10, peakDay: 21, activityDays: 4,
            activityStartMonth: 10, activityStartDay:  2,
            activityEndMonth:   11, activityEndDay:   7,
            zhr:  20, symbol: "✦"
        ),
        MeteorShower(
            id: "leonids",       name: "しし座流星群",
            radiantRA: 153.5, radiantDec: 22.0,
            peakMonth: 11, peakDay: 17, activityDays: 3,
            activityStartMonth: 11, activityStartDay:  6,
            activityEndMonth:   11, activityEndDay:  30,
            zhr:  15, symbol: "✦"
        ),
        MeteorShower(
            id: "geminids",      name: "ふたご座流星群",
            radiantRA: 112.3, radiantDec: 32.5,
            peakMonth: 12, peakDay: 14, activityDays: 4,
            activityStartMonth: 12, activityStartDay:  4,
            activityEndMonth:   12, activityEndDay:  17,
            zhr: 150, symbol: "✦"
        ),
        MeteorShower(
            id: "ursids",        name: "こぐま座流星群",
            radiantRA: 217.0, radiantDec: 76.0,
            peakMonth: 12, peakDay: 22, activityDays: 3,
            activityStartMonth: 12, activityStartDay: 17,
            activityEndMonth:   12, activityEndDay:  26,
            zhr:  10, symbol: "✦"
        ),
    ]

    // 指定日時付近でアクティブな流星群を返す（最大3件）
    /// 指定日時に活動中の流星群を ZHR の高い順で返す。
    static func active(on date: Date, timeZone: TimeZone = .current) -> [MeteorShower] {
        let cal   = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        let doy   = dayOfYear(month: month, day: day)

        return all
            .filter { $0.contains(dayOfYear: doy) }
            .sorted { $0.zhr > $1.zhr }
    }

    // 次の流星群（極大日が最も近い）
    /// 指定日時以降で最も近い極大日の流星群を返す。
    static func next(after date: Date, timeZone: TimeZone = .current) -> (shower: MeteorShower, daysUntilPeak: Int)? {
        let cal   = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        let doy   = dayOfYear(month: month, day: day)

        return all
            .map { shower -> (MeteorShower, Int) in
                let peak = dayOfYear(month: shower.peakMonth, day: shower.peakDay)
                let diff = (peak - doy + 365) % 365
                return (shower, diff)
            }
            .filter { $0.1 > 0 }
            .min { $0.1 < $1.1 }
            .map { ($0.0, $0.1) }
    }

    static func dayOfYear(month: Int, day: Int) -> Int {
        let months = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let m = max(1, min(month, 12))
        return months[m - 1] + day
    }
}
