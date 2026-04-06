import MapKit

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
        static let maximumZoomLevel = 19
        static let tilePixelSize = 256
        static let worldMeters = 40075016.685578488
        static let worldOriginShift = 20037508.342789244
    }

    let tileService: LightPollutionTileService

    override init(urlTemplate: String?) {
        self.tileService = .shared
        super.init(urlTemplate: urlTemplate)
        canReplaceMapContent = false
        minimumZ = OverlayConfig.minimumZoomLevel
        maximumZ = OverlayConfig.maximumZoomLevel
    }

    init(urlTemplate: String?, tileService: LightPollutionTileService) {
        self.tileService = tileService
        super.init(urlTemplate: urlTemplate)
        canReplaceMapContent = false
        minimumZ = OverlayConfig.minimumZoomLevel
        maximumZ = OverlayConfig.maximumZoomLevel
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        tileService.loadTile(path: path, url: url(forTilePath: path), result: result)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let (minX, minY, maxX, maxY) = tileBounds(x: path.x, y: path.y, z: path.z)
        var comps = URLComponents(string: "https://www.lightpollutionmap.info/geoserver/gwc/service/wms")!
        comps.queryItems = [
            URLQueryItem(name: "SERVICE",     value: "WMS"),
            URLQueryItem(name: "REQUEST",     value: "GetMap"),
            URLQueryItem(name: "VERSION",     value: "1.1.1"),
            URLQueryItem(name: "LAYERS",      value: "PostGIS:WA_2015"),
            URLQueryItem(name: "STYLES",      value: "WA"),
            URLQueryItem(name: "FORMAT",      value: "image/png"),
            URLQueryItem(name: "TRANSPARENT", value: "TRUE"),
            URLQueryItem(name: "SRS",         value: "EPSG:3857"),
            URLQueryItem(name: "WIDTH",       value: "\(OverlayConfig.tilePixelSize)"),
            URLQueryItem(name: "HEIGHT",      value: "\(OverlayConfig.tilePixelSize)"),
            URLQueryItem(name: "BBOX",        value: "\(minX),\(minY),\(maxX),\(maxY)"),
        ]
        return comps.url!
    }

    // タイル座標 → EPSG:3857バウンディングボックス（GeoWebCache均一グリッド）
    private func tileBounds(x: Int, y: Int, z: Int) -> (Double, Double, Double, Double) {
        let tileSize = OverlayConfig.worldMeters / pow(2.0, Double(z))
        let minX = -OverlayConfig.worldOriginShift + Double(x) * tileSize
        let maxX = minX + tileSize
        let maxY = OverlayConfig.worldOriginShift - Double(y) * tileSize
        let minY = maxY - tileSize
        return (minX, minY, maxX, maxY)
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

        // タイルロード済み：cgImageCache 未デコードならフォールバックで補完してから正規描画
        if tileService.cachedImage(for: path) == nil {
            drawFallback(for: path, mapRect: mapRect, in: context)
        }
        super.draw(mapRect, zoomScale: zoomScale, in: context)
    }

    /// mapRect + zoomScale から対応するタイルパスを算出
    private func tilePath(for mapRect: MKMapRect, zoomScale: MKZoomScale) -> MKTileOverlayPath? {
        let worldWidth = MKMapRect.world.size.width
        let z = Int(log2(worldWidth * Double(zoomScale) / 256.0).rounded())
        guard z >= 1 else { return nil }
        let n = pow(2.0, Double(z))
        let x = max(0, min(Int(n) - 1, Int(mapRect.minX / worldWidth * n)))
        let y = max(0, min(Int(n) - 1, Int(mapRect.minY / worldWidth * n)))
        return MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: 1)
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
        context.interpolationQuality = .medium
        context.draw(image, in: drawRect)
        context.restoreGState()
    }
}
