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

    // サーバーの Cache-Control: no-store を無視してディスクキャッシュに保存する専用セッション
    private static let session: URLSession = {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LightPollutionTiles")
        let cache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: cacheDir
        )
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    // ズーム中のちらつきを抑えるメモリキャッシュ（ディスクI/Oより高速に即返す）
    private static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
        return cache
    }()

    override init(urlTemplate: String?) {
        super.init(urlTemplate: urlTemplate)
        canReplaceMapContent = false
        minimumZ = 1
        maximumZ = 19
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        // WMS は BBOX で画像を生成するため、任意のズームレベルで実際の座標をそのまま使用する
        let cacheKey = "\(path.z)/\(path.x)/\(path.y)" as NSString

        // メモリキャッシュに存在すれば即返す（ズーム中のちらつき防止）
        if let cached = Self.memoryCache.object(forKey: cacheKey) {
            result(cached as Data, nil)
            return
        }

        let request = URLRequest(
            url: url(forTilePath: path),
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 15
        )
        Self.session.dataTask(with: request) { data, _, error in
            if let data {
                Self.memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            }
            result(data, error)
        }.resume()
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
            URLQueryItem(name: "WIDTH",       value: "256"),
            URLQueryItem(name: "HEIGHT",      value: "256"),
            URLQueryItem(name: "BBOX",        value: "\(minX),\(minY),\(maxX),\(maxY)"),
        ]
        return comps.url!
    }

    // タイル座標 → EPSG:3857バウンディングボックス（GeoWebCache均一グリッド）
    private func tileBounds(x: Int, y: Int, z: Int) -> (Double, Double, Double, Double) {
        let tileSize = 40075016.685578488 / pow(2.0, Double(z))
        let minX = -20037508.342789244 + Double(x) * tileSize
        let maxX = minX + tileSize
        let maxY = 20037508.342789244 - Double(y) * tileSize
        let minY = maxY - tileSize
        return (minX, minY, maxX, maxY)
    }
}

// MARK: - MapContainerView

/// 地図ビューを包む共通コンテナ（枠線・ラベル付き）。
private struct MapContainerView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
                .frame(minHeight: 160, maxHeight: 280)
                .frame(maxHeight: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            Text("地図をクリックして場所を選択")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - NSViewRepresentable wrapper for MKMapView

struct MapKitViewRepresentable: NSViewRepresentable {
    let pinCoordinate: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void
    let isVisible: Bool
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        // カメラ距離 10km 未満へのズームインを禁止（光害タイルの解像度上限に対応）
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 100)
        // 光害オーバーレイを常駐させタブ切り替え時のタイル再描画を防ぐ（alpha で表示/非表示を切り替える）
        mapView.addOverlay(LightPollutionTileOverlay(urlTemplate: nil), level: .aboveRoads)
        if let coord = pinCoordinate {
            DispatchQueue.main.async {
                mapView.setRegion(
                    MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
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

        // alpha で光害オーバーレイの表示/非表示を切り替える（削除・再追加しない）
        let targetAlpha: CGFloat = showLightPollution ? 0.8 : 0.0
        if let renderer = context.coordinator.tileRenderer, renderer.alpha != targetAlpha {
            renderer.alpha = targetAlpha
            renderer.setNeedsDisplay(MKMapRect.world)
        }

        let existing = nsView.annotations.compactMap { $0 as? MKPointAnnotation }.first

        guard let newCoord = pinCoordinate else {
            if existing != nil { nsView.removeAnnotations(nsView.annotations) }
            return
        }

        // タブ切り替えによる外部ビューポート同期（最優先）
        if context.coordinator.lastSyncTrigger != syncState.trigger {
            context.coordinator.lastSyncTrigger = syncState.trigger
            context.coordinator.suppressRegionChangeCount += 1
            if let existing {
                existing.coordinate = newCoord
            } else {
                let ann = MKPointAnnotation()
                ann.coordinate = newCoord
                nsView.addAnnotation(ann)
            }
            let region = MKCoordinateRegion(center: syncState.center, span: syncState.span)
            DispatchQueue.main.async { nsView.setRegion(region, animated: false) }
            return
        }

        // 通常のピン位置更新
        if let existing {
            let coordChanged = existing.coordinate.latitude != newCoord.latitude ||
                               existing.coordinate.longitude != newCoord.longitude
            if coordChanged { existing.coordinate = newCoord }
            if coordChanged && isVisible {
                let region = MKCoordinateRegion(center: newCoord, span: nsView.region.span)
                DispatchQueue.main.async { nsView.setRegion(region, animated: true) }
            }
        } else {
            let ann = MKPointAnnotation()
            ann.coordinate = newCoord
            nsView.addAnnotation(ann)
            if isVisible {
                let region = MKCoordinateRegion(
                    center: newCoord,
                    span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
                )
                DispatchQueue.main.async { nsView.setRegion(region, animated: true) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitViewRepresentable
        var lastSyncTrigger: Int
        /// syncState.trigger による setRegion 後に regionDidChangeAnimated を抑制するカウンタ
        var suppressRegionChangeCount = 0
        /// 光害タイルレンダラーへの参照（alpha 制御用）
        var tileRenderer: MKTileOverlayRenderer?

        init(_ parent: MapKitViewRepresentable) {
            self.parent = parent
            self.lastSyncTrigger = parent.syncState.trigger
        }

        @objc func handleTap(_ gr: NSClickGestureRecognizer) {
            guard let mapView = gr.view as? MKMapView else { return }
            let point = gr.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if suppressRegionChangeCount > 0 {
                suppressRegionChangeCount -= 1
                return
            }
            parent.onRegionChange(mapView.region.center, mapView.region.span)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? LightPollutionTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.showLightPollution ? 0.8 : 0.0
                tileRenderer = renderer
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
    let isVisible: Bool
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool
    var onCurrentLocation: (() -> Void)? = nil
    var isLocating: Bool = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedCoordinate.latitude == rhs.selectedCoordinate.latitude &&
        lhs.selectedCoordinate.longitude == rhs.selectedCoordinate.longitude &&
        lhs.isVisible == rhs.isVisible &&
        lhs.syncState == rhs.syncState &&
        lhs.showLightPollution == rhs.showLightPollution &&
        lhs.isLocating == rhs.isLocating
    }

    var body: some View {
        MapContainerView {
            MapKitViewRepresentable(
                pinCoordinate: selectedCoordinate,
                onTap: { coord in onSelect(coord) },
                isVisible: isVisible,
                syncState: syncState,
                onRegionChange: onRegionChange,
                showLightPollution: showLightPollution
            )
            .overlay(alignment: .bottomTrailing) {
                if let onCurrentLocation {
                    Button {
                        onCurrentLocation()
                    } label: {
                        Group {
                            if isLocating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14))
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .disabled(isLocating)
                    .accessibilityLabel("現在地を取得")
                }
            }
        }
    }
}
