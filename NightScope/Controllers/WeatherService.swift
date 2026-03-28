import Foundation

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
    }
    let hourly: Hourly
    let timezone: String
}

// MARK: - Service

@MainActor
final class WeatherService: ObservableObject {
    // "yyyy-MM-dd" キー生成・復元に使う共有フォーマッタ
    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
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
            "&hourly=temperature_2m,cloudcover,precipitation,windspeed_10m,relative_humidity_2m,dewpoint_2m,weathercode" +
            "&forecast_days=14" +
            "&past_days=2" +
            "&timezone=auto"

        guard let url = URL(string: urlString) else {
            errorMessage = "URLの生成に失敗しました"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let summaries = parse(response: response)
            weatherByDate = summaries
        } catch {
            if !Task.isCancelled {
                errorMessage = "天気データの取得に失敗しました"
            }
        }

        isLoading = false
    }

    func parse(response: OpenMeteoResponse) -> [String: DayWeatherSummary] {
        let hourly = response.hourly

        // Parse timestamps as local time (API returns local time when timezone=auto)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try to use the timezone from the response
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

            let hw = HourlyWeather(
                date: date,
                temperatureCelsius: temp,
                cloudCoverPercent: cloud,
                precipitationMM: precip,
                windSpeedKmh: wind,
                humidityPercent: humidity,
                dewpointCelsius: dewpoint,
                weatherCode: wcode
            )

            // Nighttime: hours 20-23 belong to "today", hours 0-4 belong to "yesterday" (previous night)
            let cal = Calendar(identifier: .gregorian)
            let hour = cal.component(.hour, from: date)

            if hour >= 20 {
                // Evening: key = this date
                let key = dateKey(date)
                hoursByDate[key, default: []].append(hw)
            } else if hour <= 4 {
                // Early morning: key = previous date (same night)
                let prevDate = cal.date(byAdding: .day, value: -1, to: date)!
                let key = dateKey(prevDate)
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
}
