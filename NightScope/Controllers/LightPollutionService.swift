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
        // rasterio from_bounds はセル中心グリッドを生成するため 0.5 セル分引く
        let latF = (latitude + 90.0) / 180.0 * Double(latCells) - 0.5
        let lonF = (longitude + 180.0) / 360.0 * Double(lonCells) - 0.5

        let lat0 = Int(latF.rounded(.down)).clamped(to: 0..<latCells)
        let lon0 = Int(lonF.rounded(.down)).clamped(to: 0..<lonCells)
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

// MARK: - ResultBox

/// completion handler（非 Sendable な関数型）を @unchecked Sendable でラップする。
/// バックグラウンドキューから安全に呼び出すために使用する。
final class ResultBox: @unchecked Sendable {
    private let handler: (Data?, Error?) -> Void
    init(_ handler: @escaping (Data?, Error?) -> Void) { self.handler = handler }
    func call(_ data: Data?, _ error: Error?) { handler(data, error) }
}

// MARK: - Tile Service

/// 光害タイルの PNG データをメモリキャッシュで管理するサービス層。
final class LightPollutionTileService: @unchecked Sendable {
    private enum TileConfig {
        static let memoryCacheCostLimit = 50 * 1024 * 1024
    }

    static let shared = LightPollutionTileService()

    private let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = TileConfig.memoryCacheCostLimit
        return cache
    }()

    func cachedTileData(for path: MKTileOverlayPath) -> Data? {
        memoryCache.object(forKey: cacheKey(for: path)) as Data?
    }

    func storeTileData(_ data: Data, for path: MKTileOverlayPath) {
        memoryCache.setObject(data as NSData, forKey: cacheKey(for: path), cost: data.count)
    }

    private func cacheKey(for path: MKTileOverlayPath) -> NSString {
        "\(path.z)_\(path.x)_\(path.y)" as NSString
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

    struct FetchResult {
        let bortleClass: Double?
        let fetchFailed: Bool
        let lastFetchedCoordinate: (lat: Double, lon: Double)?
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

    func prepareForLocationChange() {
        isLoading = false
        fetchFailed = false
    }

    func fetch(latitude: Double, longitude: Double) async {
        isLoading = true
        fetchFailed = false
        let result = await fetchSnapshot(latitude: latitude, longitude: longitude)
        applyFetchResult(result)
    }

    func fetchSnapshot(latitude: Double, longitude: Double) async -> FetchResult {
        // 同じ座標（0.05度以内 ≈ 5km）では再取得しない（光害は静的データ）
        if let last = lastFetchedCoordinate,
           abs(last.lat - latitude) <= Constants.cacheRadiusDegrees,
           abs(last.lon - longitude) <= Constants.cacheRadiusDegrees {
            return FetchResult(
                bortleClass: bortleClass,
                fetchFailed: fetchFailed,
                lastFetchedCoordinate: lastFetchedCoordinate
            )
        }

        do {
            let bortle = try await fetchBortle(latitude: latitude, longitude: longitude)
            return FetchResult(
                bortleClass: bortle,
                fetchFailed: false,
                lastFetchedCoordinate: (latitude, longitude)
            )
        } catch {
            return FetchResult(
                bortleClass: nil,
                fetchFailed: true,
                lastFetchedCoordinate: nil
            )
        }
    }

    func applyFetchResult(_ result: FetchResult) {
        bortleClass = result.bortleClass
        fetchFailed = result.fetchFailed
        lastFetchedCoordinate = result.lastFetchedCoordinate
        isLoading = false
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
