import Foundation

/// 観測地周辺の地形データを取得する Actor。
/// Open-Elevation API (POST /api/v1/lookup) から各方位 10km 先の標高を取得し、
/// 地平仰角プロファイルを構築する。API が利用不可の場合は nil を返す（平坦地扱い）。
actor TerrainService {
    static let shared = TerrainService()

    private let cache = NSCache<NSString, NSArray>()

    /// 観測地座標に対するプロファイルを返す。キャッシュがあればそれを使う。
    /// API 失敗時は nil を返す（呼び出し元は平坦地として扱う）。
    func fetchProfile(latitude: Double, longitude: Double) async -> TerrainProfile? {
        let key = cacheKey(lat: latitude, lon: longitude) as NSString
        if let cached = cache.object(forKey: key) as? [Double] {
            return TerrainProfile(horizonAngles: cached)
        }
        guard let angles = await fetchFromAPI(latitude: latitude, longitude: longitude) else {
            return nil
        }
        cache.setObject(angles as NSArray, forKey: key)
        return TerrainProfile(horizonAngles: angles)
    }

    // MARK: - Private

    private func cacheKey(lat: Double, lon: Double) -> String {
        let rLat = (lat * 100).rounded() / 100
        let rLon = (lon * 100).rounded() / 100
        return "\(rLat),\(rLon)"
    }

    /// Open-Elevation API から 72 方位の地平仰角を取得する。
    /// 各方位 10km 地点 + 観測地点の 73 点をバッチリクエストする。
    private func fetchFromAPI(latitude: Double, longitude: Double) async -> [Double]? {
        var locations: [[String: Double]] = [
            ["latitude": latitude, "longitude": longitude]
        ]
        for i in 0..<72 {
            let (lat2, lon2) = destinationPoint(
                lat: latitude, lon: longitude,
                bearing: Double(i) * 5.0, distanceM: 10_000)
            locations.append(["latitude": lat2, "longitude": lon2])
        }
        guard let url = URL(string: "https://api.open-elevation.com/api/v1/lookup"),
              let body = try? JSONSerialization.data(withJSONObject: ["locations": locations])
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  results.count == 73
            else { return nil }

            let obsElev = (results[0]["elevation"] as? Double) ?? 0
            let angles: [Double] = (0..<72).map { i in
                let elev = (results[i + 1]["elevation"] as? Double) ?? 0
                return atan2(elev - obsElev, 10_000.0) * 180.0 / .pi
            }
            return angles
        } catch {
            return nil
        }
    }

    /// Haversine 公式: 距離 distanceM (m) 先の方位 bearing (度) にある座標を返す。
    private func destinationPoint(lat: Double, lon: Double,
                                  bearing: Double, distanceM: Double) -> (Double, Double) {
        let R    = 6_371_000.0
        let d    = distanceM / R
        let lat1 = lat * .pi / 180
        let lon1 = lon * .pi / 180
        let brng = bearing * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1),
                                cos(d) - sin(lat1) * sin(lat2))
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }
}
