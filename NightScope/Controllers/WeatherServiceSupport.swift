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

    func fetchWeather(latitude: Double, longitude: Double) async
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
    static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

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

struct MetNorwayForecastParser {
    func parse(response: MetNorwayResponse) -> [String: DayWeatherSummary] {
        var hoursByDate: [String: [HourlyWeather]] = [:]
        let calendar = Calendar(identifier: .gregorian)

        for timeseries in response.properties.timeseries {
            guard let date = MetNorwayFormatting.isoDateFormatter.date(from: timeseries.time) else {
                continue
            }

            let details = timeseries.data.instant.details
            let temperature = details.air_temperature ?? 0
            let precipitation = timeseries.data.next_1_hours?.details.precipitation_amount
                ?? timeseries.data.next_6_hours?.details?.precipitation_amount
                ?? 0
            let symbolCode = timeseries.data.next_1_hours?.summary.symbol_code
                ?? timeseries.data.next_6_hours?.summary?.symbol_code

            let hourlyWeather = HourlyWeather(
                date: date,
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

            if let key = nightDateKey(for: date, calendar: calendar) {
                hoursByDate[key, default: []].append(hourlyWeather)
            }
        }

        var summaries: [String: DayWeatherSummary] = [:]
        for (key, hours) in hoursByDate {
            guard let date = MetNorwayFormatting.dateKeyFormatter.date(from: key) else {
                continue
            }
            summaries[key] = DayWeatherSummary(
                date: date,
                nighttimeHours: hours.sorted { $0.date < $1.date }
            )
        }
        return summaries
    }

    func dateKey(_ date: Date) -> String {
        MetNorwayFormatting.dateKeyFormatter.string(from: date)
    }

    private func nightDateKey(for date: Date, calendar: Calendar) -> String? {
        var localCalendar = calendar
        localCalendar.timeZone = .current
        let hour = localCalendar.component(.hour, from: date)

        if hour >= 18 {
            return dateKey(date)
        }

        if hour <= 6,
           let previousDate = localCalendar.date(byAdding: .day, value: -1, to: date) {
            return dateKey(previousDate)
        }

        return nil
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
