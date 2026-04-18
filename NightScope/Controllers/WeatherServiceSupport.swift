import Foundation
import CoreLocation
import Combine

enum WeatherServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case invalidData
    case decodingError(underlying: Error)
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URLの生成に失敗しました。"
        case .invalidResponse(let statusCode):
            return "天気APIのステータスコードが不正です: \(statusCode)"
        case .invalidData:
            return "天気APIの取得データが不正です。"
        case .decodingError(let underlying):
            return "天気データの解析に失敗しました: \(underlying.localizedDescription)"
        case .networkError(let underlying):
            return "ネットワークエラーが発生しました: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
protocol WeatherProviding: AnyObject, ObservableObject {
    var weatherByDate: [String: DayWeatherSummary] { get }
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func fetchWeather(latitude: Double, longitude: Double, timeZone: TimeZone) async
    func summary(for date: Date) -> DayWeatherSummary?
}

struct MetNorwayResponse: Decodable {
    struct Properties: Decodable {
        struct Timeseries: Decodable {
            let time: String
            struct Data: Decodable {
                struct Instant: Decodable {
                    struct Details: Decodable {
                        let air_temperature: Double?
                        let cloud_area_fraction: Double?
                        let cloud_area_fraction_low: Double?
                        let cloud_area_fraction_medium: Double?
                        let cloud_area_fraction_high: Double?
                        let wind_speed: Double?
                        let wind_speed_of_gust: Double?
                        let relative_humidity: Double?
                        let dew_point_temperature: Double?
                    }
                    let details: Details
                }
                struct Next1Hours: Decodable {
                    struct Summary: Decodable {
                        let symbol_code: String?
                    }
                    struct Details: Decodable {
                        let precipitation_amount: Double?
                    }
                    let summary: Summary
                    let details: Details
                }
                struct Next6Hours: Decodable {
                    struct Summary: Decodable {
                        let symbol_code: String?
                    }
                    struct Details: Decodable {
                        let precipitation_amount: Double?
                    }
                    let summary: Summary?
                    let details: Details?
                }
                let instant: Instant
                let next_1_hours: Next1Hours?
                let next_6_hours: Next6Hours?
            }
            let data: Data
        }
        let timeseries: [Timeseries]
    }
    let properties: Properties
}

enum MetNorwayFormatting {
    static func dateKeyFormatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }

    nonisolated(unsafe) static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()
}

struct MetNorwayRequestFactory {
    func makeRequest(latitude: Double, longitude: Double, lastModifiedDate: Date?) throws -> URLRequest {
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        let urlString = "https://api.met.no/weatherapi/locationforecast/2.0/complete"
            + "?lat=\(lat)&lon=\(lon)"

        guard let url = URL(string: urlString) else {
            throw WeatherServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "NightScope/1.0 github.com/nightscope/app",
            forHTTPHeaderField: "User-Agent"
        )

        if let lastModifiedDate {
            request.setValue(
                MetNorwayFormatting.httpDateFormatter.string(from: lastModifiedDate),
                forHTTPHeaderField: "If-Modified-Since"
            )
        }

        return request
    }
}

struct MetNorwayForecastParser: Sendable {
    func parse(
        response: MetNorwayResponse,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> [String: DayWeatherSummary] {
        let hours = response.properties.timeseries.flatMap { hourlyWeatherEntries(from: $0) }
        let hoursByDate = groupNightHours(hours, location: location, timeZone: timeZone)
        let formatter = MetNorwayFormatting.dateKeyFormatter(timeZone: timeZone)

        var summaries: [String: DayWeatherSummary] = [:]
        for (key, hours) in hoursByDate {
            guard let date = formatter.date(from: key) else {
                continue
            }
            summaries[key] = DayWeatherSummary(
                date: date,
                nighttimeHours: hours.sorted { $0.date < $1.date }
            )
        }
        return summaries
    }

    func dateKey(_ date: Date, timeZone: TimeZone) -> String {
        MetNorwayFormatting.dateKeyFormatter(timeZone: timeZone).string(from: date)
    }

    private func hourlyWeatherEntries(from timeseries: MetNorwayResponse.Properties.Timeseries) -> [HourlyWeather] {
        guard let date = MetNorwayFormatting.isoDateFormatter.date(from: timeseries.time) else {
            return []
        }

        let details = timeseries.data.instant.details
        let forecastStepHours = forecastStepHours(for: timeseries)
        let temperature = details.air_temperature ?? 0
        let precipitation = timeseries.data.next_1_hours?.details.precipitation_amount
            ?? timeseries.data.next_6_hours?.details?.precipitation_amount
            ?? 0
        let symbolCode = timeseries.data.next_1_hours?.summary.symbol_code
            ?? timeseries.data.next_6_hours?.summary?.symbol_code

        // MET Norway は先の日付ほど `next_6_hours` に切り替わる。
        // 夜間判定と星空指数は時間単位の被覆率を前提にするため、6時間ブロックは各1時間へ展開する。
        return (0..<forecastStepHours).map { offset in
            HourlyWeather(
                date: date.addingTimeInterval(Double(offset) * 3600),
                temperatureCelsius: temperature,
                cloudCoverPercent: details.cloud_area_fraction ?? 0,
                precipitationMM: precipitation,
                windSpeedKmh: (details.wind_speed ?? 0) * 3.6,
                humidityPercent: details.relative_humidity ?? 0,
                dewpointCelsius: details.dew_point_temperature ?? temperature,
                weatherCode: Self.symbolCodeToWMO(symbolCode),
                visibilityMeters: nil,
                windGustsKmh: details.wind_speed_of_gust.map { $0 * 3.6 },
                cloudCoverLowPercent: details.cloud_area_fraction_low,
                cloudCoverMidPercent: details.cloud_area_fraction_medium,
                cloudCoverHighPercent: details.cloud_area_fraction_high,
                windSpeedKmh500hpa: nil
            )
        }
    }

    private func forecastStepHours(for timeseries: MetNorwayResponse.Properties.Timeseries) -> Int {
        if timeseries.data.next_1_hours != nil {
            return 1
        }
        if timeseries.data.next_6_hours != nil {
            return 6
        }
        return 1
    }

    private func groupNightHours(
        _ hours: [HourlyWeather],
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> [String: [HourlyWeather]] {
        guard let earliestHour = hours.min(by: { $0.date < $1.date }),
              let latestHour = hours.max(by: { $0.date < $1.date }) else {
            return [:]
        }

        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let formatter = MetNorwayFormatting.dateKeyFormatter(timeZone: timeZone)
        let startDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: earliestHour.date))
            ?? calendar.startOfDay(for: earliestHour.date)
        let endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latestHour.date))
            ?? calendar.startOfDay(for: latestHour.date)

        var intervals: [(key: String, interval: DateInterval)] = []
        var currentDay = startDay
        while currentDay <= endDay {
            if let interval = MilkyWayCalculator.nightInterval(
                for: currentDay,
                location: location,
                timeZone: timeZone
            ) {
                intervals.append((formatter.string(from: currentDay), interval))
            }
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? endDay.addingTimeInterval(1)
        }

        var result: [String: [HourlyWeather]] = [:]
        for hour in hours.sorted(by: { $0.date < $1.date }) {
            if let matchingInterval = intervals.first(where: { $0.interval.contains(hour.date) }) {
                result[matchingInterval.key, default: []].append(hour)
            }
        }
        return result
    }

    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        guard let code = symbolCode else { return 0 }
        var base = code
        for suffix in ["_day", "_night", "_polartwilight"] {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }

        switch base {
        case "clearsky": return 0
        case "fair": return 1
        case "partlycloudy": return 2
        case "cloudy": return 3
        case "fog": return 45
        case "lightrain": return 61
        case "rain": return 63
        case "heavyrain": return 65
        case "lightsleet": return 68
        case "sleet": return 69
        case "lightsnow": return 71
        case "snow": return 73
        case "heavysnow": return 75
        case "lightrainshowers": return 80
        case "rainshowers": return 81
        case "heavyrainshowers": return 82
        case "lightsnowshowers": return 85
        case "snowshowers", "heavysnowshowers": return 86
        case let value where value.contains("thunder"): return 95
        default: return 3
        }
    }
}
