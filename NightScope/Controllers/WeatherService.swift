import Foundation
import Combine
import CoreLocation

@MainActor
final class WeatherService: ObservableObject, WeatherProviding {
    private struct LocationContext {
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone

        var locationKey: String {
            WeatherService.locationKey(
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
            )
        }
    }

    struct FetchResult {
        let weatherByDate: [String: DayWeatherSummary]
        let errorMessage: String?
        let lastModifiedDate: Date?
        let locationKey: String
        let timeZoneIdentifier: String
    }

    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { $weatherByDate }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?
    private let urlSession: URLSession
    private let requestFactory: MetNorwayRequestFactory
    private let forecastParser: MetNorwayForecastParser
    // キャッシュとして保持する最大場所数
    private let maxCachedLocations = 10
    private var lastModifiedDatesByLocation: [String: Date] = [:]
    private var weatherByDateByLocation: [String: [String: DayWeatherSummary]] = [:]
    private var activeLocationKey: String?
    private var activeTimeZoneIdentifier = TimeZone.current.identifier

    init(
        urlSession: URLSession = .shared,
        requestFactory: MetNorwayRequestFactory = MetNorwayRequestFactory(),
        forecastParser: MetNorwayForecastParser = MetNorwayForecastParser()
    ) {
        self.urlSession = urlSession
        self.requestFactory = requestFactory
        self.forecastParser = forecastParser
    }

    func fetchWeather(latitude: Double, longitude: Double, timeZone: TimeZone) async {
        let context = LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        let fallbackWeatherByDate = cachedWeatherByDate(for: context.locationKey)
        if activeLocationKey != context.locationKey {
            prepareForLocationChange(context)
        }
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentTask = Task {
            let result = await loadWeather(
                context: context,
                fallbackWeatherByDate: fallbackWeatherByDate
            )
            guard !Task.isCancelled else { return }
            applyFetchResult(result)
        }
        await currentTask?.value
    }

    func fetchWeatherSnapshot(latitude: Double, longitude: Double, timeZone: TimeZone) async -> FetchResult {
        let context = LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        return await loadWeather(
            context: context,
            fallbackWeatherByDate: weatherByDateByLocation[context.locationKey] ?? [:]
        )
    }

    func applyFetchResult(_ result: FetchResult) {
        activeLocationKey = result.locationKey
        activeTimeZoneIdentifier = result.timeZoneIdentifier
        weatherByDateByLocation[result.locationKey] = result.weatherByDate
        weatherByDate = result.weatherByDate
        errorMessage = result.errorMessage
        if let lastModifiedDate = result.lastModifiedDate {
            lastModifiedDatesByLocation[result.locationKey] = lastModifiedDate
        }
        // キャッシュ上限を超えた場合、アクティブ以外の古いエントリを削除する
        evictCacheIfNeeded()
        isLoading = false
    }

    private func evictCacheIfNeeded() {
        guard weatherByDateByLocation.count > maxCachedLocations else { return }
        let keysToEvict = weatherByDateByLocation.keys.filter { $0 != activeLocationKey }
        for key in keysToEvict.prefix(weatherByDateByLocation.count - maxCachedLocations) {
            weatherByDateByLocation.removeValue(forKey: key)
            lastModifiedDatesByLocation.removeValue(forKey: key)
        }
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        summary(for: date, from: weatherByDate, timeZone: activeTimeZone)
    }

    func summary(
        for date: Date,
        from weatherByDate: [String: DayWeatherSummary],
        timeZone: TimeZone
    ) -> DayWeatherSummary? {
        weatherByDate[forecastParser.dateKey(date, timeZone: timeZone)]
    }

    func isForecastOutOfRange(
        for date: Date,
        in weatherByDate: [String: DayWeatherSummary],
        timeZone: TimeZone
    ) -> Bool {
        guard summary(for: date, from: weatherByDate, timeZone: timeZone) == nil,
              let latestForecastDate = weatherByDate.values.map(\.date).max() else {
            return false
        }

        let selectedDay = ObservationTimeZone.startOfDay(for: date, timeZone: timeZone)
        let latestForecastDay = ObservationTimeZone.startOfDay(for: latestForecastDate, timeZone: timeZone)
        return selectedDay > latestForecastDay
    }

    func prepareForLocationChange(latitude: Double, longitude: Double, timeZone: TimeZone) {
        currentTask?.cancel()
        prepareForLocationChange(
            LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        )
    }

    private func prepareForLocationChange(_ context: LocationContext) {
        activeLocationKey = context.locationKey
        activeTimeZoneIdentifier = context.timeZone.identifier
        weatherByDate = weatherByDateByLocation[activeLocationKey ?? ""] ?? [:]
        errorMessage = nil
        isLoading = false
    }

    private func loadWeather(
        context: LocationContext,
        fallbackWeatherByDate: [String: DayWeatherSummary]
    ) async -> FetchResult {
        do {
            let request = try requestFactory.makeRequest(
                latitude: context.latitude,
                longitude: context.longitude,
                lastModifiedDate: lastModifiedDatesByLocation[context.locationKey]
            )
            let (data, response) = try await urlSession.data(for: request)
            if Task.isCancelled {
                return FetchResult(
                    weatherByDate: fallbackWeatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDatesByLocation[context.locationKey],
                    locationKey: context.locationKey,
                    timeZoneIdentifier: context.timeZone.identifier
                )
            }

            guard let http = response as? HTTPURLResponse else {
                throw WeatherServiceError.invalidResponse(statusCode: -1)
            }

            if http.statusCode == 304 {
                return FetchResult(
                    weatherByDate: fallbackWeatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDatesByLocation[context.locationKey],
                    locationKey: context.locationKey,
                    timeZoneIdentifier: context.timeZone.identifier
                )
            }

            guard http.statusCode == 200 else {
                throw WeatherServiceError.invalidResponse(statusCode: http.statusCode)
            }

            let lastModifiedDate: Date?
            if let lastModifiedHeader = http.value(forHTTPHeaderField: "Last-Modified") {
                lastModifiedDate = MetNorwayFormatting.httpDateFormatter.date(from: lastModifiedHeader)
            } else {
                lastModifiedDate = nil
            }

            do {
                let weatherByDate = try await Self.decodeForecast(
                    data: data,
                    forecastParser: forecastParser,
                    location: CLLocationCoordinate2D(
                        latitude: context.latitude,
                        longitude: context.longitude
                    ),
                    timeZone: context.timeZone
                )
                return FetchResult(
                    weatherByDate: weatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDate,
                    locationKey: context.locationKey,
                    timeZoneIdentifier: context.timeZone.identifier
                )
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }
        } catch {
            let serviceError = (error as? WeatherServiceError) ?? .networkError(underlying: error)
            return FetchResult(
                weatherByDate: fallbackWeatherByDate,
                errorMessage: serviceError.localizedDescription,
                lastModifiedDate: lastModifiedDatesByLocation[context.locationKey],
                locationKey: context.locationKey,
                timeZoneIdentifier: context.timeZone.identifier
            )
        }
    }

    func parse(
        response: MetNorwayResponse,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone = .current
    ) -> [String: DayWeatherSummary] {
        forecastParser.parse(response: response, location: location, timeZone: timeZone)
    }

    func dateKey(_ date: Date) -> String {
        forecastParser.dateKey(date, timeZone: activeTimeZone)
    }

    func dateKey(_ date: Date, timeZone: TimeZone) -> String {
        forecastParser.dateKey(date, timeZone: timeZone)
    }

    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        MetNorwayForecastParser.symbolCodeToWMO(symbolCode)
    }

    private var activeTimeZone: TimeZone {
        TimeZone(identifier: activeTimeZoneIdentifier) ?? .current
    }

    private nonisolated static func locationKey(latitude: Double, longitude: Double, timeZone: TimeZone) -> String {
        // requestFactory と同じ小数点4桁（約11m）で揃えて、
        // 検索で近接した別地点へ移動したときも古い天気キャッシュを再利用しない。
        // printf の暗黙丸めではなく明示的 rounded() を使うことで
        // 境界値付近の浮動小数点ブレによるキャッシュ不一致を防ぐ。
        let lat = (latitude  * 10_000).rounded() / 10_000
        let lon = (longitude * 10_000).rounded() / 10_000
        return String(format: "%.4f,%.4f|%@", lat, lon, timeZone.identifier)
    }

    private func cachedWeatherByDate(for locationKey: String) -> [String: DayWeatherSummary] {
        if let cached = weatherByDateByLocation[locationKey] {
            return cached
        }
        if activeLocationKey == locationKey {
            return weatherByDate
        }
        return [:]
    }

    private nonisolated static func decodeForecast(
        data: Data,
        forecastParser: MetNorwayForecastParser,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) async throws -> [String: DayWeatherSummary] {
        try await Task.detached(priority: .userInitiated) {
            let apiResponse = try JSONDecoder().decode(MetNorwayResponse.self, from: data)
            return forecastParser.parse(response: apiResponse, location: location, timeZone: timeZone)
        }.value
    }
}
