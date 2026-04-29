import Foundation
import CoreLocation
import Combine

// MARK: - 共通結果型

/// WeatherKit / HTTP 取得結果を共通形式で保持する。
struct WeatherFetchResult {
    let weatherByDate: [String: DayWeatherSummary]
    let errorMessage: String?
    let lastModifiedDate: Date?
    let locationKey: String
    let timeZoneIdentifier: String
}

/// 天気データ取得の失敗理由を利用者向け文言へ変換する。
enum WeatherServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case invalidData
    case decodingError(underlying: Error)
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.tr("URLの生成に失敗しました。")
        case .invalidResponse(let statusCode):
            return L10n.format("天気APIのステータスコードが不正です: %d", statusCode)
        case .invalidData:
            return L10n.tr("天気APIの取得データが不正です。")
        case .decodingError(let underlying):
            return L10n.format("天気データの解析に失敗しました: %@", underlying.localizedDescription)
        case .networkError(let underlying):
            return L10n.format("ネットワークエラーが発生しました: %@", underlying.localizedDescription)
        }
    }
}

/// 天気取得・参照・切り替え処理の共通インターフェース。
@MainActor
protocol WeatherProviding: AnyObject, ObservableObject, Sendable {
    var weatherByDate: [String: DayWeatherSummary] { get }
    var weatherByDatePublisher: Published<[String: DayWeatherSummary]>.Publisher { get }
    var isLoading: Bool { get }
    var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
    var errorMessage: String? { get }
    var errorMessagePublisher: AnyPublisher<String?, Never> { get }

    func fetchWeather(latitude: Double, longitude: Double, timeZone: TimeZone) async
    func summary(for date: Date) -> DayWeatherSummary?

    // MARK: - 拡張 API（WeatherKit 移行対応）
    func fetchWeatherSnapshot(latitude: Double, longitude: Double, timeZone: TimeZone) async -> WeatherFetchResult
    func applyFetchResult(_ result: WeatherFetchResult)
    func summary(for date: Date, from weatherByDate: [String: DayWeatherSummary], timeZone: TimeZone) -> DayWeatherSummary?
    func isForecastOutOfRange(for date: Date, in weatherByDate: [String: DayWeatherSummary], timeZone: TimeZone) -> Bool
    func dateKey(_ date: Date, timeZone: TimeZone) -> String
    func prepareForLocationChange(latitude: Double, longitude: Double, timeZone: TimeZone)
}

