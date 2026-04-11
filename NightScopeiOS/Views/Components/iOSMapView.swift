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

        if MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            on: uiView,
            existing: existing,
            coordinate: newCoord,
            syncState: syncState,
            lastSyncTrigger: &context.coordinator.lastSyncTrigger
        ) {
            return
        }

        MapKitViewSharedLogic.upsertPinAnnotation(on: uiView, existing: existing, coordinate: newCoord)
        MapKitViewSharedLogic.centerOnCurrentLocationIfNeeded(
            on: uiView,
            coordinate: newCoord,
            centerTrigger: centerTrigger,
            lastCenterTrigger: &context.coordinator.lastCenterTrigger
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: iOSMapView
        var lastSyncTrigger: Int
        var lastCenterTrigger: Int

        init(_ parent: iOSMapView) {
            self.parent = parent
            self.lastSyncTrigger = parent.syncState.trigger
            self.lastCenterTrigger = parent.centerTrigger
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
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
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.overlayAlpha
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
