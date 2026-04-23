import Foundation
import Combine
import CoreLocation
import WeatherKit

// WeatherKit.WeatherService と module 名を明示して Apple SDK 側を参照する。

@MainActor
final class WeatherKitService: ObservableObject, WeatherProviding {

    // MARK: - Internal location context

    private struct LocationContext {
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone

        var locationKey: String {
            WeatherKitService.locationKey(
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
            )
        }
    }

    // MARK: - WeatherProviding publishers

    @Published var weatherByDate: [String: DayWeatherSummary] = [:]
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { $weatherByDate }
    @Published var isLoading = false
    var isLoadingPublisher: AnyPublisher<Bool, Never> { $isLoading.eraseToAnyPublisher() }
    @Published var errorMessage: String?
    var errorMessagePublisher: AnyPublisher<String?, Never> { $errorMessage.eraseToAnyPublisher() }

    // MARK: - Cache / state

    private var currentTask: Task<Void, Never>?
    /// 保持する最大場所数
    private let maxCachedLocations = 10
    private var weatherByDateByLocation: [String: [String: DayWeatherSummary]] = [:]
    private var activeLocationKey: String?
    private var activeTimeZoneIdentifier = TimeZone.current.identifier

    // MARK: - WeatherProviding: fetch

    func fetchWeather(latitude: Double, longitude: Double, timeZone: TimeZone) async {
        let context = LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        let fallback = cachedWeatherByDate(for: context.locationKey)
        if activeLocationKey != context.locationKey {
            prepareForLocationChange(context)
        }
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentTask = Task {
            let result = await loadWeather(context: context, fallbackWeatherByDate: fallback)
            guard !Task.isCancelled else { return }
            applyFetchResult(result)
        }
        await currentTask?.value
    }

    func fetchWeatherSnapshot(latitude: Double, longitude: Double, timeZone: TimeZone) async -> WeatherFetchResult {
        let context = LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        return await loadWeather(
            context: context,
            fallbackWeatherByDate: weatherByDateByLocation[context.locationKey] ?? [:]
        )
    }

    func applyFetchResult(_ result: WeatherFetchResult) {
        activeLocationKey = result.locationKey
        activeTimeZoneIdentifier = result.timeZoneIdentifier
        weatherByDateByLocation[result.locationKey] = result.weatherByDate
        weatherByDate = result.weatherByDate
        errorMessage = result.errorMessage
        // WeatherKit は lastModifiedDate を提供しないため省略
        evictCacheIfNeeded()
        isLoading = false
    }

    // MARK: - WeatherProviding: query helpers

    func summary(for date: Date) -> DayWeatherSummary? {
        summary(for: date, from: weatherByDate, timeZone: activeTimeZone)
    }

    func summary(
        for date: Date,
        from weatherByDate: [String: DayWeatherSummary],
        timeZone: TimeZone
    ) -> DayWeatherSummary? {
        weatherByDate[dateKey(date, timeZone: timeZone)]
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
        let selectedDay   = ObservationTimeZone.startOfDay(for: date, timeZone: timeZone)
        let latestDay     = ObservationTimeZone.startOfDay(for: latestForecastDate, timeZone: timeZone)
        return selectedDay > latestDay
    }

    func dateKey(_ date: Date, timeZone: TimeZone) -> String {
        Self.makeDateKeyFormatter(timeZone: timeZone).string(from: date)
    }

    func prepareForLocationChange(latitude: Double, longitude: Double, timeZone: TimeZone) {
        currentTask?.cancel()
        prepareForLocationChange(
            LocationContext(latitude: latitude, longitude: longitude, timeZone: timeZone)
        )
    }

    // MARK: - Date key formatter

    /// "yyyy-MM-dd" 形式の DateFormatter を生成する（タイムゾーン依存）。
    private static func makeDateKeyFormatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }

    // MARK: - Private helpers

    private var activeTimeZone: TimeZone {
        TimeZone(identifier: activeTimeZoneIdentifier) ?? .current
    }

    private nonisolated static func locationKey(
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> String {
        let lat = (latitude  * 10_000).rounded() / 10_000
        let lon = (longitude * 10_000).rounded() / 10_000
        return String(format: "%.4f,%.4f|%@", lat, lon, timeZone.identifier)
    }

    private func cachedWeatherByDate(for locationKey: String) -> [String: DayWeatherSummary] {
        if let cached = weatherByDateByLocation[locationKey] { return cached }
        if activeLocationKey == locationKey { return weatherByDate }
        return [:]
    }

    private func prepareForLocationChange(_ context: LocationContext) {
        activeLocationKey = context.locationKey
        activeTimeZoneIdentifier = context.timeZone.identifier
        weatherByDate = weatherByDateByLocation[activeLocationKey ?? ""] ?? [:]
        errorMessage = nil
        isLoading = false
    }

    private func evictCacheIfNeeded() {
        guard weatherByDateByLocation.count > maxCachedLocations else { return }
        let keysToEvict = weatherByDateByLocation.keys.filter { $0 != activeLocationKey }
        for key in keysToEvict.prefix(weatherByDateByLocation.count - maxCachedLocations) {
            weatherByDateByLocation.removeValue(forKey: key)
        }
    }

    // MARK: - WeatherKit fetch

    private func loadWeather(
        context: LocationContext,
        fallbackWeatherByDate: [String: DayWeatherSummary]
    ) async -> WeatherFetchResult {
        do {
            let clLocation = CLLocation(latitude: context.latitude, longitude: context.longitude)

            // WeatherKit.WeatherService は module 名を明示して参照する
            let hourlyForecast = try await WeatherKit.WeatherService.shared.weather(
                for: clLocation,
                including: .hourly
            )

            if Task.isCancelled {
                return WeatherFetchResult(
                    weatherByDate: fallbackWeatherByDate,
                    errorMessage: nil,
                    lastModifiedDate: nil,
                    locationKey: context.locationKey,
                    timeZoneIdentifier: context.timeZone.identifier
                )
            }

            let coordinate = CLLocationCoordinate2D(
                latitude: context.latitude,
                longitude: context.longitude
            )
            let weatherByDate = groupNightHours(
                Array(hourlyForecast),
                coordinate: coordinate,
                timeZone: context.timeZone
            )

            return WeatherFetchResult(
                weatherByDate: weatherByDate,
                errorMessage: nil,
                lastModifiedDate: nil,
                locationKey: context.locationKey,
                timeZoneIdentifier: context.timeZone.identifier
            )
        } catch {
            let serviceError = WeatherServiceError.networkError(underlying: error)
            return WeatherFetchResult(
                weatherByDate: fallbackWeatherByDate,
                errorMessage: serviceError.localizedDescription,
                lastModifiedDate: nil,
                locationKey: context.locationKey,
                timeZoneIdentifier: context.timeZone.identifier
            )
        }
    }

    // MARK: - Night grouping

    private func groupNightHours(
        _ hourWeathers: [HourWeather],
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> [String: DayWeatherSummary] {
        // WeatherKit HourWeather → 共通 HourlyWeather へ変換
        let hours: [HourlyWeather] = hourWeathers.map { hw in
            HourlyWeather(
                date:                hw.date,
                temperatureCelsius:  hw.temperature.converted(to: .celsius).value,
                cloudCoverPercent:   hw.cloudCover * 100,
                precipitationMM:     hw.precipitationAmount.converted(to: .millimeters).value,
                windSpeedKmh:        hw.wind.speed.converted(to: .kilometersPerHour).value,
                humidityPercent:     hw.humidity * 100,
                dewpointCelsius:     hw.dewPoint.converted(to: .celsius).value,
                weatherCode:         WeatherConditionMapper.wmoCode(for: hw.condition),
                visibilityMeters:    hw.visibility.converted(to: .meters).value,
                windGustsKmh:        hw.wind.gust?.converted(to: .kilometersPerHour).value,
                windSpeedKmh500hpa:  nil   // WeatherKit は 500hPa 風速を非提供
            )
        }

        guard let earliest = hours.min(by: { $0.date < $1.date }),
              let latest   = hours.max(by: { $0.date < $1.date }) else {
            return [:]
        }

        let calendar  = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let formatter = Self.makeDateKeyFormatter(timeZone: timeZone)

        let startDay = calendar.date(
            byAdding: .day, value: -1,
            to: calendar.startOfDay(for: earliest.date)
        ) ?? calendar.startOfDay(for: earliest.date)

        let endDay = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.startOfDay(for: latest.date)
        ) ?? calendar.startOfDay(for: latest.date)

        // 各日の夜間インターバルを列挙（MilkyWayCalculator.nightInterval と統一）
        var intervals: [(key: String, interval: DateInterval)] = []
        var currentDay = startDay
        while currentDay <= endDay {
            if let interval = MilkyWayCalculator.nightInterval(
                for: currentDay,
                location: coordinate,
                timeZone: timeZone
            ) {
                intervals.append((formatter.string(from: currentDay), interval))
            }
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay)
                ?? endDay.addingTimeInterval(1)
        }

        // 各 hour を夜間インターバルへ振り分け
        var grouped: [String: [HourlyWeather]] = [:]
        for hour in hours.sorted(by: { $0.date < $1.date }) {
            if let match = intervals.first(where: { $0.interval.contains(hour.date) }) {
                grouped[match.key, default: []].append(hour)
            }
        }

        // DayWeatherSummary を生成
        var summaries: [String: DayWeatherSummary] = [:]
        for (key, groupedHours) in grouped {
            guard let date = formatter.date(from: key) else { continue }
            summaries[key] = DayWeatherSummary(
                date: date,
                nighttimeHours: groupedHours.sorted { $0.date < $1.date }
            )
        }
        return summaries
    }
}
