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

// MARK: - API Response

struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]
        let cloudcover: [Double?]
        let precipitation: [Double?]
        let windspeed_10m: [Double?]
        let relative_humidity_2m: [Double?]
        let dewpoint_2m: [Double?]
        let weathercode: [Int?]
        // 新規追加フィールド（配列自体もオプショナル — 後方互換性のため）
        let visibility: [Double?]?
        let windgusts_10m: [Double?]?
        let cloud_cover_low: [Double?]?
        let cloud_cover_mid: [Double?]?
        let cloud_cover_high: [Double?]?
        let windspeed_500hpa: [Double?]?

        // API キー名（wind_gusts_10m / windspeed_500hPa）と Swift プロパティ名のマッピング
        enum CodingKeys: String, CodingKey {
            case time
            case temperature_2m
            case cloudcover
            case precipitation
            case windspeed_10m
            case relative_humidity_2m
            case dewpoint_2m
            case weathercode
            case visibility
            case windgusts_10m = "wind_gusts_10m"
            case cloud_cover_low
            case cloud_cover_mid
            case cloud_cover_high
            case windspeed_500hpa = "windspeed_500hPa"
        }
    }
    let hourly: Hourly
    let timezone: String
}

// MARK: - Service

@MainActor
final class WeatherService: ObservableObject, WeatherProviding {
    // "yyyy-MM-dd" キー生成・復元に使う共有フォーマッタ
    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let isoTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { $weatherByDate }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    func fetchWeather(latitude: Double, longitude: Double) async {
        currentTask?.cancel()
        currentTask = Task {
            await performFetch(latitude: latitude, longitude: longitude)
        }
        await currentTask?.value
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherByDate[dateKey(date)]
    }

    // MARK: - Private

    private func performFetch(latitude: Double, longitude: Double) async {
        isLoading = true
        errorMessage = nil

        // Use forecast API for upcoming days
        let urlString = "https://api.open-meteo.com/v1/forecast" +
            "?latitude=\(latitude)" +
            "&longitude=\(longitude)" +
            "&hourly=temperature_2m,cloudcover,precipitation,windspeed_10m,relative_humidity_2m,dewpoint_2m,weathercode,visibility,wind_gusts_10m,cloud_cover_low,cloud_cover_mid,cloud_cover_high,windspeed_500hPa" +
            "&forecast_days=14" +
            "&past_days=2" +
            "&timezone=auto"

        guard let url = URL(string: urlString) else {
            errorMessage = "URLの生成に失敗しました"
            isLoading = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if Task.isCancelled { return }

            guard let http = response as? HTTPURLResponse else {
                throw WeatherServiceError.invalidResponse(statusCode: -1)
            }
            guard http.statusCode == 200 else {
                throw WeatherServiceError.invalidResponse(statusCode: http.statusCode)
            }

            let apiResponse: OpenMeteoResponse
            do {
                apiResponse = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }

            let summaries = parse(response: apiResponse)
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

    func parse(response: OpenMeteoResponse) -> [String: DayWeatherSummary] {
        let hourly = response.hourly

        // Parse timestamps as local time (API returns local time when timezone=auto)
        let formatter = WeatherService.isoTimestampFormatter
        if let tz = TimeZone(identifier: response.timezone) {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = .current
        }

        var hoursByDate: [String: [HourlyWeather]] = [:]

        for i in 0..<hourly.time.count {
            guard let date = formatter.date(from: hourly.time[i]) else { continue }

            let temp = hourly.temperature_2m[i] ?? 0
            let cloud = hourly.cloudcover[i] ?? 0
            let precip = hourly.precipitation[i] ?? 0
            let wind = hourly.windspeed_10m[i] ?? 0
            let humidity = hourly.relative_humidity_2m[i] ?? 0
            let dewpoint = hourly.dewpoint_2m[i] ?? temp
            let wcode = hourly.weathercode[i] ?? 0
            let visibility = hourly.visibility?[i] ?? nil
            let windGusts = hourly.windgusts_10m?[i] ?? nil
            let cloudLow = hourly.cloud_cover_low?[i] ?? nil
            let cloudMid = hourly.cloud_cover_mid?[i] ?? nil
            let cloudHigh = hourly.cloud_cover_high?[i] ?? nil
            let wind500hpa = hourly.windspeed_500hpa?[i] ?? nil

            let hw = HourlyWeather(
                date: date,
                temperatureCelsius: temp,
                cloudCoverPercent: cloud,
                precipitationMM: precip,
                windSpeedKmh: wind,
                humidityPercent: humidity,
                dewpointCelsius: dewpoint,
                weatherCode: wcode,
                visibilityMeters: visibility,
                windGustsKmh: windGusts,
                cloudCoverLowPercent: cloudLow,
                cloudCoverMidPercent: cloudMid,
                cloudCoverHighPercent: cloudHigh,
                windSpeedKmh500hpa: wind500hpa
            )

            let cal = Calendar(identifier: .gregorian)
            if let key = nightDateKey(for: date, calendar: cal) {
                hoursByDate[key, default: []].append(hw)
            }
        }

        var result: [String: DayWeatherSummary] = [:]
        for (key, hours) in hoursByDate {
            if let date = WeatherService.dateKeyFormatter.date(from: key) {
                result[key] = DayWeatherSummary(date: date, nighttimeHours: hours.sorted { $0.date < $1.date })
            }
        }
        return result
    }

    func dateKey(_ date: Date) -> String {
        WeatherService.dateKeyFormatter.string(from: date)
    }

    /// 夜間観測の集約キー（18:00-23:59 は当日、00:00-06:59 は前日）
    /// 07:00-17:59 は夜間集計対象外として nil を返す
    private func nightDateKey(for date: Date, calendar: Calendar) -> String? {
        let hour = calendar.component(.hour, from: date)

        if hour >= 18 {
            return dateKey(date)
        }

        if hour <= 6,
           let previousDate = calendar.date(byAdding: .day, value: -1, to: date) {
            return dateKey(previousDate)
        }

        return nil
    }
}
