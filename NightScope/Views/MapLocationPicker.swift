import SwiftUI
import MapKit

// MARK: - MapContainerView

/// 地図ビューを包む共通コンテナ（枠線・ラベル付き）。
private struct MapContainerView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    private var instructionText: String { L10n.tr("地図をクリックして場所を選択") }

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
        MapKitViewSharedLogic.applyMapUpdate(
            on: nsView,
            state: context.coordinator.state,
            configuration: .init(
                pinCoordinate: pinCoordinate,
                syncState: syncState,
                centerTrigger: centerTrigger,
                overlayAlpha: overlayAlpha,
                viewingDirection: viewingDirection
            )
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitViewRepresentable
        let state: MapKitCoordinatorState

        init(_ parent: MapKitViewRepresentable) {
            self.parent = parent
            self.state = MapKitCoordinatorState(
                syncTrigger: parent.syncState.trigger,
                centerTrigger: parent.centerTrigger
            )
        }

        @objc func handleTap(_ gr: NSClickGestureRecognizer) {
            guard let mapView = gr.view as? MKMapView else { return }
            let point = gr.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            state.handleRegionDidChange(mapView: mapView, onRegionChange: parent.onRegionChange)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            state.renderer(for: overlay, overlayAlpha: parent.overlayAlpha)
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
            .accessibilityLabel(L10n.tr("現在地を取得"))
            .accessibilityHint(L10n.tr("地図を現在地へ移動します"))
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
