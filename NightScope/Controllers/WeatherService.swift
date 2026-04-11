import Foundation

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

// MARK: - MET Norway Locationforecast 2.0 API Response

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
    // "yyyy-MM-dd" キー生成・復元に使う共有フォーマッタ（ローカル時刻）
    static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    // MET Norway タイムスタンプ（UTC ISO8601 "Z" 形式）パーサー
    nonisolated(unsafe) static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // HTTP-date フォーマッタ（If-Modified-Since / Last-Modified）
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
        case "clearsky":                          return 0
        case "fair":                              return 1
        case "partlycloudy":                      return 2
        case "cloudy":                            return 3
        case "fog":                               return 45
        case "lightrain":                         return 61
        case "rain":                              return 63
        case "heavyrain":                         return 65
        case "lightsleet":                        return 68
        case "sleet":                             return 69
        case "lightsnow":                         return 71
        case "snow":                              return 73
        case "heavysnow":                         return 75
        case "lightrainshowers":                  return 80
        case "rainshowers":                       return 81
        case "heavyrainshowers":                  return 82
        case "lightsnowshowers":                  return 85
        case "snowshowers", "heavysnowshowers":   return 86
        case let value where value.contains("thunder"): return 95
        default:                                  return 3
        }
    }
}

// MARK: - Service

@MainActor
final class WeatherService: ObservableObject, WeatherProviding {
    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { $weatherByDate }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?
    private let urlSession: URLSession
    private let requestFactory: MetNorwayRequestFactory
    private let forecastParser: MetNorwayForecastParser
    /// MET Norway の Last-Modified を保持（If-Modified-Since キャッシュ制御用）
    private var lastModifiedDate: Date?

    init(
        urlSession: URLSession = .shared,
        requestFactory: MetNorwayRequestFactory = MetNorwayRequestFactory(),
        forecastParser: MetNorwayForecastParser = MetNorwayForecastParser()
    ) {
        self.urlSession = urlSession
        self.requestFactory = requestFactory
        self.forecastParser = forecastParser
    }

    func fetchWeather(latitude: Double, longitude: Double) async {
        currentTask?.cancel()
        currentTask = Task {
            await performFetch(latitude: latitude, longitude: longitude)
        }
        await currentTask?.value
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherByDate[forecastParser.dateKey(date)]
    }

    // MARK: - Private

    private func performFetch(latitude: Double, longitude: Double) async {
        isLoading = true
        errorMessage = nil

        do {
            let request = try requestFactory.makeRequest(
                latitude: latitude,
                longitude: longitude,
                lastModifiedDate: lastModifiedDate
            )
            let (data, response) = try await urlSession.data(for: request)
            if Task.isCancelled { return }

            guard let http = response as? HTTPURLResponse else {
                throw WeatherServiceError.invalidResponse(statusCode: -1)
            }

            // 304 Not Modified: キャッシュデータをそのまま使う
            if http.statusCode == 304 {
                isLoading = false
                return
            }

            guard http.statusCode == 200 else {
                throw WeatherServiceError.invalidResponse(statusCode: http.statusCode)
            }

            // Last-Modified ヘッダーを保存
            if let lastModifiedHeader = http.value(forHTTPHeaderField: "Last-Modified") {
                lastModifiedDate = MetNorwayFormatting.httpDateFormatter.date(from: lastModifiedHeader)
            }

            let apiResponse: MetNorwayResponse
            do {
                apiResponse = try JSONDecoder().decode(MetNorwayResponse.self, from: data)
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }

            let summaries = forecastParser.parse(response: apiResponse)
            weatherByDate = summaries
        } catch {
            if !Task.isCancelled {
                let serviceError = (error as? WeatherServiceError) ?? .networkError(underlying: error)
                switch serviceError {
                case .invalidURL:
                    errorMessage = serviceError.localizedDescription
                case .invalidResponse(let code):
                    errorMessage = "天気APIのステータスコードが不正です: \(code)"
                case .invalidData:
                    errorMessage = serviceError.localizedDescription
                case .decodingError:
                    errorMessage = serviceError.localizedDescription
                case .networkError:
                    errorMessage = serviceError.localizedDescription
                }
            }
        }

        isLoading = false
    }

    func parse(response: MetNorwayResponse) -> [String: DayWeatherSummary] {
        forecastParser.parse(response: response)
    }

    func dateKey(_ date: Date) -> String {
        forecastParser.dateKey(date)
    }

    // MARK: - MET Norway symbol_code → WMO 互換コード

    /// MET Norway の symbol_code を WMO 互換の天気コード（Int）に変換する。
    /// _day / _night / _polartwilight サフィックスを除いてマッチングする。
    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        MetNorwayForecastParser.symbolCodeToWMO(symbolCode)
    }
}
