import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - StarMapCanvasView

/// 星空マップを描画する共有ビュー (iPhone / Mac 共通)
/// - 心射図法 (viewAltitude/viewAzimuth が画面中心)
struct StarMapCanvasView: View {
    struct CardinalOverlayPlacement: Identifiable, Equatable {
        let azimuthDegrees: Double
        let label: String
        let x: Double

        var id: Double { azimuthDegrees }
    }

    @ObservedObject var viewModel: StarMapViewModel
    var showsCardinalOverlay: Bool = true

    /// クリック/タップで天体を選択したときに呼ばれるコールバック (macOS で使用)
    var onStarSelected: ((StarPosition) -> Void)? = nil

    // ドラッグ中の一時オフセット (ピクセル単位, 横・縦)
    @GestureState private var gestureDragOffset: CGSize = .zero

    @GestureState private var gestureScale: Double = 1.0

    // キーボードフォーカス
    @FocusState private var isFocused: Bool

#if os(macOS)
    @State private var scrollWheelMonitor: Any?
#endif

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                canvas(size: size)
                    .gesture(
                        gnomonicDragGesture(size: size),
                        including: viewModel.isGyroMode ? .none : .all
                    )
                    .gesture(pinchGesture)
                    .onTapGesture(coordinateSpace: .local) { location in
                        handleTap(at: location, size: size)
                    }

                gyroModeIndicator

                // ピンチ中のみ視野角を表示
                if gestureScale != 1.0 {
                    pinchFOVOverlay
                }

                if showsCardinalOverlay && !viewModel.isTimeSliderScrubbing {
                    cardinalOverlay(size: size)
                }
            }
            .onAppear {
                onCanvasAppear(size)
#if os(macOS)
                if scrollWheelMonitor == nil {
                    scrollWheelMonitor = StarMapCanvasMacSupport.installScrollWheelMonitor(for: viewModel)
                }
#endif
            }
            .onDisappear {
#if os(macOS)
                StarMapCanvasMacSupport.removeScrollWheelMonitor(scrollWheelMonitor)
                scrollWheelMonitor = nil
#endif
            }
            .onChange(of: size) { _, newSize in
                onCanvasAppear(newSize)
            }
            .focusable()
            .focused($isFocused)
            // MARK: Keyboard Navigation (デフォルト phases = [.down, .repeat])
            .onKeyPress(.leftArrow) {
                handleAzimuthKey(step: -StarMapLayout.directionStep)
            }
            .onKeyPress(.rightArrow) {
                handleAzimuthKey(step: StarMapLayout.directionStep)
            }
            .onKeyPress(.upArrow) {
                handleAltitudeKey(step: StarMapLayout.directionStep)
            }
            .onKeyPress(.downArrow) {
                handleAltitudeKey(step: -StarMapLayout.directionStep)
            }
            .onKeyPress(KeyEquivalent("=")) {
                handleZoomKey(step: -StarMapLayout.zoomStep)
            }
            .onKeyPress(KeyEquivalent("-")) {
                handleZoomKey(step: StarMapLayout.zoomStep)
            }
            .onKeyPress(KeyEquivalent("n")) {
                viewModel.resetToNorth()
                return .handled
            }
        }
        .background(StarMapPalette.canvasBackground)
    }

    private var pinchFOVOverlay: some View {
        PinchFOVOverlayView(displayFov: effectiveGnomonicFOV())
    }

    private func handleTap(at location: CGPoint, size: CGSize) {
        isFocused = true
        guard !viewModel.isGyroMode else { return }
        let center = effectiveGnomonicCenter(size: size)
        if let star = StarMapCanvasInteraction.nearestStar(
            at: location,
            starPositions: viewModel.starPositions,
            size: size,
            fov: effectiveGnomonicFOV(),
            centerAlt: center.alt,
            centerAz: center.az
        ) {
            onStarSelected?(star)
        }
    }

    private func handleAzimuthKey(step: Double) -> KeyPress.Result {
        viewModel.viewAzimuth = StarMapCanvasInteraction.movedAzimuth(
            current: viewModel.viewAzimuth,
            step: step
        )
        return .handled
    }

    private func handleAltitudeKey(step: Double) -> KeyPress.Result {
        viewModel.viewAltitude = StarMapCanvasInteraction.movedAltitude(
            current: viewModel.viewAltitude,
            step: step
        )
        return .handled
    }

    private func handleZoomKey(step: Double) -> KeyPress.Result {
        viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov + step)
        return .handled
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        Canvas { ctx, sz in
            let cx = sz.width / 2
            let cy = sz.height / 2
            let (centerAlt, centerAz) = effectiveGnomonicCenter(size: sz)
            let fov = effectiveGnomonicFOV()
            drawGnomonicProjection(ctx: ctx, cx: cx, cy: cy, size: sz,
                                   centerAlt: centerAlt, centerAz: centerAz, fov: fov)
        }
    }

    private func cardinalOverlay(size: CGSize) -> some View {
        CardinalOverlayView(
            placements: cardinalLabelPlacements(size: size),
            overlayY: StarMapCanvasProjection.cardinalOverlayY(sizeHeight: size.height)
        )
    }


    // MARK: - Gnomonic Projection (心射図法)

    /// ピンチ中のライブ視野角（心射図法用）
    private func effectiveGnomonicFOV() -> Double {
        StarMapCanvasProjection.effectiveFOV(baseFOV: viewModel.fov, gestureScale: gestureScale)
    }

    /// ドラッグ中のライブ中心方向（心射図法用）。
    /// スクリーン移動量をカメラ空間の角度変化に正確に変換する。
    private func effectiveGnomonicCenter(size: CGSize) -> (alt: Double, az: Double) {
        StarMapCanvasProjection.adjustedCenter(
            viewAltitude: viewModel.viewAltitude,
            viewAzimuth: viewModel.viewAzimuth,
            translation: gestureDragOffset,
            size: size,
            fov: effectiveGnomonicFOV()
        )
    }


    // MARK: - Gnomonic Ground / Horizon / Cardinals

    private func cardinalLabelPlacements(size: CGSize) -> [CardinalOverlayPlacement] {
        let center = effectiveGnomonicCenter(size: size)
        return StarMapCanvasProjection.cardinalLabelPlacements(
            size: size,
            centerAlt: center.alt,
            centerAz: center.az,
            fov: effectiveGnomonicFOV()
        )
    }

    // MARK: - Drag Gesture (心射図法 カメラ空間ドラッグ)

    private func gnomonicDragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { [self] value in
                let center = StarMapCanvasProjection.adjustedCenter(
                    viewAltitude: viewModel.viewAltitude,
                    viewAzimuth: viewModel.viewAzimuth,
                    translation: value.translation,
                    size: size,
                    fov: effectiveGnomonicFOV()
                )
                viewModel.viewAltitude = center.alt
                viewModel.viewAzimuth = center.az
            }
    }

    // MARK: - Pinch Gesture (視野角ズーム)

    /// ピンチで水平視野角を調整する。広げると狭くなる (望遠鏡的ズームイン)。
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { [self] value in
                viewModel.fov = StarMapCanvasInteraction.committedFOV(
                    currentFOV: viewModel.fov,
                    magnification: value
                )
            }
    }

    private func onCanvasAppear(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewModel.updateCanvasSize(size)
        viewModel.applyInitialPoseIfNeeded()
    }

    // MARK: - Gyro Mode Indicator

    private var gyroModeIndicator: some View {
        GyroModeIndicatorView(
            azimuth: viewModel.viewAzimuth,
            altitude: viewModel.viewAltitude
        )
    }
}

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return StarMapCanvasView(viewModel: vm)
        .frame(width: 400, height: 500)
}
