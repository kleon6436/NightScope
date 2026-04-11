import Foundation
import Compression
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MapKit

enum LightPollutionServiceError: Error, LocalizedError {
    case noData

    var errorDescription: String? {
        "現在地の光害データが取得できませんでした。"
    }
}

@MainActor
protocol LightPollutionProviding: AnyObject, ObservableObject {
    var bortleClass: Double? { get }
    var bortleClassPublisher: Published<Double?>.Publisher { get }
    var isLoading: Bool { get }
    var isLoadingPublisher: Published<Bool>.Publisher { get }
    var fetchFailed: Bool { get }

    func fetch(latitude: Double, longitude: Double) async
    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double
}

enum LightPollutionBundleDataSource {
    /// Map overlay と service の両方から使う共有グリッドデータ。
    static let sharedGridData: BortleGridData? = loadBundledGridData()

    private static func loadBundledGridData() -> BortleGridData? {
        guard let url = Bundle.main.url(forResource: "bortle_map", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return nil }
        return BortleGridData(data: data)
    }
}

struct BortleScaleConverter {
    private enum Constants {
        /// 自然夜空輝度 (mcd/m²)。Bortle 換算の基準値。
        static let naturalSkyBrightnessMcdPerSqm = 0.172
    }

    func bortleClass(for brightness: Double) -> Double {
        let ratio = brightness / Constants.naturalSkyBrightnessMcdPerSqm

        let anchors: [(Double, Double)] = [
            (0.01, 2.0),
            (0.03, 3.0),
            (0.10, 4.0),
            (0.30, 5.0),
            (1.0,  6.0),
            (3.0,  7.0),
            (9.0,  8.0),
            (27.0, 9.0)
        ]

        if ratio < 0.01 { return 1.0 }
        if ratio >= 27.0 { return 9.0 }

        for i in 0..<(anchors.count - 1) {
            let (ratioLo, bortleLo) = anchors[i]
            let (ratioHi, bortleHi) = anchors[i + 1]
            if ratio >= ratioLo && ratio < ratioHi {
                let t = log(ratio / ratioLo) / log(ratioHi / ratioLo)
                return bortleLo + t * (bortleHi - bortleLo)
            }
        }
        return 9.0
    }
}

// MARK: - Bortle Grid Data (Falchi World Atlas 2015 バンドルデータ)

/// バンドルされた光害バイナリデータを読み込む構造体。
///
/// バイナリフォーマット v1:
///   - Magic:     4 bytes  = 0x42 0x4F 0x52 0x54 ("BORT")
///   - Version:   UInt32 LE = 1
///   - Lat cells: Int32  LE (南から北: -90 → +90)
///   - Lon cells: Int32  LE (西から東: -180 → +180)
///   - Data:      Float32[] LE, row-major, 人工輝度 (mcd/m² 相当)
///
/// バイナリフォーマット v2 (zlib 圧縮):
///   - Magic:     4 bytes  = 0x42 0x4F 0x52 0x54 ("BORT")
///   - Version:   UInt32 LE = 2
///   - Lat cells: Int32  LE
///   - Lon cells: Int32  LE
///   - Raw size:  UInt32 LE (非圧縮データサイズ)
///   - Data:      zlib compressed Float32[] LE
///
/// 生成: Tools/generate_bortle_map.py
struct BortleGridData {
    private let latCells: Int
    private let lonCells: Int
    /// Float32 配列データを保持。
    /// v1: ファイルデータのスライスを直接保持（コピーなし）。
    /// v2: zlib 解凍後のデータを保持。
    private let data: Data

    private static let magic: [UInt8] = [0x42, 0x4F, 0x52, 0x54]  // "BORT"
    private static let headerSizeV1 = 16
    private static let headerSizeV2 = 20

    init?(data fileData: Data) {
        guard fileData.count >= Self.headerSizeV1 else { return nil }
        guard fileData[0..<4].elementsEqual(Self.magic) else { return nil }

        let version = Int(fileData[4..<8].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        })
        let latCells = Int(fileData[8..<12].withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self).littleEndian
        })
        let lonCells = Int(fileData[12..<16].withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self).littleEndian
        })
        guard latCells > 0, lonCells > 0 else { return nil }

        let expectedRawSize = latCells * lonCells * 4

        switch version {
        case 1:
            guard fileData.count == Self.headerSizeV1 + expectedRawSize else { return nil }
            self.data = fileData[Self.headerSizeV1...]

        case 2:
            guard fileData.count >= Self.headerSizeV2 else { return nil }
            let rawSize = Int(fileData[16..<20].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            })
            guard rawSize == expectedRawSize else { return nil }
            let compressedData = fileData[Self.headerSizeV2...]
            guard let decompressed = Self.zlibDecompress(compressedData, expectedSize: rawSize) else {
                return nil
            }
            self.data = decompressed

        default:
            return nil
        }

        self.latCells = latCells
        self.lonCells = lonCells
    }

    /// 指定座標の人工輝度 (mcd/m²) をバイリニア補間で返す。
    func brightness(latitude: Double, longitude: Double) -> Double {
        let latF = (latitude + 90.0) / 180.0 * Double(latCells)
        let lonF = (longitude + 180.0) / 360.0 * Double(lonCells)

        let lat0 = Int(latF).clamped(to: 0..<latCells)
        let lon0 = Int(lonF).clamped(to: 0..<lonCells)
        let lat1 = (lat0 + 1).clamped(to: 0..<latCells)
        let lon1 = (lon0 + 1).clamped(to: 0..<lonCells)

        let dt = latF - Double(lat0)
        let ds = lonF - Double(lon0)

        let v00 = Double(float(at: lat0 * lonCells + lon0))
        let v01 = Double(float(at: lat0 * lonCells + lon1))
        let v10 = Double(float(at: lat1 * lonCells + lon0))
        let v11 = Double(float(at: lat1 * lonCells + lon1))

        return (1 - dt) * (1 - ds) * v00
             + (1 - dt) *      ds  * v01
             +      dt  * (1 - ds) * v10
             +      dt  *      ds  * v11
    }

    @inline(__always)
    private func float(at index: Int) -> Float {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 4, as: Float.self) }
    }

    func withStorage<Result>(_ body: (UnsafeRawBufferPointer, Int, Int) -> Result) -> Result {
        data.withUnsafeBytes { body($0, latCells, lonCells) }
    }

    // MARK: - zlib Decompression

    private static func zlibDecompress(_ compressed: Data, expectedSize: Int) -> Data? {
        var decompressed = Data(count: expectedSize)
        let result = compressed.withUnsafeBytes { srcPtr -> Int in
            decompressed.withUnsafeMutableBytes { dstPtr -> Int in
                guard let srcBase = srcPtr.baseAddress,
                      let dstBase = dstPtr.baseAddress else { return -1 }
                let written = compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self), expectedSize,
                    srcBase.assumingMemoryBound(to: UInt8.self), compressed.count,
                    nil, COMPRESSION_ZLIB
                )
                return written
            }
        }
        guard result == expectedSize else { return nil }
        return decompressed
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}

// MARK: - Tile Image Cache Box

/// NSCache に CGImage を格納するための参照型ラッパー。
final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

// MARK: - Tile Service

/// 光害タイルのメモリキャッシュ・デコードを担うサービス層。
/// バンドルデータからローカルレンダリングされたタイルをメモリキャッシュで管理する。
final class LightPollutionTileService: @unchecked Sendable {
    private enum TileConfig {
        static let memoryCacheCostLimit = 100 * 1024 * 1024
        static let cgImageCacheCostLimit = 80 * 1024 * 1024
        static let descendantPreCropDepth = 2
        static let maximumZoomLevel = 19
    }

    static let shared = LightPollutionTileService()

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

    init() {}

    /// メモリキャッシュからデータを返す。なければ nil。
    func cachedTileData(for path: MKTileOverlayPath) -> Data? {
        memoryCache.object(forKey: cacheKey(for: path)) as Data?
    }

    /// データをメモリキャッシュに書き込み、子ズームタイルを先読みする。
    func storeTileData(_ data: Data, for path: MKTileOverlayPath) {
        let key = cacheKey(for: path)
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        if let image = decodeAndCache(data: data, forKey: key) {
            scheduleDescendantPreCrop(from: image, path: path)
        }
    }

    func storeRenderedTile(_ renderedTile: RenderedLightPollutionTile, for path: MKTileOverlayPath) {
        let key = cacheKey(for: path)
        memoryCache.setObject(renderedTile.data as NSData, forKey: key, cost: renderedTile.data.count)
        cgImageCache.setObject(
            CGImageBox(renderedTile.image),
            forKey: key,
            cost: Self.cgImageCost(renderedTile.image)
        )
        scheduleDescendantPreCrop(from: renderedTile.image, path: path)
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

/// Falchi World Atlas 2015 バンドルデータから Bortle 値（連続 Double）を取得するサービス。
///
/// バンドルデータが存在しない場合は fetchFailed = true、bortleClass = nil となる。
/// バンドルデータの生成: Tools/generate_bortle_map.py (CC-BY 4.0, Falchi et al. 2016)
@MainActor
final class LightPollutionService: ObservableObject, LightPollutionProviding {
    private enum Constants {
        /// 同一座標とみなすキャッシュ半径（度）≈ 5 km
        static let cacheRadiusDegrees = 0.05
    }

    @Published var bortleClass: Double?
    var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
    @Published var isLoading = false
    var isLoadingPublisher: Published<Bool>.Publisher { $isLoading }
    @Published var fetchFailed = false

    private var lastFetchedCoordinate: (lat: Double, lon: Double)?

    /// バンドルデータ（アプリ起動時に一度だけロード）
    private let gridData: BortleGridData?
    private let scaleConverter: BortleScaleConverter

    init(
        gridData: BortleGridData? = LightPollutionBundleDataSource.sharedGridData,
        scaleConverter: BortleScaleConverter = BortleScaleConverter()
    ) {
        self.gridData = gridData
        self.scaleConverter = scaleConverter
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
        } catch {
            bortleClass = nil
            fetchFailed = true
            lastFetchedCoordinate = nil
        }
    }

    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
        guard let grid = gridData else {
            throw LightPollutionServiceError.noData
        }
        let brightness = grid.brightness(latitude: latitude, longitude: longitude)
        return scaleConverter.bortleClass(for: brightness)
    }

    // MARK: - Bortle Conversion

    /// World Atlas 2015 の人工輝度値（mcd/m²）から Bortle クラスに変換する。
    ///
    /// 変換根拠:
    ///   - 自然夜空輝度 ≈ 0.172 mcd/m²
    ///   - ratio = 人工輝度 / 自然輝度
    ///   - Falchi 2016 論文の比率–Bortle対応表を使用
    func wa2015ToBortle(_ brightness: Double) -> Double {
        scaleConverter.bortleClass(for: brightness)
    }
}
