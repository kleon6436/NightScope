import SwiftUI
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

// MARK: - MapContainerView

/// 地図ビューを包む共通コンテナ（枠線・ラベル付き）。
private struct MapContainerView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private var verticalSpacing: CGFloat { 4 }
    private var minMapHeight: CGFloat { 160 }
    private var maxMapHeight: CGFloat { 280 }
    private var instructionText: String { "地図をクリックして場所を選択" }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            mapSurface
            instructionLabel
        }
    }

    private var mapSurface: some View {
        content()
            .frame(minHeight: minMapHeight, maxHeight: maxMapHeight)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Layout.mapCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.mapCornerRadius)
                    .stroke(.separator, lineWidth: Layout.mapSeparatorLineWidth)
            )
    }

    private var instructionLabel: some View {
        Text(instructionText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - NSViewRepresentable wrapper for MKMapView

struct MapKitViewRepresentable: NSViewRepresentable {
    private enum MapViewConfig {
        static let minCenterCoordinateDistance: CLLocationDistance = 100
        static let visibleOverlayAlpha: CGFloat = 0.8
        static let hiddenOverlayAlpha: CGFloat = 0.0
        static let initialPinLatitudeDelta: CLLocationDegrees = 0.05
        static let initialPinLongitudeDelta: CLLocationDegrees = 0.05
        static let currentLocationLatitudeDelta: CLLocationDegrees = 0.5
        static let currentLocationLongitudeDelta: CLLocationDegrees = 0.5
    }

    let pinCoordinate: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool
    /// 現在地取得成功時にインクリメントされるトリガー（変化時のみマップをセンタリング）
    let centerTrigger: Int

    private var overlayAlpha: CGFloat {
        showLightPollution ? MapViewConfig.visibleOverlayAlpha : MapViewConfig.hiddenOverlayAlpha
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        // カメラ距離 10km 未満へのズームインを禁止（光害タイルの解像度上限に対応）
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: MapViewConfig.minCenterCoordinateDistance)
        // 光害オーバーレイを常駐させタブ切り替え時のタイル再描画を防ぐ（alpha で表示/非表示を切り替える）
        mapView.addOverlay(LightPollutionTileOverlay(urlTemplate: nil), level: .aboveRoads)
        if let coord = pinCoordinate {
            DispatchQueue.main.async {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(
                            latitudeDelta: MapViewConfig.initialPinLatitudeDelta,
                            longitudeDelta: MapViewConfig.initialPinLongitudeDelta
                        )
                    ),
                    animated: false
                )
            }
        }
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(click)
        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.parent = self
        updateLightPollutionOverlayAlpha(on: nsView)

        let existing = currentPinAnnotation(in: nsView)

        guard let newCoord = pinCoordinate else {
            removeAnnotationsIfNeeded(from: nsView, existing: existing)
            return
        }

        if applyViewportSyncIfNeeded(
            on: nsView,
            existing: existing,
            coordinate: newCoord,
            coordinator: context.coordinator
        ) {
            return
        }

        upsertPinAnnotation(on: nsView, existing: existing, coordinate: newCoord)
        centerOnCurrentLocationIfNeeded(on: nsView, coordinate: newCoord, coordinator: context.coordinator)
    }

    private func updateLightPollutionOverlayAlpha(on mapView: MKMapView) {
        let targetAlpha = overlayAlpha
        if let overlay = mapView.overlays.first(where: { $0 is LightPollutionTileOverlay }),
           let renderer = mapView.renderer(for: overlay) as? LightPollutionTileRenderer,
           renderer.alpha != targetAlpha {
            renderer.alpha = targetAlpha
            renderer.setNeedsDisplay(MKMapRect.world)
        }
    }

    private func currentPinAnnotation(in mapView: MKMapView) -> MKPointAnnotation? {
        mapView.annotations.compactMap { $0 as? MKPointAnnotation }.first
    }

    private func removeAnnotationsIfNeeded(from mapView: MKMapView, existing: MKPointAnnotation?) {
        if existing != nil {
            mapView.removeAnnotations(mapView.annotations)
        }
    }

    private func applyViewportSyncIfNeeded(
        on mapView: MKMapView,
        existing: MKPointAnnotation?,
        coordinate: CLLocationCoordinate2D,
        coordinator: Coordinator
    ) -> Bool {
        guard coordinator.lastSyncTrigger != syncState.trigger else {
            return false
        }

        coordinator.lastSyncTrigger = syncState.trigger
        upsertPinAnnotation(on: mapView, existing: existing, coordinate: coordinate)
        let region = MKCoordinateRegion(center: syncState.center, span: syncState.span)
        DispatchQueue.main.async { mapView.setRegion(region, animated: false) }
        return true
    }

    private func upsertPinAnnotation(
        on mapView: MKMapView,
        existing: MKPointAnnotation?,
        coordinate: CLLocationCoordinate2D
    ) {
        if let existing {
            let coordChanged = !coordinatesEqual(existing.coordinate, coordinate)
            if coordChanged {
                existing.coordinate = coordinate
            }
            return
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    private func coordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    private func centerOnCurrentLocationIfNeeded(
        on mapView: MKMapView,
        coordinate: CLLocationCoordinate2D,
        coordinator: Coordinator
    ) {
        guard coordinator.lastCenterTrigger != centerTrigger else {
            return
        }

        coordinator.lastCenterTrigger = centerTrigger
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: MapViewConfig.currentLocationLatitudeDelta,
                longitudeDelta: MapViewConfig.currentLocationLongitudeDelta
            )
        )
        Task { @MainActor in
            mapView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitViewRepresentable
        var lastSyncTrigger: Int
        var lastCenterTrigger: Int

        init(_ parent: MapKitViewRepresentable) {
            self.parent = parent
            self.lastSyncTrigger = parent.syncState.trigger
            self.lastCenterTrigger = parent.centerTrigger
        }

        @objc func handleTap(_ gr: NSClickGestureRecognizer) {
            guard let mapView = gr.view as? MKMapView else { return }
            let point = gr.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region.center, mapView.region.span)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? LightPollutionTileOverlay {
                let renderer = LightPollutionTileRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.overlayAlpha
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - MapLocationPicker view

struct MapLocationPicker: View, Equatable {
    let selectedCoordinate: CLLocationCoordinate2D
    let onSelect: (CLLocationCoordinate2D) -> Void
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool
    var onCurrentLocation: (() -> Void)? = nil
    var isLocating: Bool = false
    var centerTrigger: Int = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        coordinatesEqual(lhs.selectedCoordinate, rhs.selectedCoordinate) &&
        lhs.syncState == rhs.syncState &&
        lhs.showLightPollution == rhs.showLightPollution &&
        lhs.isLocating == rhs.isLocating &&
        lhs.centerTrigger == rhs.centerTrigger
    }

    private static func coordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    var body: some View {
        MapContainerView {
            mapViewContent
        }
    }

    private var mapViewContent: some View {
        MapKitViewRepresentable(
            pinCoordinate: selectedCoordinate,
            onTap: onSelect,
            syncState: syncState,
            onRegionChange: onRegionChange,
            showLightPollution: showLightPollution,
            centerTrigger: centerTrigger
        )
        .overlay(alignment: .bottomTrailing) {
            currentLocationOverlay
        }
    }

    @ViewBuilder
    private var currentLocationOverlay: some View {
        if let onCurrentLocation {
            Button(action: onCurrentLocation) {
                currentLocationButtonLabel
            }
            .buttonStyle(.plain)
            .padding(Spacing.xs)
            .disabled(isLocating)
            .accessibilityLabel("現在地を取得")
        }
    }

    @ViewBuilder
    private var currentLocationButtonLabel: some View {
        Group {
            if isLocating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "location.fill")
                    .font(.system(size: Layout.mapIconSize))
            }
        }
        .frame(width: Layout.mapButtonSize, height: Layout.mapButtonSize)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.mapButtonCornerRadius))
    }
}
