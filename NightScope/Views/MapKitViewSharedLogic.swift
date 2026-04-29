import MapKit

@MainActor
/// MapKit の同期・オーバーレイ更新ロジックを共有するための補助 API。
enum MapKitViewSharedLogic {
    private enum Config {
        static let minCenterCoordinateDistance: CLLocationDistance = 100
        static let visibleOverlayAlpha: CGFloat = 0.8
        static let hiddenOverlayAlpha: CGFloat = 0.0
        static let initialPinLatitudeDelta: CLLocationDegrees = 0.05
        static let initialPinLongitudeDelta: CLLocationDegrees = 0.05
        static let currentLocationLatitudeDelta: CLLocationDegrees = 0.5
        static let currentLocationLongitudeDelta: CLLocationDegrees = 0.5
        static let minimumLongitudeMetersPerDegree = 5_000.0
    }

    struct UpdateConfiguration {
        let pinCoordinate: CLLocationCoordinate2D?
        let syncState: MapKitSyncState
        let centerTrigger: Int
        let overlayAlpha: CGFloat
        let viewingDirection: ViewingDirection?
    }

    static var minCenterCoordinateDistance: CLLocationDistance {
        Config.minCenterCoordinateDistance
    }

    static func overlayAlpha(showLightPollution: Bool) -> CGFloat {
        showLightPollution ? Config.visibleOverlayAlpha : Config.hiddenOverlayAlpha
    }

    static func setInitialRegionIfNeeded(on mapView: MKMapView, pinCoordinate: CLLocationCoordinate2D?) {
        guard let pinCoordinate = GeoStateValidator.sanitizedCoordinate(pinCoordinate),
              let region = GeoStateValidator.sanitizedRegion(
                center: pinCoordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: Config.initialPinLatitudeDelta,
                    longitudeDelta: Config.initialPinLongitudeDelta
                )
              ) else { return }
        mapView.setRegion(region, animated: false)
    }

    static func updateLightPollutionOverlayAlpha(on mapView: MKMapView, targetAlpha: CGFloat) {
        if let overlay = mapView.overlays.first(where: { $0 is LightPollutionTileOverlay }),
           let renderer = mapView.renderer(for: overlay) as? MKTileOverlayRenderer,
           renderer.alpha != targetAlpha {
            renderer.alpha = targetAlpha
        }
    }

    static func currentPinAnnotation(in mapView: MKMapView) -> MKPointAnnotation? {
        mapView.annotations.compactMap { $0 as? MKPointAnnotation }.first
    }

    static func removeAnnotationsIfNeeded(from mapView: MKMapView, existing: MKPointAnnotation?) {
        if existing != nil {
            mapView.removeAnnotations(mapView.annotations)
        }
    }

    static func upsertPinAnnotation(
        on mapView: MKMapView,
        existing: MKPointAnnotation?,
        coordinate: CLLocationCoordinate2D
    ) {
        guard let coordinate = GeoStateValidator.sanitizedCoordinate(coordinate) else {
            removeAnnotationsIfNeeded(from: mapView, existing: existing)
            return
        }

        if let existing {
            if !coordinatesEqual(existing.coordinate, coordinate) {
                existing.coordinate = coordinate
            }
            return
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    static func applyMapUpdate(
        on mapView: MKMapView,
        state: MapKitCoordinatorState,
        configuration: UpdateConfiguration
    ) {
        updateLightPollutionOverlayAlpha(on: mapView, targetAlpha: configuration.overlayAlpha)

        let existing = currentPinAnnotation(in: mapView)
        let pinCoordinate = GeoStateValidator.sanitizedCoordinate(configuration.pinCoordinate)

        guard let pinCoordinate else {
            removeAnnotationsIfNeeded(from: mapView, existing: existing)
            updateViewingDirectionOverlay(
                on: mapView,
                pinCoordinate: nil,
                viewingDirection: configuration.viewingDirection
            )
            return
        }

        if let syncRegion = state.syncedRegion(syncState: configuration.syncState) {
            upsertPinAnnotation(on: mapView, existing: existing, coordinate: pinCoordinate)
            state.scheduleRegionChange(on: mapView, region: syncRegion, animated: false)
            updateViewingDirectionOverlay(
                on: mapView,
                pinCoordinate: pinCoordinate,
                viewingDirection: configuration.viewingDirection
            )
            return
        }

        upsertPinAnnotation(on: mapView, existing: existing, coordinate: pinCoordinate)
        if let centeredRegion = state.centeredRegion(
            coordinate: pinCoordinate,
            centerTrigger: configuration.centerTrigger
        ) {
            state.scheduleRegionChange(on: mapView, region: centeredRegion, animated: true)
        }
        updateViewingDirectionOverlay(
            on: mapView,
            pinCoordinate: pinCoordinate,
            viewingDirection: configuration.viewingDirection
        )
    }

    static func applyViewportSyncIfNeeded(
        syncState: MapKitSyncState,
        lastSyncTrigger: inout Int
    ) -> MKCoordinateRegion? {
        guard lastSyncTrigger != syncState.trigger else {
            return nil
        }

        lastSyncTrigger = syncState.trigger
        return GeoStateValidator.sanitizedRegion(
            center: syncState.center,
            span: syncState.span
        )
    }

    static func centerOnCurrentLocationIfNeeded(
        coordinate: CLLocationCoordinate2D,
        centerTrigger: Int,
        lastCenterTrigger: inout Int
    ) -> MKCoordinateRegion? {
        guard lastCenterTrigger != centerTrigger else {
            return nil
        }

        lastCenterTrigger = centerTrigger
        return GeoStateValidator.sanitizedRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: Config.currentLocationLatitudeDelta,
                longitudeDelta: Config.currentLocationLongitudeDelta
            )
        )
    }

    static func consumePendingRegionChangeIgnore(_ pendingIgnoredRegionChanges: inout Int) -> Bool {
        guard pendingIgnoredRegionChanges > 0 else {
            return false
        }

        pendingIgnoredRegionChanges -= 1
        return true
    }

    fileprivate static func regionsEquivalent(
        _ lhs: MKCoordinateRegion,
        _ rhs: MKCoordinateRegion,
        tolerance: CLLocationDegrees = 0.000001
    ) -> Bool {
        abs(lhs.center.latitude - rhs.center.latitude) <= tolerance
            && abs(lhs.center.longitude - rhs.center.longitude) <= tolerance
            && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) <= tolerance
            && abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) <= tolerance
    }

    private static func coordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    // MARK: - Viewing Direction Overlay

    /// サイドバーマップ上に視野方向を示す扇形オーバーレイを更新する。
    static func updateViewingDirectionOverlay(
        on mapView: MKMapView,
        pinCoordinate: CLLocationCoordinate2D?,
        viewingDirection: ViewingDirection?
    ) {
        mapView.overlays
            .compactMap { $0 as? ViewingDirectionOverlay }
            .forEach { mapView.removeOverlay($0) }

        guard let dir = viewingDirection, dir.isActive,
              let center = pinCoordinate else { return }

        var coords = sectorCoordinates(center: center, azimuth: dir.azimuth, fov: dir.fov)
        guard coords.count >= 3 else { return }
        let overlay = ViewingDirectionOverlay(coordinates: &coords, count: coords.count)
        mapView.addOverlay(overlay, level: .aboveRoads)
    }

    private static func sectorCoordinates(
        center: CLLocationCoordinate2D,
        azimuth: Double,
        fov: Double,
        radius: Double = 2000
    ) -> [CLLocationCoordinate2D] {
        guard let sanitizedCenter = GeoStateValidator.sanitizedCoordinate(center) else { return [] }
        let lat = sanitizedCenter.latitude
        let steps = 20
        var coords = [CLLocationCoordinate2D]()
        coords.append(sanitizedCenter)
        for i in 0...steps {
            let angle = (azimuth - fov / 2) + Double(i) * fov / Double(steps)
            let angleRad = angle * .pi / 180
            let latOffset  = radius * cos(angleRad) / 111_000
            let metersPerLongitudeDegree = max(
                111_000 * abs(cos(lat * .pi / 180)),
                Config.minimumLongitudeMetersPerDegree
            )
            let lonOffset  = radius * sin(angleRad) / metersPerLongitudeDegree
            let coordinate = CLLocationCoordinate2D(
                latitude:  lat + latOffset,
                longitude: sanitizedCenter.longitude + lonOffset
            )
            if let sanitizedCoordinate = GeoStateValidator.sanitizedCoordinate(coordinate) {
                coords.append(sanitizedCoordinate)
            }
        }
        return coords
    }
}


// MARK: - ViewingDirectionOverlay

/// サイドバーマップで視野方向を示す扇形ポリゴンオーバーレイ。
final class ViewingDirectionOverlay: MKPolygon {}

/// MapKit の delegate 状態とプログラム更新の抑止を管理する。
@MainActor
final class MapKitCoordinatorState {
    private static let pendingIgnoreResetDelay: Duration = .milliseconds(500)
    private static let animatedPendingIgnoreResetDelay: Duration = .seconds(2)

    private var lastSyncTrigger: Int
    private var lastCenterTrigger: Int
    private var pendingIgnoredRegionChanges = 0
    private var latestProgrammaticRegionGeneration = 0
    private var pendingIgnoreResetTask: Task<Void, Never>?

    init(syncTrigger: Int, centerTrigger: Int) {
        self.lastSyncTrigger = syncTrigger
        self.lastCenterTrigger = centerTrigger
    }

    func syncedRegion(
        syncState: MapKitSyncState
    ) -> MKCoordinateRegion? {
        MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            syncState: syncState,
            lastSyncTrigger: &lastSyncTrigger
        )
    }

    func centeredRegion(
        coordinate: CLLocationCoordinate2D,
        centerTrigger: Int
    ) -> MKCoordinateRegion? {
        MapKitViewSharedLogic.centerOnCurrentLocationIfNeeded(
            coordinate: coordinate,
            centerTrigger: centerTrigger,
            lastCenterTrigger: &lastCenterTrigger
        )
    }

    func scheduleRegionChange(on mapView: MKMapView, region: MKCoordinateRegion, animated: Bool) {
        guard let sanitizedRegion = GeoStateValidator.sanitizedRegion(
            center: region.center,
            span: region.span
        ) else {
            return
        }
        latestProgrammaticRegionGeneration += 1
        let scheduledGeneration = latestProgrammaticRegionGeneration

        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self, let mapView else { return }
            guard scheduledGeneration == self.latestProgrammaticRegionGeneration else {
                return
            }
            guard !MapKitViewSharedLogic.regionsEquivalent(mapView.region, sanitizedRegion) else {
                return
            }
            self.pendingIgnoredRegionChanges += 1
            self.schedulePendingIgnoreReset(animated: animated)
            mapView.setRegion(sanitizedRegion, animated: animated)
        }
    }

    func handleRegionDidChange(
        mapView: MKMapView,
        onRegionChange: @escaping (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    ) {
        if MapKitViewSharedLogic.consumePendingRegionChangeIgnore(&pendingIgnoredRegionChanges) {
            if pendingIgnoredRegionChanges == 0 {
                pendingIgnoreResetTask?.cancel()
                pendingIgnoreResetTask = nil
            }
            return
        }
        let region = mapView.region
        guard let sanitizedRegion = GeoStateValidator.sanitizedRegion(
            center: region.center,
            span: region.span
        ) else {
            return
        }
        let capturedGeneration = latestProgrammaticRegionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard capturedGeneration == self.latestProgrammaticRegionGeneration else { return }
            onRegionChange(sanitizedRegion.center, sanitizedRegion.span)
        }
    }

    private func schedulePendingIgnoreReset(animated: Bool) {
        pendingIgnoreResetTask?.cancel()
        let resetDelay = animated ? Self.animatedPendingIgnoreResetDelay : Self.pendingIgnoreResetDelay
        pendingIgnoreResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: resetDelay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.pendingIgnoredRegionChanges = 0
            self.pendingIgnoreResetTask = nil
        }
    }

    func renderer(for overlay: MKOverlay, overlayAlpha: CGFloat) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? LightPollutionTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = overlayAlpha
            return renderer
        }
        if overlay is ViewingDirectionOverlay {
            let renderer = MKPolygonRenderer(overlay: overlay)
            #if os(macOS)
            renderer.fillColor = NSColor.white.withAlphaComponent(0.15)
            renderer.strokeColor = NSColor.white.withAlphaComponent(0.5)
            #else
            renderer.fillColor = UIColor.white.withAlphaComponent(0.15)
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.5)
            #endif
            renderer.lineWidth = 1.0
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
