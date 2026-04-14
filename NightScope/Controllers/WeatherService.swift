import Foundation
import Combine

@MainActor
final class WeatherService: ObservableObject, WeatherProviding {
    struct FetchResult {
        let weatherByDate: [String: DayWeatherSummary]
        let errorMessage: String?
        let lastModifiedDate: Date?
        let locationKey: String
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
        let locationKey = Self.locationKey(latitude: latitude, longitude: longitude)
        let fallbackWeatherByDate = cachedWeatherByDate(for: locationKey)
        if activeLocationKey != locationKey {
            prepareForLocationChange(latitude: latitude, longitude: longitude)
        }
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentTask = Task {
            let result = await loadWeather(
                latitude: latitude,
                longitude: longitude,
                locationKey: locationKey,
                fallbackWeatherByDate: fallbackWeatherByDate
            )
            guard !Task.isCancelled else { return }
            applyFetchResult(result)
        }
        await currentTask?.value
    }

    func fetchWeatherSnapshot(latitude: Double, longitude: Double) async -> FetchResult {
        let locationKey = Self.locationKey(latitude: latitude, longitude: longitude)
        return await loadWeather(
            latitude: latitude,
            longitude: longitude,
            locationKey: locationKey,
            fallbackWeatherByDate: weatherByDateByLocation[locationKey] ?? [:]
        )
    }

    func applyFetchResult(_ result: FetchResult) {
        activeLocationKey = result.locationKey
        weatherByDateByLocation[result.locationKey] = result.weatherByDate
        weatherByDate = result.weatherByDate
        errorMessage = result.errorMessage
        if let lastModifiedDate = result.lastModifiedDate {
            lastModifiedDatesByLocation[result.locationKey] = lastModifiedDate
        }
        isLoading = false
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherByDate[forecastParser.dateKey(date)]
    }

    func prepareForLocationChange(latitude: Double, longitude: Double) {
        currentTask?.cancel()
        activeLocationKey = Self.locationKey(latitude: latitude, longitude: longitude)
        errorMessage = nil
        isLoading = false
    }

    private func loadWeather(
        latitude: Double,
        longitude: Double,
        locationKey: String,
        fallbackWeatherByDate: [String: DayWeatherSummary]
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
                    locationKey: locationKey
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
                    locationKey: locationKey
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

            let apiResponse: MetNorwayResponse
            do {
                apiResponse = try JSONDecoder().decode(MetNorwayResponse.self, from: data)
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }

            return FetchResult(
                weatherByDate: forecastParser.parse(response: apiResponse),
                errorMessage: nil,
                lastModifiedDate: lastModifiedDate,
                locationKey: locationKey
            )
        } catch {
            let serviceError = (error as? WeatherServiceError) ?? .networkError(underlying: error)
            return FetchResult(
                weatherByDate: fallbackWeatherByDate,
                errorMessage: serviceError.localizedDescription,
                lastModifiedDate: lastModifiedDatesByLocation[locationKey],
                locationKey: locationKey
            )
        }
    }

    func parse(response: MetNorwayResponse) -> [String: DayWeatherSummary] {
        forecastParser.parse(response: response)
    }

    func dateKey(_ date: Date) -> String {
        forecastParser.dateKey(date)
    }

    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        MetNorwayForecastParser.symbolCodeToWMO(symbolCode)
    }

    private static func locationKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
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
}
