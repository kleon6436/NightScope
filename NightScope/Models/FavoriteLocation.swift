import Foundation

/// ユーザーが保存した観測地の永続化モデル。
/// - Note: 緯度経度は WGS84、タイムゾーンは IANA 識別子で保持する。
struct FavoriteLocation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// 観測地の緯度（度）。
    var latitude: Double
    /// 観測地の経度（度）。
    var longitude: Double
    /// 観測地の IANA タイムゾーン識別子。
    var timeZoneIdentifier: String
    /// この観測地を登録した日時。
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = createdAt
    }
}
