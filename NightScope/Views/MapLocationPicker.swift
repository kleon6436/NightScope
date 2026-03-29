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

// MARK: - CGImageBox

/// NSCache に CGImage を格納するための参照型ラッパー。
final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

// MARK: - LightPollutionTileOverlay

final class LightPollutionTileOverlay: MKTileOverlay {

    // Cache-Control: no-store を無視してタイルを保存する独自ディスクキャッシュ
    private static let diskCacheDir: URL = {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LightPollutionTiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // ネットワークリクエスト専用セッション（URLCache は Cache-Control: no-store を尊重するため使用しない）
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // ズーム中のちらつきを抑えるメモリキャッシュ（ディスクI/Oより高速に即返す）
    // LightPollutionTileRenderer からもアクセスするため internal
    static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB（ズーム前後のタイルを保持）
        return cache
    }()

    // レンダースレッドでの PNG デコードを排除するため、デコード済み CGImage を別途キャッシュ
    // LightPollutionTileRenderer からもアクセスするため internal
    static let cgImageCache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.totalCostLimit = 80 * 1024 * 1024  // 80MB（ピクセル数ベースのコスト管理）
        return cache
    }()

    /// CGImage のメモリコスト（ピクセル数 × 4 byte RGBA）を返す。
    static func cgImageCost(_ image: CGImage) -> Int { image.width * image.height * 4 }

    /// PNG データをデコードして自タイルを cgImageCache に格納し、CGImage を返す。
    /// drawFallback が先に低品質クロップを書き込んでいても実タイルで上書きする。
    private static func decodeAndCache(data: Data, forKey key: NSString) -> CGImage? {
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        cgImageCache.setObject(CGImageBox(cgImage), forKey: key, cost: cgImageCost(cgImage))
        return cgImage
    }

    /// z+1〜z+2 の子孫タイルを実タイルから切り出してキャッシュする。
    /// drawFallback が先に低品質な祖先クロップを書き込んでいた場合も実タイル品質で上書きする。
    /// バックグラウンドスレッドから呼び出すこと。
    private static func preCropDescendants(from cgImage: CGImage, path: MKTileOverlayPath) {
        for dz in 1...2 {
            let childZ = path.z + dz
            guard childZ <= 19 else { break }
            let scale = 1 << dz
            let baseX = path.x * scale
            let baseY = path.y * scale
            let divisions = CGFloat(scale)
            let tileW = CGFloat(cgImage.width) / divisions
            let tileH = CGFloat(cgImage.height) / divisions
            for dy in 0..<scale {
                for dx in 0..<scale {
                    let childKey = "\(childZ)_\(baseX + dx)_\(baseY + dy)" as NSString
                    let srcRect = CGRect(x: CGFloat(dx) * tileW, y: CGFloat(dy) * tileH,
                                        width: tileW, height: tileH)
                    if let cropped = cgImage.cropping(to: srcRect) {
                        cgImageCache.setObject(CGImageBox(cropped), forKey: childKey,
                                               cost: cgImageCost(cropped))
                    }
                }
            }
        }
    }

    override init(urlTemplate: String?) {
        super.init(urlTemplate: urlTemplate)
        canReplaceMapContent = false
        minimumZ = 1
        maximumZ = 19
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let cacheKey = "\(path.z)_\(path.x)_\(path.y)" as NSString

        // 1: メモリキャッシュに存在すれば即返す
        if let cached = Self.memoryCache.object(forKey: cacheKey) {
            // cgImageCache が evict されていた場合はバックグラウンドで再構築
            if Self.cgImageCache.object(forKey: cacheKey) == nil {
                let data = cached as Data
                Task.detached(priority: .utility) {
                    if let img = Self.decodeAndCache(data: data, forKey: cacheKey) {
                        Self.preCropDescendants(from: img, path: path)
                    }
                }
            }
            result(cached as Data, nil)
            return
        }

        // 2: ディスクキャッシュを確認
        let diskURL = Self.diskCacheDir.appendingPathComponent("\(cacheKey).png")
        if let diskData = try? Data(contentsOf: diskURL, options: .mappedIfSafe) {
            Self.memoryCache.setObject(diskData as NSData, forKey: cacheKey, cost: diskData.count)
            // 自タイルのデコードは result() 前に完了させ、子孫クロップは result() 後にバックグラウンドへ
            let img = Self.decodeAndCache(data: diskData, forKey: cacheKey)
            result(diskData, nil)
            if let img {
                Task.detached(priority: .utility) {
                    Self.preCropDescendants(from: img, path: path)
                }
            }
            return
        }

        // 3: ネットワークから取得してキャッシュに保存
        let request = URLRequest(url: url(forTilePath: path), timeoutInterval: 15)
        Self.session.dataTask(with: request) { data, response, error in
            guard let data, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                result(data, error)
                return
            }
            Self.memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            // 自タイルのデコードは result() 前に完了させ、子孫クロップは result() 後にバックグラウンドへ
            let img = Self.decodeAndCache(data: data, forKey: cacheKey)
            try? data.write(to: diskURL, options: .atomic)
            result(data, nil)
            if let img {
                Task.detached(priority: .utility) {
                    Self.preCropDescendants(from: img, path: path)
                }
            }
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

// MARK: - LightPollutionTileRenderer

/// 光害タイルのカスタムレンダラー。
/// キャッシュミスのタイルが読み込まれるまでの間、低ズームのキャッシュ済みタイルを
/// スケールアップしてフォールバック描画し、ズーム時の空白（ちらつき）を防ぐ。
final class LightPollutionTileRenderer: MKTileOverlayRenderer {

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // alpha=0（非表示）のときは一切描画しない。super.draw() が非ゼロ alpha を要求するため。
        guard alpha > 0 else { return }

        guard let path = tilePath(for: mapRect, zoomScale: zoomScale) else {
            super.draw(mapRect, zoomScale: zoomScale, in: context)
            return
        }

        let key = "\(path.z)_\(path.x)_\(path.y)" as NSString
        let tileLoaded = LightPollutionTileOverlay.memoryCache.object(forKey: key) != nil

        if !tileLoaded {
            // loadTile 未完了：super.draw() はタイルデータなしで alpha=0 fill を試みアサーションが発生する。
            // フォールバック描画のみ行い、loadTile 完了後の再描画コールで super.draw() を呼ぶ。
            drawFallback(for: path, mapRect: mapRect, in: context)
            return
        }

        // タイルロード済み：cgImageCache 未デコードならフォールバックで補完してから正規描画
        if LightPollutionTileOverlay.cgImageCache.object(forKey: key) == nil {
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
        let selfKey = "\(path.z)_\(path.x)_\(path.y)" as NSString

        // クロップ済み画像が既にキャッシュされていれば即描画（2フレーム目以降はゼロコスト）
        if let box = LightPollutionTileOverlay.cgImageCache.object(forKey: selfKey) {
            drawImage(box.image, in: mapRect, context: context)
            return
        }

        // 親ズームのタイルを探してクロップ（dz=1,2 は preCropDescendants でほぼヒット）
        for dz in 1...4 {
            let parentZ = path.z - dz
            guard parentZ >= 1 else { break }
            let parentX = path.x >> dz
            let parentY = path.y >> dz
            let parentKey = "\(parentZ)_\(parentX)_\(parentY)" as NSString

            // CGImage キャッシュを優先（PNG デコード不要・レンダースレッドをブロックしない）
            let parentImage: CGImage
            if let box = LightPollutionTileOverlay.cgImageCache.object(forKey: parentKey) {
                parentImage = box.image
            } else if let nsData = LightPollutionTileOverlay.memoryCache.object(forKey: parentKey) as Data?,
                      let nsImage = NSImage(data: nsData),
                      let img = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                LightPollutionTileOverlay.cgImageCache.setObject(
                    CGImageBox(img), forKey: parentKey,
                    cost: LightPollutionTileOverlay.cgImageCost(img))
                parentImage = img
            } else {
                continue
            }

            // 親タイル内の対応サブ領域（ピクセル座標）を算出
            let divisions = CGFloat(1 << dz)
            let subX = CGFloat(path.x % (1 << dz))
            let subY = CGFloat(path.y % (1 << dz))
            let tileW = CGFloat(parentImage.width) / divisions
            let tileH = CGFloat(parentImage.height) / divisions
            let srcRect = CGRect(x: subX * tileW, y: subY * tileH, width: tileW, height: tileH)
            guard let cropped = parentImage.cropping(to: srcRect) else { continue }

            // 次フレーム以降はクロップ不要にするためキャッシュ（実タイル到着時に preCropDescendants が上書きする）
            LightPollutionTileOverlay.cgImageCache.setObject(
                CGImageBox(cropped), forKey: selfKey,
                cost: LightPollutionTileOverlay.cgImageCost(cropped))
            drawImage(cropped, in: mapRect, context: context)
            break
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
                .frame(minHeight: 160, maxHeight: 280)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Layout.mapCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.mapCornerRadius)
                        .stroke(.separator, lineWidth: Layout.mapSeparatorLineWidth)
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
    /// 現在地取得成功時にインクリメントされるトリガー（変化時のみマップをセンタリング）
    let centerTrigger: Int

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
        // nsView.renderer(for:) で常に最新のレンダラーを取得し、古い参照による消失を防ぐ
        let targetAlpha: CGFloat = showLightPollution ? 0.8 : 0.0
        if let overlay = nsView.overlays.first(where: { $0 is LightPollutionTileOverlay }),
           let renderer = nsView.renderer(for: overlay) as? LightPollutionTileRenderer {
            if renderer.alpha != targetAlpha {
                renderer.alpha = targetAlpha
                renderer.setNeedsDisplay(MKMapRect.world)
            }
        }

        let existing = nsView.annotations.compactMap { $0 as? MKPointAnnotation }.first

        guard let newCoord = pinCoordinate else {
            if existing != nil { nsView.removeAnnotations(nsView.annotations) }
            return
        }

        // タブ切り替えによる外部ビューポート同期（最優先）
        if context.coordinator.lastSyncTrigger != syncState.trigger {
            context.coordinator.lastSyncTrigger = syncState.trigger
            // suppressRegionChangeCount は使わない: 同期 setRegion が MKMapView に変化をもたらさない場合
            // regionDidChangeAnimated が発火せずカウントが残り、次のユーザー操作を誤抑制するため。
            // onRegionChange で viewport に同じ値が書き戻されても実害はない。
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

        // 通常のピン位置更新（マップのビューポートは変更しない）
        if let existing {
            let coordChanged = existing.coordinate.latitude != newCoord.latitude ||
                               existing.coordinate.longitude != newCoord.longitude
            if coordChanged { existing.coordinate = newCoord }
        } else {
            let ann = MKPointAnnotation()
            ann.coordinate = newCoord
            nsView.addAnnotation(ann)
        }

        // 現在地ボタンで取得した座標のときだけセンタリング
        // suppressRegionChangeCount は使わない → onRegionChange で viewport が更新されタブ同期が維持される
        if context.coordinator.lastCenterTrigger != centerTrigger {
            context.coordinator.lastCenterTrigger = centerTrigger
            let region = MKCoordinateRegion(center: newCoord, span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
            Task { @MainActor in nsView.setRegion(region, animated: true) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitViewRepresentable
        var lastSyncTrigger: Int
        var lastCenterTrigger: Int
        /// syncState.trigger による setRegion 後に regionDidChangeAnimated を抑制するカウンタ
        var suppressRegionChangeCount = 0
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
            if suppressRegionChangeCount > 0 {
                suppressRegionChangeCount -= 1
                return
            }
            parent.onRegionChange(mapView.region.center, mapView.region.span)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? LightPollutionTileOverlay {
                let renderer = LightPollutionTileRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.showLightPollution ? 0.8 : 0.0
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
    var centerTrigger: Int = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedCoordinate.latitude == rhs.selectedCoordinate.latitude &&
        lhs.selectedCoordinate.longitude == rhs.selectedCoordinate.longitude &&
        lhs.isVisible == rhs.isVisible &&
        lhs.syncState == rhs.syncState &&
        lhs.showLightPollution == rhs.showLightPollution &&
        lhs.isLocating == rhs.isLocating &&
        lhs.centerTrigger == rhs.centerTrigger
    }

    var body: some View {
        MapContainerView {
            MapKitViewRepresentable(
                pinCoordinate: selectedCoordinate,
                onTap: { coord in onSelect(coord) },
                isVisible: isVisible,
                syncState: syncState,
                onRegionChange: onRegionChange,
                showLightPollution: showLightPollution,
                centerTrigger: centerTrigger
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
                                    .font(.system(size: Layout.mapIconSize))
                            }
                        }
                        .frame(width: Layout.mapButtonSize, height: Layout.mapButtonSize)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.mapButtonCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.xs)
                    .disabled(isLocating)
                    .accessibilityLabel("現在地を取得")
                }
            }
        }
    }
}
