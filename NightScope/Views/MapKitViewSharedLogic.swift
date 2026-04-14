import MapKit

@MainActor
enum MapKitViewSharedLogic {
    private enum Config {
        static let minCenterCoordinateDistance: CLLocationDistance = 100
        static let visibleOverlayAlpha: CGFloat = 0.8
        static let hiddenOverlayAlpha: CGFloat = 0.0
        static let initialPinLatitudeDelta: CLLocationDegrees = 0.05
        static let initialPinLongitudeDelta: CLLocationDegrees = 0.05
        static let currentLocationLatitudeDelta: CLLocationDegrees = 0.5
        static let currentLocationLongitudeDelta: CLLocationDegrees = 0.5
    }

    static var minCenterCoordinateDistance: CLLocationDistance {
        Config.minCenterCoordinateDistance
    }

    static func overlayAlpha(showLightPollution: Bool) -> CGFloat {
        showLightPollution ? Config.visibleOverlayAlpha : Config.hiddenOverlayAlpha
    }

    static func setInitialRegionIfNeeded(on mapView: MKMapView, pinCoordinate: CLLocationCoordinate2D?) {
        guard let pinCoordinate else { return }
        let region = MKCoordinateRegion(
            center: pinCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: Config.initialPinLatitudeDelta,
                longitudeDelta: Config.initialPinLongitudeDelta
            )
        )
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

    static func applyViewportSyncIfNeeded(
        existing: MKPointAnnotation?,
        coordinate: CLLocationCoordinate2D,
        syncState: MapKitSyncState,
        lastSyncTrigger: inout Int
    ) -> MKCoordinateRegion? {
        guard lastSyncTrigger != syncState.trigger else {
            return nil
        }

        lastSyncTrigger = syncState.trigger
        return MKCoordinateRegion(center: syncState.center, span: syncState.span)
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
        return MKCoordinateRegion(
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
        let overlay = ViewingDirectionOverlay(coordinates: &coords, count: coords.count)
        mapView.addOverlay(overlay, level: .aboveRoads)
    }

    private static func sectorCoordinates(
        center: CLLocationCoordinate2D,
        azimuth: Double,
        fov: Double,
        radius: Double = 2000
    ) -> [CLLocationCoordinate2D] {
        let lat = center.latitude
        let steps = 20
        var coords = [CLLocationCoordinate2D]()
        coords.append(center)
        for i in 0...steps {
            let angle = (azimuth - fov / 2) + Double(i) * fov / Double(steps)
            let angleRad = angle * .pi / 180
            let latOffset  = radius * cos(angleRad) / 111_000
            let cosLat = max(abs(cos(lat * .pi / 180)), 1e-6)
            let lonOffset  = radius * sin(angleRad) / (111_000 * cosLat)
            coords.append(CLLocationCoordinate2D(
                latitude:  lat + latOffset,
                longitude: center.longitude + lonOffset
            ))
        }
        return coords
    }
}


// MARK: - ViewingDirectionOverlay

/// サイドバーマップで視野方向を示す扇形ポリゴンオーバーレイ。
final class ViewingDirectionOverlay: MKPolygon {}
