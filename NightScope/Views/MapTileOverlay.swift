import MapKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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

/// 非 Sendable な completion handler をバックグラウンド描画から安全に呼ぶためのラッパー。
final class TileLoadCompletion: @unchecked Sendable {
    private let callback: (Data?, Error?) -> Void

    init(_ callback: @escaping (Data?, Error?) -> Void) {
        self.callback = callback
    }

    func call(data: Data?, error: Error?) {
        callback(data, error)
    }
}

struct RenderedLightPollutionTile {
    let data: Data
    let image: CGImage
}

// MARK: - LightPollutionTileOverlay

final class LightPollutionTileOverlay: MKTileOverlay {

    private enum OverlayConfig {
        static let minimumZoomLevel = 1
        static let maximumZoomLevel = 12   // バンドルデータの解像度に合わせて上限を設定
        static let tilePixelSize = 256
    }

    let tileService: LightPollutionTileService

    /// Falchi Atlas バンドルデータ（LightPollutionService と同じインスタンスを使う）
    private let bortleGrid: BortleGridData?

    /// タイルレンダリングの同時実行数を制限するキュー
    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        queue.qualityOfService = .utility
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
        // キャッシュ確認（メモリ or ディスク）
        if let cached = tileService.cachedTileData(for: path) {
            result(cached, nil)
            return
        }
        guard let grid = bortleGrid else {
            // バンドルデータなし → 透明タイルを返す
            result(Self.transparentTileData(), nil)
            return
        }
        // バックグラウンドでタイルをレンダリングしてキャッシュに保存
        let tileService = self.tileService
        let completion = TileLoadCompletion(result)
        Self.renderQueue.addOperation {
            let renderedTile = Self.renderedTile(path: path, grid: grid, size: OverlayConfig.tilePixelSize)
            if let renderedTile {
                tileService.storeRenderedTile(renderedTile, for: path)
            }
            completion.call(data: renderedTile?.data, error: nil)
        }
    }

    // MKTileOverlay のデフォルト実装との互換性のために残す（実際には使われない）
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
        renderedTile(path: path, grid: grid, size: size)?.data
    }

    static func renderedTile(path: MKTileOverlayPath, grid: BortleGridData, size: Int) -> RenderedLightPollutionTile? {
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
            let longitudeSamples = (0..<size).map { px in
                let lon = minLon + lonSpan * (Double(px) + 0.5) / sizeD
                let lonF = (lon + 180.0) / 360.0 * Double(lonCells)
                let lon0 = clampedIndex(Int(lonF), upperBound: lonCells)
                let lon1 = clampedIndex(lon0 + 1, upperBound: lonCells)
                return LongitudeSample(lon0: lon0, lon1: lon1, fraction: lonF - Double(lon0))
            }

            for py in 0..<size {
                // メルカトル Y 空間で線形補間し、緯度に変換（ピクセル中心サンプリング）
                let mercY = mercYTop + (mercYBottom - mercYTop) * (Double(py) + 0.5) / sizeD
                let lat = atan(sinh(mercY)) * 180.0 / .pi
                let latF = (lat + 90.0) / 180.0 * Double(latCells)
                let lat0 = clampedIndex(Int(latF), upperBound: latCells)
                let lat1 = clampedIndex(lat0 + 1, upperBound: latCells)
                let dt = latF - Double(lat0)
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
        guard let image = cgImage(from: pixelData, width: size, height: size) else {
            return nil
        }
        let data = pngData(from: image) ?? Data()
        return RenderedLightPollutionTile(data: data, image: image)
    }

    /// 人工輝度 (mcd/m²) から RGBA カラーを生成する。
    /// Falchi Atlas の標準カラーマップに準拠。
    private static func bortleToRGBA(_ brightness: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let naturalSky = 0.172  // mcd/m²
        let ratio = brightness / naturalSky
        if ratio < 0.01 { return (0, 0, 0, 0) }   // 真の暗天 → 透明

        let alpha: UInt8 = 180  // 半透明

        switch ratio {
        case ..<0.03:  return (20,  20,  60,  alpha)    // Bortle 2: 非常に濃い青
        case ..<0.10:  return (0,   0,   140, alpha)    // Bortle 3: 濃い青
        case ..<0.30:  return (0,   100, 0,   alpha)    // Bortle 4: 濃い緑
        case ..<1.0:   return (150, 175, 30,  alpha)    // Bortle 5: 黄緑
        case ..<3.0:   return (255, 230, 0,   alpha)    // Bortle 6: 黄
        case ..<9.0:   return (255, 140, 0,   alpha)    // Bortle 7: オレンジ
        case ..<27.0:  return (220, 30,  30,  alpha)    // Bortle 8: 赤
        default:       return (255, 255, 255, alpha)    // Bortle 9: 白
        }
    }

    /// 1×1 ピクセルの透明 PNG を返す（バンドルデータなし時のプレースホルダー）。
    private static let _transparentTileCache: Data = {
        let pixels: [UInt8] = Array(repeating: 0, count: 4)
        return pixels.withUnsafeBytes { ptr in
            let pixelData = Data(bytes: ptr.baseAddress!, count: ptr.count)
            guard let image = cgImage(from: pixelData, width: 1, height: 1) else {
                return Data()
            }
            return pngData(from: image) ?? Data()
        }
    }()

    static func transparentTileData() -> Data { _transparentTileCache }

    private static func cgImage(from pixelData: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              )
        else {
            return nil
        }
        return cgImage
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

// MARK: - LightPollutionTileRenderer

/// 光害タイルのカスタムレンダラー。
/// キャッシュミスのタイルが読み込まれるまでの間、低ズームのキャッシュ済みタイルを
/// スケールアップしてフォールバック描画し、ズーム時の空白（ちらつき）を防ぐ。
final class LightPollutionTileRenderer: MKTileOverlayRenderer {

    private enum FallbackConfig {
        static let minimumZoomLevel = 1
        static let maxAncestorDepth = 4
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // alpha=0（非表示）のときは一切描画しない。super.draw() が非ゼロ alpha を要求するため。
        guard alpha > 0 else { return }
        guard let tileService else {
            super.draw(mapRect, zoomScale: zoomScale, in: context)
            return
        }

        guard let path = tilePath(for: mapRect, zoomScale: zoomScale) else {
            super.draw(mapRect, zoomScale: zoomScale, in: context)
            return
        }

        let tileLoaded = tileService.hasTileData(for: path)

        if !tileLoaded {
            // loadTile 未完了：super.draw() はタイルデータなしで alpha=0 fill を試みアサーションが発生する。
            // フォールバック描画のみ行い、loadTile 完了後の再描画コールで super.draw() を呼ぶ。
            drawFallback(for: path, mapRect: mapRect, in: context)
            return
        }

        if let image = resolveCachedImage(for: path) {
            drawImage(image, in: mapRect, context: context)
            return
        }

        // タイルロード済みだが画像キャッシュがまだ用意できていない場合のみフォールバック→既存描画へ戻す
        drawFallback(for: path, mapRect: mapRect, in: context)
        super.draw(mapRect, zoomScale: zoomScale, in: context)
    }

    /// mapRect + zoomScale から対応するタイルパスを算出
    private func tilePath(for mapRect: MKMapRect, zoomScale: MKZoomScale) -> MKTileOverlayPath? {
        let worldWidth = MKMapRect.world.size.width
        let tileSize = (overlay as? MKTileOverlay)?.tileSize.width ?? 256.0
        let z = max(1, Int(floor(log2(worldWidth * Double(zoomScale) / tileSize))))
        guard let tileOverlay = overlay as? LightPollutionTileOverlay else { return nil }
        let clampedZ = min(z, tileOverlay.maximumZ)
        guard clampedZ >= tileOverlay.minimumZ else { return nil }
        let n = pow(2.0, Double(clampedZ))
        let x = max(0, min(Int(n) - 1, Int(mapRect.minX / worldWidth * n)))
        let y = max(0, min(Int(n) - 1, Int(mapRect.minY / worldWidth * n)))
        return MKTileOverlayPath(x: x, y: y, z: clampedZ, contentScaleFactor: 1)
    }

    /// 低ズームのキャッシュ済みタイルをサブ領域切り出し＋スケールアップして描画
    private func drawFallback(for path: MKTileOverlayPath, mapRect: MKMapRect, in context: CGContext) {
        guard let tileService else { return }

        // クロップ済み画像が既にキャッシュされていれば即描画（2フレーム目以降はゼロコスト）
        if let cached = tileService.cachedImage(for: path) {
            drawImage(cached, in: mapRect, context: context)
            return
        }

        // 親ズームのタイルを探してクロップ（dz=1,2 は preCropDescendants でほぼヒット）
        for dz in 1...FallbackConfig.maxAncestorDepth {
            guard let parentPath = parentPath(for: path, dz: dz) else { break }
            guard let parentImage = resolveCachedImage(for: parentPath) else { continue }
            let srcRect = cropRect(for: path, dz: dz, image: parentImage)
            guard let cropped = parentImage.cropping(to: srcRect) else { continue }

            tileService.cacheCroppedImage(cropped, for: path)
            drawImage(cropped, in: mapRect, context: context)
            break
        }
    }

    private var tileService: LightPollutionTileService? {
        (overlay as? LightPollutionTileOverlay)?.tileService
    }

    private func parentPath(for path: MKTileOverlayPath, dz: Int) -> MKTileOverlayPath? {
        let parentZ = path.z - dz
        guard parentZ >= FallbackConfig.minimumZoomLevel else { return nil }
        let parentX = path.x >> dz
        let parentY = path.y >> dz
        return MKTileOverlayPath(x: parentX, y: parentY, z: parentZ, contentScaleFactor: 1)
    }

    private func resolveCachedImage(for path: MKTileOverlayPath) -> CGImage? {
        guard let tileService else { return nil }
        return tileService.cachedImage(for: path) ?? tileService.decodeImageFromMemoryIfNeeded(for: path)
    }

    private func cropRect(for path: MKTileOverlayPath, dz: Int, image: CGImage) -> CGRect {
        let scale = 1 << dz
        let divisions = CGFloat(scale)
        let subX = CGFloat(path.x % scale)
        let subY = CGFloat(path.y % scale)
        let tileW = CGFloat(image.width) / divisions
        let tileH = CGFloat(image.height) / divisions
        return CGRect(x: subX * tileW, y: subY * tileH, width: tileW, height: tileH)
    }

    private func drawImage(_ image: CGImage, in mapRect: MKMapRect, context: CGContext) {
        let drawRect = rect(for: mapRect)
        context.saveGState()
        context.setAlpha(alpha)
        context.interpolationQuality = .medium
        context.draw(image, in: drawRect)
        context.restoreGState()
    }
}
