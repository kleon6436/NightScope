import SwiftUI
import MapKit

// MARK: - MapContainerView

/// 地図ビューを包む共通コンテナ（枠線・ラベル付き）。
private struct MapContainerView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private var instructionText: String { "地図をクリックして場所を選択" }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.mapInstructionSpacing) {
            mapSurface
            instructionLabel
        }
    }

    private var mapSurface: some View {
        content()
            .frame(minHeight: Layout.mapMinHeight, maxHeight: Layout.mapMaxHeight)
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
    let pinCoordinate: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void
    let syncState: MapKitSyncState
    let onRegionChange: (CLLocationCoordinate2D, MKCoordinateSpan) -> Void
    let showLightPollution: Bool
    /// 現在地取得成功時にインクリメントされるトリガー（変化時のみマップをセンタリング）
    let centerTrigger: Int
    /// 視野方向オーバーレイ（nil の場合は非表示）
    var viewingDirection: ViewingDirection?

    private var overlayAlpha: CGFloat {
        MapKitViewSharedLogic.overlayAlpha(showLightPollution: showLightPollution)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        // カメラ距離 10km 未満へのズームインを禁止（光害タイルの解像度上限に対応）
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: MapKitViewSharedLogic.minCenterCoordinateDistance)
        // 光害オーバーレイを常駐させタブ切り替え時のタイル再描画を防ぐ（alpha で表示/非表示を切り替える）
        mapView.addOverlay(LightPollutionTileOverlay(urlTemplate: nil), level: .aboveRoads)
        MapKitViewSharedLogic.setInitialRegionIfNeeded(on: mapView, pinCoordinate: pinCoordinate)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(click)
        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.parent = self
        MapKitViewSharedLogic.updateLightPollutionOverlayAlpha(on: nsView, targetAlpha: overlayAlpha)

        let existing = MapKitViewSharedLogic.currentPinAnnotation(in: nsView)

        guard let newCoord = pinCoordinate else {
            MapKitViewSharedLogic.removeAnnotationsIfNeeded(from: nsView, existing: existing)
            return
        }

        if MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            on: nsView,
            existing: existing,
            coordinate: newCoord,
            syncState: syncState,
            lastSyncTrigger: &context.coordinator.lastSyncTrigger
        ) {
            return
        }

        MapKitViewSharedLogic.upsertPinAnnotation(on: nsView, existing: existing, coordinate: newCoord)
        MapKitViewSharedLogic.centerOnCurrentLocationIfNeeded(
            on: nsView,
            coordinate: newCoord,
            centerTrigger: centerTrigger,
            lastCenterTrigger: &context.coordinator.lastCenterTrigger
        )
        MapKitViewSharedLogic.updateViewingDirectionOverlay(
            on: nsView, pinCoordinate: pinCoordinate, viewingDirection: viewingDirection)
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
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = parent.overlayAlpha
                return renderer
            }
            if overlay is ViewingDirectionOverlay {
                let renderer = MKPolygonRenderer(overlay: overlay)
                renderer.fillColor = NSColor.white.withAlphaComponent(0.15)
                renderer.strokeColor = NSColor.white.withAlphaComponent(0.5)
                renderer.lineWidth = 1.0
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
    var viewingDirection: ViewingDirection? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        coordinatesEqual(lhs.selectedCoordinate, rhs.selectedCoordinate) &&
        lhs.syncState == rhs.syncState &&
        lhs.showLightPollution == rhs.showLightPollution &&
        lhs.isLocating == rhs.isLocating &&
        lhs.centerTrigger == rhs.centerTrigger &&
        lhs.viewingDirection == rhs.viewingDirection
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
            centerTrigger: centerTrigger,
            viewingDirection: viewingDirection
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
            .buttonStyle(.glass)
            .padding(Spacing.xs)
            .disabled(isLocating)
            .accessibilityLabel("現在地を取得")
            .accessibilityHint("地図を現在地へ移動します")
        }
    }

    @ViewBuilder
    private var currentLocationButtonLabel: some View {
        Group {
            if isLocating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: AppIcons.Navigation.currentLocation)
                    .font(.system(size: Layout.mapIconSize))
            }
        }
        .frame(width: Layout.mapButtonSize, height: Layout.mapButtonSize)
    }
}
