import Foundation
import Combine

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
    private var lastModifiedDatesByLocation: [String: Date] = [:]
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
        if activeLocationKey != locationKey {
            prepareForLocationChange(latitude: latitude, longitude: longitude)
        }
        currentTask?.cancel()
        currentTask = Task {
            await performFetch(latitude: latitude, longitude: longitude, locationKey: locationKey)
        }
        await currentTask?.value
    }

    func summary(for date: Date) -> DayWeatherSummary? {
        weatherByDate[forecastParser.dateKey(date)]
    }

    func prepareForLocationChange(latitude: Double, longitude: Double) {
        currentTask?.cancel()
        activeLocationKey = Self.locationKey(latitude: latitude, longitude: longitude)
        weatherByDate = [:]
        errorMessage = nil
        isLoading = false
    }

    private func performFetch(latitude: Double, longitude: Double, locationKey: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let request = try requestFactory.makeRequest(
                latitude: latitude,
                longitude: longitude,
                lastModifiedDate: lastModifiedDatesByLocation[locationKey]
            )
            let (data, response) = try await urlSession.data(for: request)
            if Task.isCancelled { return }

            guard let http = response as? HTTPURLResponse else {
                throw WeatherServiceError.invalidResponse(statusCode: -1)
            }

            if http.statusCode == 304 {
                isLoading = false
                return
            }

            guard http.statusCode == 200 else {
                throw WeatherServiceError.invalidResponse(statusCode: http.statusCode)
            }

            if let lastModifiedHeader = http.value(forHTTPHeaderField: "Last-Modified") {
                lastModifiedDatesByLocation[locationKey] = MetNorwayFormatting.httpDateFormatter.date(from: lastModifiedHeader)
            }

            let apiResponse: MetNorwayResponse
            do {
                apiResponse = try JSONDecoder().decode(MetNorwayResponse.self, from: data)
            } catch {
                throw WeatherServiceError.decodingError(underlying: error)
            }

            weatherByDate = forecastParser.parse(response: apiResponse)
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

    static func symbolCodeToWMO(_ symbolCode: String?) -> Int {
        MetNorwayForecastParser.symbolCodeToWMO(symbolCode)
    }

    private static func locationKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}
