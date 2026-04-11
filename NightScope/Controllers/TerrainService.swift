import Foundation

/// 観測地周辺の地形データを取得する Actor。
/// Open-Elevation API (POST /api/v1/lookup) から各方位 10km 先の標高を取得し、
/// 地平仰角プロファイルを構築する。API が利用不可の場合は nil を返す（平坦地扱い）。
actor TerrainService {
    private enum Constants {
        static let requestTimeout: TimeInterval = 5
        static let sampleDistanceMeters = 10_000.0
        static let sampleCount = 72
    }

    static let shared = TerrainService()

    private let cache = NSCache<NSString, NSArray>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

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
        for i in 0..<Constants.sampleCount {
            let (lat2, lon2) = destinationPoint(
                lat: latitude, lon: longitude,
                bearing: Double(i) * 5.0, distanceM: Constants.sampleDistanceMeters)
            locations.append(["latitude": lat2, "longitude": lon2])
        }
        guard let url = URL(string: "https://api.open-elevation.com/api/v1/lookup") else {
            return nil
        }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["locations": locations])
        } catch {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return parseAngles(from: data)
        } catch {
            return nil
        }
    }

    func parseAngles(from data: Data) -> [Double]? {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }

        guard let payload = json as? [String: Any],
              let results = payload["results"] as? [[String: Any]],
              results.count == Constants.sampleCount + 1
        else {
            return nil
        }

        let obsElev = (results[0]["elevation"] as? Double) ?? 0
        return (0..<Constants.sampleCount).map { index in
            let elev = (results[index + 1]["elevation"] as? Double) ?? 0
            return atan2(elev - obsElev, Constants.sampleDistanceMeters) * 180.0 / .pi
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
