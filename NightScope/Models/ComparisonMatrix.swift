import Foundation

/// 比較表の 1 セルに対応する、地点×日付の集計結果。
struct ComparisonCell: Identifiable {
    /// 取得状態と失敗理由を保持する。
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let id: String
    let locationID: UUID
    let date: Date
    let nightSummary: NightSummary?
    let weather: DayWeatherSummary?
    let bortleClass: Double?
    let index: StarGazingIndex?
    let loadState: LoadState

    init(
        locationID: UUID,
        date: Date,
        nightSummary: NightSummary? = nil,
        weather: DayWeatherSummary? = nil,
        bortleClass: Double? = nil,
        index: StarGazingIndex? = nil,
        loadState: LoadState = .idle
    ) {
        self.id = ComparisonCell.makeID(locationID: locationID, date: date)
        self.locationID = locationID
        self.date = date
        self.nightSummary = nightSummary
        self.weather = weather
        self.bortleClass = bortleClass
        self.index = index
        self.loadState = loadState
    }

    /// 地点 ID と日付を元に安定したセル ID を生成する。
    static func makeID(locationID: UUID, date: Date) -> String {
        "\(locationID.uuidString)|\(Int(date.timeIntervalSince1970))"
    }
}

/// 観測地点と日付を二次元に並べた比較データ。
struct ComparisonMatrix {
    let locations: [FavoriteLocation]
    let dates: [Date]
    let cellsByID: [String: ComparisonCell]

    static let empty = ComparisonMatrix(locations: [], dates: [], cellsByID: [:])
}
