import MapKit
import ImageIO
import CoreGraphics

// MARK: - ViewportBox

/// タブ間でビューポートを共有する参照型コンテナ。
/// @State と組み合わせることで、パン中に SwiftUI 再描画を発生させずに状態を更新できる。
final class ViewportBox {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan

    init(center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
         span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)) {
        self.center = center
        self.span = span
    }
}

// MARK: - Sync State

/// MKMapView タブ切り替え時のビューポート同期パラメータ。trigger の変化で同期を検知する。
struct MapKitSyncState: Equatable {
    let trigger: Int
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trigger == rhs.trigger
    }
}

// MARK: - LightPollutionTileOverlay

final class LightPollutionTileOverlay: MKTileOverlay {

    private enum OverlayConfig {
        static let minimumZoomLevel = 1
        /// ズームレベル上限。MapKit の最大タイルレベルに合わせて 19 を設定。
        /// 上限値より高いズームでも loadTile が呼ばれ、グリッドデータをアップサンプリングして描画する。
        static let maximumZoomLevel = 19
        static let tilePixelSize = 256
    }

    let tileService: LightPollutionTileService

    /// Falchi Atlas バンドルデータ（LightPollutionService と同じインスタンスを使う）
    private let bortleGrid: BortleGridData?

    /// タイルレンダリングの同時実行数を制限するキュー
    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(urlTemplate: String?) {
        self.tileService = .shared
        self.bortleGrid = LightPollutionBundleDataSource.sharedGridData
        super.init(urlTemplate: urlTemplate)
        configureOverlay()
    }

    init(
        urlTemplate: String? = nil,
        tileService: LightPollutionTileService,
        gridData: BortleGridData?
    ) {
        self.tileService = tileService
        self.bortleGrid = gridData
        super.init(urlTemplate: urlTemplate)
        configureOverlay()
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        if let cached = tileService.cachedTileData(for: path) {
            result(cached, nil)
            return
        }
        guard let grid = bortleGrid else {
            result(Self.transparentTileData(), nil)
            return
        }
        let tileService = self.tileService
        // @unchecked Sendable ラッパーなしで completion を渡すため nonisolated クロージャを使用
        let resultBox = ResultBox(result)
        Self.renderQueue.addOperation {
            let data = Self.renderTile(path: path, grid: grid, size: OverlayConfig.tilePixelSize)
            let tileData = data ?? Self.transparentTileData()
            tileService.storeTileData(tileData, for: path)
            resultBox.call(tileData, nil)
        }
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        URL(string: "about:blank")!
    }

    private func configureOverlay() {
        canReplaceMapContent = false
        minimumZ = OverlayConfig.minimumZoomLevel
        maximumZ = OverlayConfig.maximumZoomLevel
    }

    // MARK: - Local Tile Rendering

    private struct LongitudeSample {
        let lon0: Int
        let lon1: Int
        let fraction: Double
    }

    @inline(__always)
    private static func clampedIndex(_ value: Int, upperBound: Int) -> Int {
        max(0, min(value, upperBound - 1))
    }

    /// バンドル Bortle グリッドから 256×256 PNG タイルをレンダリングする。
    static func renderTile(path: MKTileOverlayPath, grid: BortleGridData, size: Int) -> Data? {
        let n = pow(2.0, Double(path.z))
        let minLon = Double(path.x) / n * 360.0 - 180.0
        let lonSpan = 360.0 / n

        // メルカトル Y 座標（ピクセルはこの空間で等間隔）
        let mercYTop = Double.pi * (1.0 - 2.0 * Double(path.y) / n)
        let mercYBottom = Double.pi * (1.0 - 2.0 * Double(path.y + 1) / n)

        let byteCount = size * size * 4
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        defer { pixels.deallocate() }

        let sizeD = Double(size)

        grid.withStorage { rawBuffer, latCells, lonCells in
            // 経度サンプルを事前計算（行ループ外）
            // セル中心補正: rasterio from_bounds は各セルが均等幅のピクセルとして
            // 格納されており、インデックス i が緯度/経度範囲の先頭 (left edge) に対応する。
            // そのため `lonF - 0.5` でセル中心を正しく参照する。
            let longitudeSamples = (0..<size).map { px in
                let lon = minLon + lonSpan * (Double(px) + 0.5) / sizeD
                let lonF = (lon + 180.0) / 360.0 * Double(lonCells) - 0.5
                let lon0 = clampedIndex(Int(lonF.rounded(.down)), upperBound: lonCells)
                let lon1 = clampedIndex(lon0 + 1, upperBound: lonCells)
                return LongitudeSample(lon0: lon0, lon1: lon1, fraction: lonF - lonF.rounded(.down))
            }

            for py in 0..<size {
                // メルカトル Y 空間で線形補間し、緯度に変換（ピクセル中心サンプリング）
                let mercY = mercYTop + (mercYBottom - mercYTop) * (Double(py) + 0.5) / sizeD
                let lat = atan(sinh(mercY)) * 180.0 / .pi
                // セル中心補正
                let latF = (lat + 90.0) / 180.0 * Double(latCells) - 0.5
                let lat0 = clampedIndex(Int(latF.rounded(.down)), upperBound: latCells)
                let lat1 = clampedIndex(lat0 + 1, upperBound: latCells)
                let dt = latF - latF.rounded(.down)
                let row0 = lat0 * lonCells
                let row1 = lat1 * lonCells

                for px in 0..<size {
                    let sample = longitudeSamples[px]
                    let ds = sample.fraction
                    let v00 = Double(rawBuffer.loadUnaligned(fromByteOffset: (row0 + sample.lon0) * 4, as: Float.self))
                    let v01 = Double(rawBuffer.loadUnaligned(fromByteOffset: (row0 + sample.lon1) * 4, as: Float.self))
                    let v10 = Double(rawBuffer.loadUnaligned(fromByteOffset: (row1 + sample.lon0) * 4, as: Float.self))
                    let v11 = Double(rawBuffer.loadUnaligned(fromByteOffset: (row1 + sample.lon1) * 4, as: Float.self))
                    let brightness = (1 - dt) * (1 - ds) * v00
                        + (1 - dt) * ds * v01
                        + dt * (1 - ds) * v10
                        + dt * ds * v11
                    let (r, g, b, a) = bortleToRGBA(brightness)
                    let idx = (py * size + px) * 4
                    pixels[idx] = r
                    pixels[idx + 1] = g
                    pixels[idx + 2] = b
                    pixels[idx + 3] = a
                }
            }
        }

        let pixelData = Data(bytes: pixels, count: byteCount)
        guard let image = cgImage(from: pixelData, width: size, height: size) else { return nil }
        return pngData(from: image)
    }

    /// 人工輝度 (mcd/m²) から **プリマルチプライド** RGBA カラーを生成する。
    /// CGImage は premultipliedLast で作成するため RGB に alpha を乗算する。
    private static func bortleToRGBA(_ brightness: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let naturalSky = 0.172  // mcd/m²
        let ratio = brightness / naturalSky
        if ratio < 0.01 { return (0, 0, 0, 0) }   // 真の暗天 → 透明

        let alpha = 180.0 / 255.0   // 半透明係数
        let a = UInt8(180)

        // 各カラーは straight alpha 値に alpha を掛けてプリマルチプライドに変換
        func premul(_ v: Double) -> UInt8 { UInt8(min(255, (v * alpha).rounded())) }

        switch ratio {
        case ..<0.03:  return (premul(20),  premul(20),  premul(60),  a)   // Bortle 2
        case ..<0.10:  return (premul(0),   premul(0),   premul(140), a)   // Bortle 3
        case ..<0.30:  return (premul(0),   premul(100), premul(0),   a)   // Bortle 4
        case ..<1.0:   return (premul(150), premul(175), premul(30),  a)   // Bortle 5
        case ..<3.0:   return (premul(255), premul(230), premul(0),   a)   // Bortle 6
        case ..<9.0:   return (premul(255), premul(140), premul(0),   a)   // Bortle 7
        case ..<27.0:  return (premul(220), premul(30),  premul(30),  a)   // Bortle 8
        default:       return (premul(255), premul(20),  premul(147), a)   // Bortle 9 (deep pink)
        }
    }

    /// 1×1 ピクセルの透明 PNG（バンドルデータなし時のプレースホルダー）。
    private static let _transparentTileCache: Data = {
        let pixels = Data(count: 4)
        guard let image = cgImage(from: pixels, width: 1, height: 1),
              let data = pngData(from: image) else { return Data() }
        return data
    }()

    static func transparentTileData() -> Data { _transparentTileCache }

    private static func cgImage(from pixelData: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: pixelData as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }
}
