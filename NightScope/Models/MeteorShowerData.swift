import Foundation

struct MeteorShower: Identifiable {
    let id: String
    let name: String          // 表示名（日本語）
    let radiantRA: Double     // 放射点 赤経 (度)
    let radiantDec: Double    // 放射点 赤緯 (度)
    let peakMonth: Int        // ピーク月
    let peakDay: Int          // ピーク日
    let activityDays: Int     // 活動期間（ピーク前後 ±activityDays 日）
    let zhr: Int              // 極大 ZHR (Zenithal Hourly Rate)
    let symbol: String        // SF Symbol or emoji
}

// MARK: - Major Meteor Showers Catalog

enum MeteorShowerCatalog {
    static let all: [MeteorShower] = [
        MeteorShower(id: "quadrantids",   name: "しぶんぎ座流星群",   radiantRA: 230.1, radiantDec: 48.5,  peakMonth:  1, peakDay:  4, activityDays: 2,  zhr: 120, symbol: "✦"),
        MeteorShower(id: "lyrids",        name: "こと座流星群",       radiantRA: 271.4, radiantDec: 33.6,  peakMonth:  4, peakDay: 22, activityDays: 3,  zhr:  18, symbol: "✦"),
        MeteorShower(id: "eta_aquarids",  name: "みずがめ座流星群",  radiantRA: 338.0, radiantDec: -1.0,  peakMonth:  5, peakDay:  6, activityDays: 5,  zhr:  50, symbol: "✦"),
        MeteorShower(id: "perseids",      name: "ペルセウス座流星群",  radiantRA:  48.2, radiantDec: 58.1,  peakMonth:  8, peakDay: 13, activityDays: 5,  zhr: 100, symbol: "✦"),
        MeteorShower(id: "orionids",      name: "オリオン座流星群",    radiantRA:  95.0, radiantDec: 16.0,  peakMonth: 10, peakDay: 21, activityDays: 4,  zhr:  20, symbol: "✦"),
        MeteorShower(id: "leonids",       name: "しし座流星群",       radiantRA: 153.5, radiantDec: 22.0,  peakMonth: 11, peakDay: 17, activityDays: 3,  zhr:  15, symbol: "✦"),
        MeteorShower(id: "geminids",      name: "ふたご座流星群",     radiantRA: 112.3, radiantDec: 32.5,  peakMonth: 12, peakDay: 14, activityDays: 4,  zhr: 150, symbol: "✦"),
        MeteorShower(id: "ursids",        name: "こぐま座流星群",     radiantRA: 217.0, radiantDec: 76.0,  peakMonth: 12, peakDay: 22, activityDays: 3,  zhr:  10, symbol: "✦"),
    ]

    // 指定日時付近でアクティブな流星群を返す（最大3件）
    static func active(on date: Date) -> [MeteorShower] {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)

        return all.filter { shower in
            let doy    = dayOfYear(month: month, day: day)
            let peak   = dayOfYear(month: shower.peakMonth, day: shower.peakDay)
            let diff   = min(abs(doy - peak), 365 - abs(doy - peak))
            return diff <= shower.activityDays
        }.sorted { $0.zhr > $1.zhr }
    }

    // 次の流星群（極大日が最も近い）
    static func next(after date: Date) -> (shower: MeteorShower, daysUntilPeak: Int)? {
        let cal   = Calendar.current
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

    private static func dayOfYear(month: Int, day: Int) -> Int {
        let months = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        return months[min(month - 1, 11)] + day
    }
}
