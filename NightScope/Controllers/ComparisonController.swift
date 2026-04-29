import Foundation
import CoreLocation

/// 保存済み地点の夜間条件を日単位で比較するコントローラ。
@MainActor
final class ComparisonController: ObservableObject {
    @Published private(set) var matrix: ComparisonMatrix = .empty
    @Published private(set) var isRefreshing = false
    /// 比較に含める日数。
    @Published var dayCount: Int = 7

    private let favoriteStore: any FavoriteLocationStoring
    private let weatherService: any WeatherProviding
    private let lightPollutionService: any LightPollutionProviding
    private let calculationService: any NightCalculating

    /// 比較対象のデータソースを注入する。
    init(
        favoriteStore: any FavoriteLocationStoring,
        weatherService: any WeatherProviding,
        lightPollutionService: any LightPollutionProviding,
        calculationService: any NightCalculating
    ) {
        self.favoriteStore = favoriteStore
        self.weatherService = weatherService
        self.lightPollutionService = lightPollutionService
        self.calculationService = calculationService
    }

    /// 現在の保存地点で比較マトリクスを再構築する。
    func refresh(referenceDate: Date = Date(), locations: [FavoriteLocation]? = nil) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let locations = locations ?? favoriteStore.loadAll()
        let dates = Self.makeDates(referenceDate: referenceDate, dayCount: dayCount)
        matrix = ComparisonMatrix(
            locations: locations,
            dates: dates,
            cellsByID: Dictionary(uniqueKeysWithValues: locations.flatMap { location in
                dates.map { date in
                    let cell = ComparisonCell(locationID: location.id, date: date, loadState: .loading)
                    return (cell.id, cell)
                }
            })
        )

        let computed = await computeMatrix(referenceDate: referenceDate, locations: locations)
        matrix = computed
    }

    /// 再利用しやすい純粋計算として比較マトリクスを返す。
    func computeMatrix(referenceDate: Date = Date(), locations: [FavoriteLocation]? = nil) async -> ComparisonMatrix {
        let locations = locations ?? favoriteStore.loadAll()
        return await Self.computeMatrix(
            referenceDate: referenceDate,
            locations: locations,
            dayCount: dayCount,
            weatherService: weatherService,
            lightPollutionService: lightPollutionService,
            calculationService: calculationService
        )
    }

    /// 指定地点・指定日のセルを返す。
    func cell(for locationID: UUID, date: Date) -> ComparisonCell? {
        matrix.cellsByID[ComparisonCell.makeID(locationID: locationID, date: date)]
    }

    /// 指定日における最良セルを返す。
    func bestCell(for date: Date) -> ComparisonCell? {
        matrix.locations
            .compactMap { cell(for: $0.id, date: date) }
            .max { ($0.index?.score ?? Int.min) < ($1.index?.score ?? Int.min) }
    }

    private static func makeDates(referenceDate: Date, dayCount: Int) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: referenceDate)
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 保存済み地点ごとの夜間条件をまとめて評価する。
    static func computeMatrix(
        referenceDate: Date,
        locations: [FavoriteLocation],
        dayCount: Int,
        weatherService: any WeatherProviding,
        lightPollutionService: any LightPollutionProviding,
        calculationService: any NightCalculating
    ) async -> ComparisonMatrix {
        let dates = makeDates(referenceDate: referenceDate, dayCount: dayCount)
        var cellsByID = Dictionary(uniqueKeysWithValues: locations.flatMap { location in
            dates.map { date in
                let cell = ComparisonCell(locationID: location.id, date: date, loadState: .loading)
                return (cell.id, cell)
            }
        })

        guard !locations.isEmpty else {
            return ComparisonMatrix(locations: [], dates: dates, cellsByID: [:])
        }

        for location in locations {
            guard !Task.isCancelled else { break }

            let timeZone = TimeZone(identifier: location.timeZoneIdentifier) ?? .current
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let weatherResult = await weatherService.fetchWeatherSnapshot(
                latitude: location.latitude,
                longitude: location.longitude,
                timeZone: timeZone
            )
            let bortleClass = try? await lightPollutionService.fetchBortle(
                latitude: location.latitude,
                longitude: location.longitude
            )
            let nights = await calculationService.calculateUpcomingNights(
                from: referenceDate,
                location: coordinate,
                timeZone: timeZone,
                days: dayCount
            )

            for (offset, date) in dates.enumerated() {
                let cellID = ComparisonCell.makeID(locationID: location.id, date: date)
                guard offset < nights.count else {
                    cellsByID[cellID] = ComparisonCell(
                        locationID: location.id,
                        date: date,
                        bortleClass: bortleClass,
                        loadState: .failed(L10n.tr("取得失敗"))
                    )
                    continue
                }

                let night = nights[offset]
                let weather = weatherService.summary(
                    for: night.date,
                    from: weatherResult.weatherByDate,
                    timeZone: timeZone
                )
                let index = StarGazingIndex.compute(
                    nightSummary: night,
                    weather: weather,
                    bortleClass: bortleClass,
                    referenceDate: referenceDate
                )
                cellsByID[cellID] = ComparisonCell(
                    locationID: location.id,
                    date: date,
                    nightSummary: night,
                    weather: weather,
                    bortleClass: bortleClass,
                    index: index,
                    loadState: .loaded
                )
            }
        }

        return ComparisonMatrix(locations: locations, dates: dates, cellsByID: cellsByID)
    }
}
