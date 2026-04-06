import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MapKit

enum LightPollutionServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case invalidData
    case decodingError(underlying: Error)
    case networkFailure(underlying: Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "有効なURLが生成できませんでした。"
        case .invalidResponse(let statusCode):
            return "予期しないHTTPステータスコード: \(statusCode)"
        case .invalidData:
            return "レスポンスの形式が不正です。"
        case .decodingError(let underlying):
            return "デコード中にエラーが発生しました: \(underlying.localizedDescription)"
        case .networkFailure(let underlying):
            return "ネットワークエラー: \(underlying.localizedDescription)"
        case .noData:
            return "現在地の光害データが取得できませんでした。"
        }
    }
}

@MainActor
protocol LightPollutionProviding: AnyObject, ObservableObject {
    var bortleClass: Double? { get }
    var bortleClassPublisher: Published<Double?>.Publisher { get }
    var isLoading: Bool { get }
    var fetchFailed: Bool { get }

    func fetch(latitude: Double, longitude: Double) async
    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double
}

// MARK: - Nominatim Response (fallback)

private struct NominatimResponse: Decodable {
    struct Address: Decodable {
        let city: String?
        let town: String?
        let village: String?
        let hamlet: String?
        let suburb: String?
        let county: String?   // 郡（農村地域の指標）
    }
    let address: Address?
    /// OSM の place type（"city", "town", "village", "hamlet", "suburb" など）
    let type: String?
}

// MARK: - Tile Image Cache Box

/// NSCache に CGImage を格納するための参照型ラッパー。
final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// URLSession の completion handler（非 Sendable な関数型）を @unchecked Sendable でラップする。
final class ResultBox: @unchecked Sendable {
    private let handler: (Data?, Error?) -> Void
    init(_ handler: @escaping (Data?, Error?) -> Void) { self.handler = handler }
    func call(_ data: Data?, _ error: Error?) { handler(data, error) }
}

// MARK: - Tile Service

/// 光害タイルの取得・キャッシュ・デコードを担うサービス層。
/// View / Renderer からネットワーク・ディスクI/Oを分離する。
final class LightPollutionTileService: @unchecked Sendable {
    private enum TileConfig {
        static let cacheDirectoryName = "LightPollutionTiles"
        static let requestTimeout: TimeInterval = 15
        static let maxConnectionsPerHost = 8
        static let memoryCacheCostLimit = 100 * 1024 * 1024
        static let cgImageCacheCostLimit = 80 * 1024 * 1024
        static let descendantPreCropDepth = 2
        static let maximumZoomLevel = 19
    }

    static let shared = LightPollutionTileService()

    private let diskCacheDir: URL
    private let session: URLSession

    private let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = TileConfig.memoryCacheCostLimit
        return cache
    }()

    private let cgImageCache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.totalCostLimit = TileConfig.cgImageCacheCostLimit
        return cache
    }()

    init(
        fileManager: FileManager = .default,
        cachesDirectory: URL? = nil,
        session: URLSession? = nil
    ) {
        let cacheBase = cachesDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = cacheBase.appendingPathComponent(TileConfig.cacheDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskCacheDir = dir

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpMaximumConnectionsPerHost = TileConfig.maxConnectionsPerHost
            config.timeoutIntervalForRequest = TileConfig.requestTimeout
            self.session = URLSession(configuration: config)
        }
    }

    func loadTile(path: MKTileOverlayPath, url: URL, result: @escaping (Data?, Error?) -> Void) {
        let cacheKey = cacheKey(for: path)
        let diskURL = diskURL(for: cacheKey)

        if respondFromMemoryCache(cacheKey: cacheKey, path: path, result: result) {
            return
        }

        if respondFromDiskCache(cacheKey: cacheKey, path: path, diskURL: diskURL, result: result) {
            return
        }

        loadFromNetwork(path: path, cacheKey: cacheKey, diskURL: diskURL, url: url, result: result)
    }

    func hasTileData(for path: MKTileOverlayPath) -> Bool {
        memoryCache.object(forKey: cacheKey(for: path)) != nil
    }

    func cachedImage(for path: MKTileOverlayPath) -> CGImage? {
        cgImageCache.object(forKey: cacheKey(for: path))?.image
    }

    func decodeImageFromMemoryIfNeeded(for path: MKTileOverlayPath) -> CGImage? {
        let key = cacheKey(for: path)
        if let image = cgImageCache.object(forKey: key)?.image {
            return image
        }
        guard let data = memoryCache.object(forKey: key) as Data?,
              let image = Self.cgImage(from: data)
        else {
            return nil
        }
        cgImageCache.setObject(CGImageBox(image), forKey: key, cost: Self.cgImageCost(image))
        return image
    }

    func cacheCroppedImage(_ image: CGImage, for path: MKTileOverlayPath) {
        let key = cacheKey(for: path)
        cgImageCache.setObject(CGImageBox(image), forKey: key, cost: Self.cgImageCost(image))
    }

    static func cgImageCost(_ image: CGImage) -> Int { image.width * image.height * 4 }

    private func cacheKey(for path: MKTileOverlayPath) -> NSString {
        "\(path.z)_\(path.x)_\(path.y)" as NSString
    }

    private func diskURL(for cacheKey: NSString) -> URL {
        diskCacheDir.appendingPathComponent("\(cacheKey).png")
    }

    private func respondFromMemoryCache(
        cacheKey: NSString,
        path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) -> Bool {
        guard let cached = memoryCache.object(forKey: cacheKey) else {
            return false
        }

        if cgImageCache.object(forKey: cacheKey) == nil {
            let data = cached as Data
            let key = cacheKey as String
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                if let image = self.decodeAndCache(data: data, forKey: key as NSString) {
                    self.scheduleDescendantPreCrop(from: image, path: path)
                }
            }
        }

        result(cached as Data, nil)
        return true
    }

    private func respondFromDiskCache(
        cacheKey: NSString,
        path: MKTileOverlayPath,
        diskURL: URL,
        result: @escaping (Data?, Error?) -> Void
    ) -> Bool {
        guard let diskData = try? Data(contentsOf: diskURL, options: .mappedIfSafe) else {
            return false
        }

        memoryCache.setObject(diskData as NSData, forKey: cacheKey, cost: diskData.count)
        let image = decodeAndCache(data: diskData, forKey: cacheKey)
        result(diskData, nil)

        if let image {
            scheduleDescendantPreCrop(from: image, path: path)
        }

        return true
    }

    private func loadFromNetwork(
        path: MKTileOverlayPath,
        cacheKey: NSString,
        diskURL: URL,
        url: URL,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let request = URLRequest(url: url, timeoutInterval: TileConfig.requestTimeout)
        let key = cacheKey as String
        // result と key を @Sendable クロージャに渡すため nonisolated な型に変換
        let resultBox = ResultBox(result)
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let nsKey = key as NSString
            guard let data, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                resultBox.call(data, error)
                return
            }

            self.memoryCache.setObject(data as NSData, forKey: nsKey, cost: data.count)
            let image = self.decodeAndCache(data: data, forKey: nsKey)
            try? data.write(to: diskURL, options: .atomic)
            resultBox.call(data, nil)

            if let image {
                self.scheduleDescendantPreCrop(from: image, path: path)
            }
        }.resume()
    }

    private func decodeAndCache(data: Data, forKey key: NSString) -> CGImage? {
        guard let cgImage = Self.cgImage(from: data) else { return nil }
        cgImageCache.setObject(CGImageBox(cgImage), forKey: key, cost: Self.cgImageCost(cgImage))
        return cgImage
    }

    private static func cgImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }

    private func preCropDescendants(from cgImage: CGImage, path: MKTileOverlayPath) {
        for dz in 1...TileConfig.descendantPreCropDepth {
            let childZ = path.z + dz
            guard childZ <= TileConfig.maximumZoomLevel else { break }
            let scale = 1 << dz
            let baseX = path.x * scale
            let baseY = path.y * scale
            let divisions = CGFloat(scale)
            let tileW = CGFloat(cgImage.width) / divisions
            let tileH = CGFloat(cgImage.height) / divisions

            for dy in 0..<scale {
                for dx in 0..<scale {
                    let childPath = MKTileOverlayPath(x: baseX + dx, y: baseY + dy, z: childZ, contentScaleFactor: 1)
                    let srcRect = CGRect(
                        x: CGFloat(dx) * tileW,
                        y: CGFloat(dy) * tileH,
                        width: tileW,
                        height: tileH
                    )
                    if let cropped = cgImage.cropping(to: srcRect) {
                        cacheCroppedImage(cropped, for: childPath)
                    }
                }
            }
        }
    }

    private func scheduleDescendantPreCrop(from image: CGImage, path: MKTileOverlayPath) {
        Task.detached(priority: .utility) { [weak self] in
            self?.preCropDescendants(from: image, path: path)
        }
    }
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
final class LightPollutionService: ObservableObject, LightPollutionProviding {
    private enum Constants {
        /// 同一座標とみなすキャッシュ半径（度）≈ 5 km
        static let cacheRadiusDegrees = 0.05
        /// 自然夜空輝度 (mcd/m²)。Bortle 換算の基準値。
        static let naturalSkyBrightnessMcdPerSqm = 0.172
        /// qk トークン組み立て時の suffix（外部 API 固有）
        static let qkTokenSuffix = ";isuckdicks:)"
    }

    @Published var bortleClass: Double?
    var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
    @Published var isLoading = false
    @Published var fetchFailed = false

    private var lastFetchedCoordinate: (lat: Double, lon: Double)?

    private let session: URLSession
    private let qkTimestampProvider: () -> Int64

    init(
        session: URLSession = .shared,
        qkTimestampProvider: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.session = session
        self.qkTimestampProvider = qkTimestampProvider
    }

    func fetch(latitude: Double, longitude: Double) async {
        // 同じ座標（0.05度以内 ≈ 5km）では再取得しない（光害は静的データ）
        if let last = lastFetchedCoordinate,
           abs(last.lat - latitude) <= Constants.cacheRadiusDegrees,
           abs(last.lon - longitude) <= Constants.cacheRadiusDegrees {
            return
        }

        isLoading = true
        fetchFailed = false
        defer { isLoading = false }

        do {
            let bortle = try await fetchBortle(latitude: latitude, longitude: longitude)
            bortleClass = bortle
            lastFetchedCoordinate = (latitude, longitude)
            fetchFailed = false
            return
        } catch {
            // 主戦略失敗: フォールバックを試行
        }

        do {
            let bortle = try await fetchBortleFromNominatim(lat: latitude, lon: longitude)
            bortleClass = bortle
            lastFetchedCoordinate = (latitude, longitude)
            fetchFailed = false
            return
        } catch {
            // 失敗
        }

        bortleClass = nil
        fetchFailed = true
        lastFetchedCoordinate = nil
    }

    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
        try await fetchBortleFromLightPollutionMap(lat: latitude, lon: longitude)
    }

    // MARK: - Primary: lightpollutionmap.info

    private func fetchBortleFromLightPollutionMap(lat: Double, lon: Double) async throws -> Double {
        // qk トークン: btoa(Date.now() + Constants.qkTokenSuffix)  ← JS ソースより
        let timestamp = qkTimestampProvider()
        let raw = "\(timestamp)\(Constants.qkTokenSuffix)"
        let qk = Data(raw.utf8).base64EncodedString()

        // 座標順序は lon,lat（OpenLayers の慣例）
        // wa_2015: World Atlas 2015 データ。viirs_2022 はサーバーサイドバグで使用不可。
        let urlString = "https://www.lightpollutionmap.info/api/queryraster"
            + "?qk=\(qk)"
            + "&ql=wa_2015"
            + "&qt=point"
            + "&qd=\(lon),\(lat)"

        guard let url = URL(string: urlString) else {
            throw LightPollutionServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("NightScope/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LightPollutionServiceError.invalidResponse(statusCode: -1)
            }
            guard http.statusCode == 200 else {
                throw LightPollutionServiceError.invalidResponse(statusCode: http.statusCode)
            }
            guard let body = String(data: data, encoding: .utf8) else {
                throw LightPollutionServiceError.invalidData
            }

            let parts = body.split(separator: ",")
            guard let value = parts.first, let brightness = Double(value) else {
                throw LightPollutionServiceError.invalidData
            }

            return wa2015ToBortle(brightness)
        } catch let error as LightPollutionServiceError {
            throw error
        } catch {
            throw LightPollutionServiceError.networkFailure(underlying: error)
        }
    }

    // MARK: - Fallback: OSM Nominatim

    private func fetchBortleFromNominatim(lat: Double, lon: Double) async throws -> Double {
        let urlString = "https://nominatim.openstreetmap.org/reverse"
            + "?format=jsonv2"
            + "&lat=\(lat)"
            + "&lon=\(lon)"
            + "&addressdetails=1"
            + "&zoom=14"

        guard let url = URL(string: urlString) else {
            throw LightPollutionServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("NightScope/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LightPollutionServiceError.invalidResponse(statusCode: -1)
            }
            guard http.statusCode == 200 else {
                throw LightPollutionServiceError.invalidResponse(statusCode: http.statusCode)
            }

            let decoded: NominatimResponse
            do {
                decoded = try JSONDecoder().decode(NominatimResponse.self, from: data)
            } catch {
                throw LightPollutionServiceError.decodingError(underlying: error)
            }

            return estimateBortleFromAddress(decoded)
        } catch let error as LightPollutionServiceError {
            throw error
        } catch {
            throw LightPollutionServiceError.networkFailure(underlying: error)
        }
    }

    // MARK: - Bortle Conversion

    /// World Atlas 2015 の人工輝度値（mcd/m²）から Bortle クラスに変換する。
    ///
    /// 変換根拠:
    ///   - 自然夜空輝度 ≈ 0.172 mcd/m²
    ///   - ratio = 人工輝度 / 自然輝度
    ///   - Falchi 2016 論文の比率–Bortle対応表を使用（lightpollutionmap.info と同一）
    ///
    /// 補間方式:
    ///   - 対数スケール: 各 Bortle クラス間は約3倍の輝度差（対数スケール）
    ///   - クラス内: 隣接 ratio アンカーポイント間で対数補間
    ///   - 例: ratio 3.0（Bortle 7.0）→ 6.0（Bortle 7.63）→ 9.0（Bortle 8.0）
    private func wa2015ToBortle(_ brightness: Double) -> Double {
        let ratio = brightness / Constants.naturalSkyBrightnessMcdPerSqm

        // アンカーポイント: (ratio の下限, Bortle 値)
        let anchors: [(Double, Double)] = [
            (0.01, 2.0),
            (0.03, 3.0),
            (0.10, 4.0),
            (0.30, 5.0),
            (1.0, 6.0),
            (3.0, 7.0),
            (9.0, 8.0),
            (27.0, 9.0)
        ]

        // ratio < 0.01 → Bortle 1
        if ratio < 0.01 { return 1.0 }

        // ratio >= 27.0 → Bortle 9
        if ratio >= 27.0 { return 9.0 }

        // 隣接アンカー (lo, hi) を見つけて対数補間
        for i in 0..<(anchors.count - 1) {
            let (ratioLo, bortleLo) = anchors[i]
            let (ratioHi, bortleHi) = anchors[i + 1]

            if ratio >= ratioLo && ratio < ratioHi {
                // 対数補間: t = log(ratio / ratioLo) / log(ratioHi / ratioLo)
                let t = log(ratio / ratioLo) / log(ratioHi / ratioLo)
                return bortleLo + t * (bortleHi - bortleLo)
            }
        }

        // フォールバック（到達不可通）
        return 9.0
    }

    /// Nominatim レスポンスから Bortle を推定（フォールバック用）
    ///
    /// 推定根拠:
    ///   1. type フィールド（OSM place type）: 人口規模・都市機能と強く相関
    ///   2. address フィールド: type が取得できない場合のフォールバック
    ///   精度はおよそ ±1.5 Bortle クラス（lightpollutionmap.info 主戦略の補完用）
    private func estimateBortleFromAddress(_ response: NominatimResponse?) -> Double {
        // 1. type フィールドによる一次推定（Nominatim jsonv2 で利用可能）
        switch response?.type {
        case "city":               return 7.5  // 都市（数万〜数百万人規模）
        case "town":               return 5.5  // 町（1万〜10万人規模）
        case "village":            return 3.5  // 村（数百〜数千人規模）
        case "hamlet":             return 2.5  // 集落（数十〜数百人）
        case "isolated_dwelling":  return 2.0  // 孤立した建物
        case "suburb":             return 6.5  // 郊外住宅地
        case "quarter", "neighbourhood": return 6.0  // 市内の地区
        default: break
        }

        // 2. アドレスフィールドによる推定（フォールバック）
        let addr = response?.address
        let hasCity    = addr?.city    != nil
        let hasSuburb  = addr?.suburb  != nil
        let hasTown    = addr?.town    != nil
        let hasVillage = addr?.village != nil
        let hasHamlet  = addr?.hamlet  != nil
        let hasCounty  = addr?.county  != nil

        switch (hasCity, hasSuburb) {
        case (true, true):  return 7.5  // 都市内の郊外（市街地）
        case (false, true): return 6.5  // 郊外（suburb のみ）
        case (true, false): return 6.0  // 都市（suburb なし）
        default: break
        }
        if hasTown    { return 5.0 }  // 町
        if hasVillage { return 3.5 }  // 村
        if hasHamlet  { return 2.5 }  // 集落
        if hasCounty  { return 4.0 }  // 郡（農村地域）
        return 3.0                    // 不明（農村として推定）
    }
}
