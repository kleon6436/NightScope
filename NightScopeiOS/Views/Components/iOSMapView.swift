import SwiftUI
import MapKit

// MARK: - UIViewRepresentable wrapper for MKMapView (iOS)

struct iOSMapView: UIViewRepresentable {
    let pinCoordinate: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool
    let centerTrigger: Int

    private var overlayAlpha: CGFloat {
        MapKitViewSharedLogic.overlayAlpha(showLightPollution: showLightPollution)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: MapKitViewSharedLogic.minCenterCoordinateDistance
        )
        mapView.addOverlay(LightPollutionTileOverlay(urlTemplate: nil), level: .aboveRoads)
        MapKitViewSharedLogic.setInitialRegionIfNeeded(on: mapView, pinCoordinate: pinCoordinate)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        MapKitViewSharedLogic.updateLightPollutionOverlayAlpha(on: uiView, targetAlpha: overlayAlpha)

        let existing = MapKitViewSharedLogic.currentPinAnnotation(in: uiView)

        guard let newCoord = pinCoordinate else {
            MapKitViewSharedLogic.removeAnnotationsIfNeeded(from: uiView, existing: existing)
            return
        }

        if let syncRegion = MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            existing: existing,
            coordinate: newCoord,
            syncState: syncState,
            lastSyncTrigger: &context.coordinator.lastSyncTrigger
        ) {
            MapKitViewSharedLogic.upsertPinAnnotation(on: uiView, existing: existing, coordinate: newCoord)
            context.coordinator.scheduleRegionChange(on: uiView, region: syncRegion, animated: false)
            return
        }

        MapKitViewSharedLogic.upsertPinAnnotation(on: uiView, existing: existing, coordinate: newCoord)
        if let centeredRegion = MapKitViewSharedLogic.centerOnCurrentLocationIfNeeded(
            coordinate: newCoord,
            centerTrigger: centerTrigger,
            lastCenterTrigger: &context.coordinator.lastCenterTrigger
        ) {
            context.coordinator.scheduleRegionChange(on: uiView, region: centeredRegion, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: iOSMapView
        var lastSyncTrigger: Int
        var lastCenterTrigger: Int
        var pendingIgnoredRegionChanges = 0
        var latestProgrammaticRegionGeneration = 0

        init(_ parent: iOSMapView) {
            self.parent = parent
            self.lastSyncTrigger = parent.syncState.trigger
            self.lastCenterTrigger = parent.centerTrigger
        }

        func scheduleRegionChange(on mapView: MKMapView, region: MKCoordinateRegion, animated: Bool) {
            pendingIgnoredRegionChanges += 1
            latestProgrammaticRegionGeneration += 1
            let scheduledGeneration = latestProgrammaticRegionGeneration

            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                guard scheduledGeneration == self.latestProgrammaticRegionGeneration else {
                    self.pendingIgnoredRegionChanges = max(0, self.pendingIgnoredRegionChanges - 1)
                    return
                }
                mapView.setRegion(region, animated: animated)
            }
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let mapView = gr.view as? MKMapView else { return }
            let point = gr.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if MapKitViewSharedLogic.consumePendingRegionChangeIgnore(&pendingIgnoredRegionChanges) {
                return
            }
            let region = mapView.region
            let capturedGeneration = latestProgrammaticRegionGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard capturedGeneration == self.latestProgrammaticRegionGeneration else { return }
                self.parent.onRegionChange(region.center, region.span)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? LightPollutionTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.overlayAlpha
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
