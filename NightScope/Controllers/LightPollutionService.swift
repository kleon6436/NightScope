import Foundation

// MARK: - Nominatim Response (fallback)

private struct NominatimResponse: Decodable {
    struct Address: Decodable {
        let city: String?
        let town: String?
        let village: String?
        let hamlet: String?
        let suburb: String?
    }
    let address: Address?
}

// MARK: - Service

/// lightpollutionmap.info の World Atlas 2015 データから Bortle 値（連続 Double）を取得するサービス。
///
/// 主戦略: lightpollutionmap.info/api/queryraster (wa_2015 レイヤー)
///   - 座標: lon,lat 形式
///   - レスポンス: "{人工輝度_mcd/m²},{標高_m}"
///   - Bortle 換算: 輝度 / 自然夜空輝度(0.172 mcd/m²) = 比率 → Bortle 値（対数補間）
///
/// フォールバック: OSM Nominatim 逆ジオコーディング
@MainActor
class LightPollutionService: ObservableObject {
    @Published var bortleClass: Double?
    @Published var isLoading = false
    @Published var fetchFailed = false

    private var lastFetchedCoordinate: (lat: Double, lon: Double)?

    func fetch(latitude: Double, longitude: Double) async {
        // 同じ座標（0.05度以内 ≈ 5km）では再取得しない（光害は静的データ）
        if let last = lastFetchedCoordinate,
           abs(last.lat - latitude) < 0.05,
           abs(last.lon - longitude) < 0.05 {
            return
        }

        isLoading = true
        fetchFailed = false
        defer { isLoading = false }

        if let bortle = await fetchFromLightPollutionMap(lat: latitude, lon: longitude) {
            bortleClass = bortle
            lastFetchedCoordinate = (latitude, longitude)
            return
        }

        if let bortle = await fetchFromNominatim(lat: latitude, lon: longitude) {
            bortleClass = bortle
            lastFetchedCoordinate = (latitude, longitude)
            return
        }

        bortleClass = nil
        fetchFailed = true
    }

    // MARK: - Primary: lightpollutionmap.info

    private func fetchFromLightPollutionMap(lat: Double, lon: Double) async -> Double? {
        // qk トークン: btoa(Date.now() + ";isuckdicks:)")  ← JS ソースより
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let raw = "\(timestamp);isuckdicks:)"
        let qk = Data(raw.utf8).base64EncodedString()

        // 座標順序は lon,lat（OpenLayers の慣例）
        // wa_2015: World Atlas 2015 データ。viirs_2022 はサーバーサイドバグで使用不可。
        let urlString = "https://www.lightpollutionmap.info/api/queryraster"
            + "?qk=\(qk)"
            + "&ql=wa_2015"
            + "&qt=point"
            + "&qd=\(lon),\(lat)"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("NightScope/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let body = String(data: data, encoding: .utf8) else { return nil }

            // レスポンス形式: "{輝度_mcd/m²},{標高_m}"
            // 例: "6.6520867347717285,36.0" (東京)
            //      "0.023789362981915474,1500.0" (長野山地)
            let parts = body.split(separator: ",")
            guard let brightness = Double(parts[0]) else { return nil }

            return wa2015ToBortle(brightness)
        } catch {
            return nil
        }
    }

    // MARK: - Fallback: OSM Nominatim

    private func fetchFromNominatim(lat: Double, lon: Double) async -> Double? {
        let urlString = "https://nominatim.openstreetmap.org/reverse"
            + "?format=jsonv2"
            + "&lat=\(lat)"
            + "&lon=\(lon)"
            + "&addressdetails=1"
            + "&zoom=14"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("NightScope/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(NominatimResponse.self, from: data)
            return estimateBortleFromAddress(response.address)
        } catch {
            return nil
        }
    }

    // MARK: - Bortle Conversion

    /// World Atlas 2015 の人工輝度値（mcd/m²）から Bortle クラスに変換する。
    ///
    /// 変換根拠:
    ///   - 自然夜空輝度 ≈ 0.172 mcd/m²
    ///   - ratio = 人工輝度 / 自然輝度
    ///   - Falchi 2016 論文の比率–Bortle対応表を使用（lightpollutionmap.info と同一）
    private func wa2015ToBortle(_ brightness: Double) -> Double {
        let ratio = brightness / 0.172
        switch ratio {
        case ..<0.01:      return 1  // < 0.00172 mcd/m²  非常に暗い
        case 0.01..<0.03:  return 2  // 田舎の暗い空
        case 0.03..<0.10:  return 3  // 農村部
        case 0.10..<0.30:  return 4  // 農村–郊外境界
        case 0.30..<1.0:   return 5  // 郊外
        case 1.0..<3.0:    return 6  // 明るい郊外
        case 3.0..<9.0:    return 7  // 郊外–都市境界
        case 9.0..<27.0:   return 8  // 都市
        default:           return 9  // > 4.64 mcd/m²  都市中心部
        }
    }

    /// Nominatim アドレスから Bortle を推定（フォールバック用）
    private func estimateBortleFromAddress(_ addr: NominatimResponse.Address?) -> Double {
        let hasCity    = addr?.city    != nil
        let hasSuburb  = addr?.suburb  != nil
        let hasTown    = addr?.town    != nil
        let hasVillage = addr?.village != nil
        let hasHamlet  = addr?.hamlet  != nil

        switch (hasCity, hasSuburb) {
        case (true, true):  return 7.0
        case (false, true): return 6.0
        case (true, false): return 5.0
        default: break
        }
        if hasTown    { return 4.0 }
        if hasVillage { return 3.0 }
        if hasHamlet  { return 2.0 }
        return 2.0
    }
}
