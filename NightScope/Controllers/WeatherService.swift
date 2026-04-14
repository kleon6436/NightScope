import Foundation
import Combine
import CoreLocation

@MainActor
final class WeatherService: ObservableObject, WeatherProviding {
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
    private var lastModifiedDatesByLocation: [String: Date] = [:]
    private var weatherByDateByLocation: [String: [String: DayWeatherSummary]] = [:]
    private var activeLocationKey: String?
    private var activeTimeZoneIdentifier = ObservationTimeZone.current.identifier

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
        let locationKey = Self.locationKey(latitude: latitude, longitude: longitude, timeZone: timeZone)
        let fallbackWeatherByDate = cachedWeatherByDate(for: locationKey)
        if activeLocationKey != locationKey {
            prepareForLocationChange(latitude: latitude, longitude: longitude, timeZone: timeZone)
        }
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentTask = Task {
            let result = await loadWeather(
                latitude: latitude,
                longitude: longitude,
                locationKey: locationKey,
                fallbackWeatherByDate: fallbackWeatherByDate,
                timeZone: timeZone
            )
            guard !Task.isCancelled else { return }
            applyFetchResult(result)
        }
        await currentTask?.value
    }

    func fetchWeatherSnapshot(latitude: Double, longitude: Double, timeZone: TimeZone) async -> FetchResult {
        let locationKey = Self.locationKey(latitude: latitude, longitude: longitude, timeZone: timeZone)
        return await loadWeather(
            latitude: latitude,
            longitude: longitude,
            locationKey: locationKey,
            fallbackWeatherByDate: weatherByDateByLocation[locationKey] ?? [:],
            timeZone: timeZone
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
        isLoading = false
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherByDate[forecastParser.dateKey(date, timeZone: activeTimeZone)]
    }

    func prepareForLocationChange(latitude: Double, longitude: Double, timeZone: TimeZone) {
        currentTask?.cancel()
        activeLocationKey = Self.locationKey(latitude: latitude, longitude: longitude, timeZone: timeZone)
        activeTimeZoneIdentifier = timeZone.identifier
        weatherByDate = weatherByDateByLocation[activeLocationKey ?? ""] ?? [:]
        errorMessage = nil
        isLoading = false
    }

    private func loadWeather(
        latitude: Double,
        longitude: Double,
        locationKey: String,
        fallbackWeatherByDate: [String: DayWeatherSummary],
        timeZone: TimeZone
    ) async -> FetchResult {
        do {
            let request = try requestFactory.makeRequest(
                latitude: latitude,
                longitude: longitude,
                lastModifiedDate: lastModifiedDatesByLocation[locationKey]
            )
            let (data, response) = try await urlSession.data(for: request)
            if Task.isCancelled {
                return FetchResult(
                    weatherByDate: fallbackWeatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDatesByLocation[locationKey],
                    locationKey: locationKey,
                    timeZoneIdentifier: timeZone.identifier
                )
            }

            guard let http = response as? HTTPURLResponse else {
                throw WeatherServiceError.invalidResponse(statusCode: -1)
            }

            if http.statusCode == 304 {
                return FetchResult(
                    weatherByDate: fallbackWeatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDatesByLocation[locationKey],
                    locationKey: locationKey,
                    timeZoneIdentifier: timeZone.identifier
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
                    location: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    timeZone: timeZone
                )
                return FetchResult(
                    weatherByDate: weatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: lastModifiedDate,
                    locationKey: locationKey,
                    timeZoneIdentifier: timeZone.identifier
                )
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }
        } catch {
            let serviceError = (error as? WeatherServiceError) ?? .networkError(underlying: error)
            return FetchResult(
                weatherByDate: fallbackWeatherByDate,
                errorMessage: serviceError.localizedDescription,
                lastModifiedDate: lastModifiedDatesByLocation[locationKey],
                locationKey: locationKey,
                timeZoneIdentifier: timeZone.identifier
            )
        }
    }

    func parse(
        response: MetNorwayResponse,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone = ObservationTimeZone.current
    ) -> [String: DayWeatherSummary] {
        forecastParser.parse(response: response, location: location, timeZone: timeZone)
    }

    func dateKey(_ date: Date) -> String {
        forecastParser.dateKey(date, timeZone: activeTimeZone)
    }

    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        MetNorwayForecastParser.symbolCodeToWMO(symbolCode)
    }

    private var activeTimeZone: TimeZone {
        TimeZone(identifier: activeTimeZoneIdentifier) ?? .current
    }

    private static func locationKey(latitude: Double, longitude: Double, timeZone: TimeZone) -> String {
        String(format: "%.4f,%.4f|%@", latitude, longitude, timeZone.identifier)
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
