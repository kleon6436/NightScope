import Foundation

enum ObservationAdvisorInputBuilder {
    /// Returns "ja" for Japanese locales, "en" for all others.
    /// To add a new language, extend this function.
    static func supportedAdvisorLanguage(for locale: Locale = .autoupdatingCurrent) -> String {
        let code = locale.language.languageCode?.identifier ?? "ja"
        return code == "ja" ? "ja" : "en"
    }

    static func build(
        nightSummary: NightSummary,
        index: StarGazingIndex,
        weather: DayWeatherSummary?,
        bortleClass: Double?,
        locationName: String,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent
    ) -> ObservationAdvisorInput {
        let language = supportedAdvisorLanguage(for: locale)
        return ObservationAdvisorInput(
            language: language,
            isUnfavorable: index.tier == .poor || index.tier == .bad,
            dateString: DateFormatters.yearMonthDayWeekdayString(
                from: nightSummary.date,
                timeZone: timeZone,
                locale: locale
            ),
            locationName: sanitize(locationName, language: language),
            tierLabel: tierLabel(for: index.tier, language: language),
            viewingWindowSummary: viewingWindowSummary(for: nightSummary, timeZone: timeZone, language: language),
            moonSummary: moonSummary(for: nightSummary, timeZone: timeZone, language: language),
            weatherSummary: weatherSummary(for: weather, language: language),
            lightPollutionSummary: lightPollutionSummary(for: bortleClass, language: language)
        )
    }

    private static func sanitize(_ locationName: String, language: String) -> String {
        let filteredScalars = locationName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filteredScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 100 {
            return cleaned.isEmpty ? defaultLocationName(language: language) : cleaned
        }
        return String(cleaned.prefix(100))
    }

    private static func defaultLocationName(language: String) -> String {
        language == "ja" ? "観測地未設定" : "Observation location not set"
    }

    private static func tierLabel(for tier: StarGazingIndex.Tier, language: String) -> String {
        guard language == "en" else {
            switch tier {
            case .excellent: return "絶好"
            case .good: return "良好"
            case .fair: return "普通"
            case .poor: return "不向き"
            case .bad: return "観測困難"
            }
        }

        switch tier {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .bad: return "Very Poor"
        }
    }

    private static func viewingWindowSummary(for summary: NightSummary, timeZone: TimeZone, language: String) -> String {
        if let window = summary.bestViewingWindow {
            if language == "ja" {
                return "\(window.start.nightTimeString(timeZone: timeZone))〜\(window.end.nightTimeString(timeZone: timeZone))（\(durationText(window.duration, language: language))）、見頃：\(window.peakTime.nightTimeString(timeZone: timeZone))ごろ"
            }
            return "\(window.start.nightTimeString(timeZone: timeZone)) to \(window.end.nightTimeString(timeZone: timeZone)) (\(durationText(window.duration, language: language))), best around \(window.peakTime.nightTimeString(timeZone: timeZone))"
        }

        if let start = summary.eveningDarkStart, let end = summary.morningDarkEnd {
            if language == "ja" {
                return "\(start.nightTimeString(timeZone: timeZone))〜\(end.nightTimeString(timeZone: timeZone))（暗夜 \(durationText(end.timeIntervalSince(start), language: language))）"
            }
            return "\(start.nightTimeString(timeZone: timeZone)) to \(end.nightTimeString(timeZone: timeZone)) (dark sky for \(durationText(end.timeIntervalSince(start), language: language)))"
        }

        return language == "ja" ? "まとまった見頃の時間帯なし" : "No meaningful viewing window tonight"
    }

    private static func moonSummary(for summary: NightSummary, timeZone: TimeZone, language: String) -> String {
        let illumination = Int(round(summary.moonIllumination * 100))
        let moonTimeText = moonTimeText(for: summary.events, timeZone: timeZone, language: language)
        let phaseName = moonPhaseName(for: summary.moonPhaseAtMidnight, language: language)
        if language == "ja" {
            return "\(phaseName)（照度\(illumination)%、\(moonTimeText)）"
        }
        return "\(phaseName) (\(illumination)% illuminated, \(moonTimeText))"
    }

    private static func moonTimeText(for events: [AstroEvent], timeZone: TimeZone, language: String) -> String {
        guard events.count > 1 else {
            if (events.first?.moonAltitude ?? -1) > 0 {
                return language == "ja" ? "月が高め" : "the Moon stays fairly high"
            }
            return language == "ja" ? "月は地平線下" : "the Moon stays below the horizon"
        }

        for pair in zip(events, events.dropFirst()) {
            if pair.0.moonAltitude > 0, pair.1.moonAltitude <= 0 {
                let time = interpolatedCrossingTime(from: pair.0, to: pair.1).nightTimeString(timeZone: timeZone)
                return language == "ja" ? "\(time)に沈む" : "sets at \(time)"
            }
        }

        for pair in zip(events, events.dropFirst()) {
            if pair.0.moonAltitude <= 0, pair.1.moonAltitude > 0 {
                let time = interpolatedCrossingTime(from: pair.0, to: pair.1).nightTimeString(timeZone: timeZone)
                return language == "ja" ? "\(time)に昇る" : "rises at \(time)"
            }
        }

        if events.allSatisfy({ $0.moonAltitude > 0 }) {
            return language == "ja" ? "夜通し月が見える" : "the Moon remains visible all night"
        }

        return language == "ja" ? "月は地平線下" : "the Moon stays below the horizon"
    }

    private static func interpolatedCrossingTime(from first: AstroEvent, to second: AstroEvent) -> Date {
        let delta = second.moonAltitude - first.moonAltitude
        guard delta != 0 else { return second.date }
        let ratio = (0 - first.moonAltitude) / delta
        let interval = second.date.timeIntervalSince(first.date)
        return first.date.addingTimeInterval(interval * ratio)
    }

    private static func weatherSummary(for weather: DayWeatherSummary?, language: String) -> String {
        guard let weather else {
            return language == "ja" ? "天気データなし" : "No weather data"
        }

        let windMetersPerSecond = Int(round(weather.avgWindSpeed / 3.6))
        let cloudCover = Int(round(weather.avgCloudCover))
        let weatherLabel = weatherLabel(for: weather.representativeWeatherCode, language: language)
        let transparency = transparencyLabel(for: weather, language: language)
        if language == "ja" {
            return "\(weatherLabel)、雲量\(cloudCover)%、\(transparency)、風速\(windMetersPerSecond)m/s"
        }
        return "\(weatherLabel), \(cloudCover)% clouds, \(transparency), wind \(windMetersPerSecond) m/s"
    }

    private static func transparencyLabel(for weather: DayWeatherSummary, language: String) -> String {
        if let visibility = weather.avgVisibilityMeters {
            switch visibility {
            case 20_000...: return language == "ja" ? "透明度良好" : "good transparency"
            case 10_000...: return language == "ja" ? "透明度普通" : "average transparency"
            default: return language == "ja" ? "透明度低め" : "reduced transparency"
            }
        }

        switch weather.avgDewpointSpread {
        case 10...: return language == "ja" ? "透明度良好" : "good transparency"
        case 5...: return language == "ja" ? "透明度普通" : "average transparency"
        default: return language == "ja" ? "透明度低め" : "reduced transparency"
        }
    }

    private static func lightPollutionSummary(for bortleClass: Double?, language: String) -> String {
        guard let bortleClass else {
            return language == "ja" ? "光害データなし" : "No light pollution data"
        }

        let rounded = max(1, min(9, Int(bortleClass.rounded())))
        let description: String
        if language == "ja" {
            switch rounded {
            case 1...2: description = "非常に暗い空（天の川がはっきり見える）"
            case 3: description = "田舎の暗い空（天の川が明瞭に見える）"
            case 4: description = "郊外の空（天の川は肉眼でうっすら見える）"
            case 5: description = "郊外〜住宅地の空（明るい星団が中心）"
            case 6: description = "住宅地の空（明るい星座中心）"
            case 7...8: description = "都市近郊の空（明るい星や主要星座が中心）"
            default: description = "都市中心部の空（最も明るい星が中心）"
            }
        } else {
            switch rounded {
            case 1...2: description = "Very dark sky (Milky Way clearly visible)"
            case 3: description = "Rural dark sky (Milky Way is prominent)"
            case 4: description = "Suburban sky (Milky Way faintly visible to the naked eye)"
            case 5: description = "Suburban-residential sky (bright clusters stand out)"
            case 6: description = "Residential sky (bright constellations dominate)"
            case 7...8: description = "Bright urban-edge sky (bright stars and major constellations dominate)"
            default: description = "City-center sky (only the brightest stars stand out)"
            }
        }
        return description
    }

    private static func durationText(_ duration: TimeInterval, language: String) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if language == "ja" {
            if hours == 0 {
                return "\(minutes)分"
            }
            if minutes == 0 {
                return "\(hours)時間"
            }
            return "\(hours)時間\(minutes)分"
        }

        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    private static func moonPhaseName(for phase: Double, language: String) -> String {
        if language == "ja" {
            switch phase {
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

        switch phase {
        case 0..<0.04, 0.96...1: return "New Moon"
        case 0.04..<0.12: return "Young Crescent"
        case 0.12..<0.22: return "Waxing Crescent"
        case 0.22..<0.30: return "First Quarter"
        case 0.30..<0.46: return "Waxing Gibbous"
        case 0.46..<0.54: return "Full Moon"
        case 0.54..<0.70: return "Waning Gibbous"
        case 0.70..<0.80: return "Last Quarter"
        case 0.80..<0.96: return "Waning Crescent"
        default: return ""
        }
    }

    private static func weatherLabel(for code: Int, language: String) -> String {
        if language == "ja" {
            switch code {
            case 0: return "快晴"
            case 1: return "晴れ"
            case 2: return "晴れ時々曇り"
            case 3: return "曇り"
            case 45, 48: return "霧"
            case 51, 53, 55: return "霧雨"
            case 61: return "小雨"
            case 63: return "雨"
            case 65: return "大雨"
            case 71: return "小雪"
            case 73: return "雪"
            case 75: return "大雪"
            case 77: return "細雪"
            case 80, 81, 82: return "にわか雨"
            case 85, 86: return "にわか雪"
            case 95: return "雷雨"
            case 96, 99: return "雷雨（ひょう）"
            default: return "不明"
            }
        }

        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }

}
