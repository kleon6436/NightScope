import SwiftUI
#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#elseif os(iOS)
import UIKit
private typealias PlatformFont = UIFont
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

    struct ConstellationLabelCandidate: Equatable {
        let name: String
        let anchor: CGPoint
        let priority: Double
    }

    struct ConstellationLabelPlacement: Equatable {
        let name: String
        let anchor: CGPoint
        let origin: CGPoint
        let size: CGSize

        var bounds: CGRect {
            CGRect(origin: origin, size: size)
        }
    }

    struct HorizonOverlayStyle {
        let groundFillColor: Color
        let groundFillOpacity: Double
        let horizonStrokeColor: Color
        let terrainFillColor: Color
        let terrainFillOpacity: Double
        let terrainStrokeColor: Color

        static let `default` = HorizonOverlayStyle(
            groundFillColor: Color(red: 0.08, green: 0.12, blue: 0.06),
            groundFillOpacity: 0.6,
            horizonStrokeColor: Color(red: 0.3, green: 0.5, blue: 0.3).opacity(0.5),
            terrainFillColor: StarMapPalette.groundFill,
            terrainFillOpacity: 1,
            terrainStrokeColor: Color(red: 0.2, green: 0.35, blue: 0.15).opacity(0.4)
        )
    }

    private struct HorizonLineCoefficients {
        let a: Double
        let b: Double
        let c: Double

        func value(at point: CGPoint) -> Double {
            a * point.x + b * point.y + c
        }
    }

    private struct GnomonicProjectionContext {
        let cx: Double
        let cy: Double
        let scale: Double
        let forward: (x: Double, y: Double, z: Double)
        let right: (x: Double, y: Double, z: Double)
        let up: (x: Double, y: Double, z: Double)

        init(size: CGSize, centerAlt: Double, centerAz: Double, rollDegrees: Double, fov: Double) {
            self.cx = size.width / 2
            self.cy = size.height / 2
            self.scale = StarMapCanvasView.projectionScale(size: size, horizontalFOV: fov)
            let basis = StarMapCanvasView.cameraBasis(
                centerAlt: centerAlt,
                centerAz: centerAz,
                roll: rollDegrees
            )
            self.forward = basis.forward
            self.right = basis.right
            self.up = basis.up
        }

        func project(altitudeRadians: Double, azimuthRadians: Double) -> CGPoint? {
            StarMapCanvasView.projectPoint(
                cx: cx,
                cy: cy,
                scale: scale,
                forward: forward,
                right: right,
                up: up,
                altitudeRadians: altitudeRadians,
                azimuthRadians: azimuthRadians
            )
        }
    }

    @ObservedObject var viewModel: StarMapViewModel
    var showsCardinalOverlay: Bool = true
    var cardinalOverlayBottomInset: CGFloat = StarMapLayout.cardinalLabelBottomInset
    var backgroundColor: Color = StarMapPalette.canvasBackground
    var drawsDynamicSky: Bool = true
    var horizonOverlayStyle: HorizonOverlayStyle = .default
    var fovOverride: Double? = nil
    var rollOverride: Double? = nil

    /// クリック/タップで天体を選択したときに呼ばれるコールバック (macOS で使用)
    var onStarSelected: ((StarPosition) -> Void)? = nil

    // ドラッグ中の一時オフセット (ピクセル単位, 横・縦)
    @GestureState private var gestureDragOffset: CGSize = .zero

    @GestureState private var gestureScale: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // キーボードフォーカス
    @FocusState private var isFocused: Bool

#if os(macOS)
    @State private var scrollWheelMonitor: Any?
    @State private var isPointerOverCanvas = false
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
                    .gesture(
                        pinchGesture,
                        including: allowsManualFOVAdjustment ? .all : .none
                    )
                    .onTapGesture(coordinateSpace: .local) { location in
                        handleTap(at: location, size: size)
                    }

                gyroModeIndicator

                // ピンチ中のみ視野角を表示
                if allowsManualFOVAdjustment && gestureScale != 1.0 {
                    pinchFOVOverlay
                }

                if showsCardinalOverlay && !viewModel.isTimeSliderScrubbing {
                    cardinalOverlay(size: size)
                }
            }
            .onAppear {
                onCanvasAppear(size)
#if os(macOS)
                installMacScrollWheelMonitor()
#endif
            }
            .onDisappear {
#if os(macOS)
                removeMacScrollWheelMonitor()
#endif
            }
#if os(macOS)
            .onHover { isPointerOverCanvas = $0 }
#endif
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
        .background(backgroundColor)
    }

    private var pinchFOVOverlay: some View {
        PinchFOVOverlayView(displayFov: StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale)))
    }

    private var allowsManualFOVAdjustment: Bool {
        fovOverride == nil
    }

    private func handleTap(at location: CGPoint, size: CGSize) {
        isFocused = true
        if let star = nearestStar(at: location, size: size) {
            onStarSelected?(star)
        }
    }

    private func handleAzimuthKey(step: Double) -> KeyPress.Result {
        viewModel.viewAzimuth = (viewModel.viewAzimuth + step + 360)
            .truncatingRemainder(dividingBy: 360)
        return .handled
    }

    private func handleAltitudeKey(step: Double) -> KeyPress.Result {
        viewModel.viewAltitude = max(-10, min(89, viewModel.viewAltitude + step))
        return .handled
    }

    private func handleZoomKey(step: Double) -> KeyPress.Result {
        guard allowsManualFOVAdjustment else { return .ignored }
        viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov + step)
        return .handled
    }

    // MARK: Canvas

    private var scintillationEnabled: Bool {
        viewModel.isNight && !reduceMotion
    }

    private func canvas(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !scintillationEnabled)) { timeline in
            Canvas { ctx, sz in
                let cx = sz.width / 2
                let cy = sz.height / 2
                let (centerAlt, centerAz) = effectiveGnomonicCenter(size: sz)
                let roll = effectiveGnomonicRoll()
                let fov = effectiveGnomonicFOV()
                let scintillationTime = scintillationEnabled
                    ? timeline.date.timeIntervalSinceReferenceDate : 0
                drawGnomonicProjection(ctx: ctx, cx: cx, cy: cy, size: sz,
                                       centerAlt: centerAlt, centerAz: centerAz,
                                       roll: roll, fov: fov,
                                       scintillationTime: scintillationTime)
            }
        }
    }

    private func cardinalOverlay(size: CGSize) -> some View {
        CardinalOverlayView(
            placements: cardinalLabelPlacements(size: size),
            overlayY: Self.cardinalOverlayY(
                sizeHeight: size.height,
                bottomInset: Double(cardinalOverlayBottomInset)
            )
        )
    }


    // MARK: - Gnomonic Projection (心射図法)

    /// ピンチ中のライブ視野角（心射図法用）
    private func effectiveGnomonicFOV() -> Double {
        if let fovOverride {
            return StarMapLayout.clampedFOV(fovOverride)
        }
        return StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale))
    }

    private func effectiveGnomonicRoll() -> Double {
        if let rollOverride {
            return rollOverride
        }
        return viewModel.isGyroMode ? viewModel.viewRoll : 0
    }

    /// ドラッグ中のライブ中心方向（心射図法用）。
    /// スクリーン移動量をカメラ空間の角度変化に正確に変換する。
    private func effectiveGnomonicCenter(size: CGSize) -> (alt: Double, az: Double) {
        guard gestureDragOffset != .zero else {
            return (viewModel.viewAltitude, viewModel.viewAzimuth)
        }
        let fov = effectiveGnomonicFOV()
        let scale = Self.projectionScale(size: size, horizontalFOV: fov)
        return Self.adjustedCenter(
            altitude: viewModel.viewAltitude,
            azimuth: viewModel.viewAzimuth,
            translation: gestureDragOffset,
            scale: scale
        )
    }


    private func drawGnomonicProjection(ctx: GraphicsContext,
                                        cx: Double, cy: Double, size: CGSize,
                                        centerAlt: Double, centerAz: Double, roll: Double, fov: Double,
                                        scintillationTime: Double = 0) {
        let projection = GnomonicProjectionContext(
            size: size,
            centerAlt: centerAlt,
            centerAz: centerAz,
            rollDegrees: roll,
            fov: fov
        )

        // 動的空色の塗りつぶし
        if drawsDynamicSky {
            let skyColor = StarMapPalette.skyColor(
                sunAltitude: viewModel.sunAltitude,
                moonAltitude: viewModel.moonAltitude,
                moonPhase: viewModel.moonPhase
            )
            ctx.fill(
                Rectangle().path(in: CGRect(origin: .zero, size: size)),
                with: .color(skyColor)
            )
        }

        // 地平線・地面描画
        drawGnomonicGround(ctx: ctx, size: size, projection: projection)

        // 星座線
        if viewModel.showsConstellationLines {
            var constPath = Path()
            for line in viewModel.constellationLines {
                let a1 = max(line.startAlt, -5) * .pi / 180
                let a2 = max(line.endAlt,   -5) * .pi / 180
                if let p1 = projection.project(altitudeRadians: a1, azimuthRadians: line.startAz * .pi / 180),
                   let p2 = projection.project(altitudeRadians: a2, azimuthRadians: line.endAz * .pi / 180) {
                    constPath.move(to: p1)
                    constPath.addLine(to: p2)
                }
            }
            ctx.stroke(constPath,
                       with: .color(Color(red: 0.4, green: 0.6, blue: 0.9).opacity(0.35)),
                       lineWidth: 1)
        }

        // 天の川バンド（星座線の上、恒星の下に描画）
        if viewModel.isNight {
            drawGnomonicMilkyWayBand(
                ctx: ctx,
                project: { alt, az in
                    projection.project(altitudeRadians: alt, azimuthRadians: az)
                }
            )
        }

        // 恒星
        let moonBright = StarMapPalette.moonBrightness(
            moonAltitude: viewModel.moonAltitude,
            moonPhase: viewModel.moonPhase
        )
        for pos in viewModel.starPositions {
            // 地平線近くの暗い星をスキップ
            if pos.altitude < 5 && pos.star.magnitude > 6.0 { continue }
            let alt = pos.altitude * .pi / 180
            let az  = pos.azimuth  * .pi / 180
            if let pt = projection.project(altitudeRadians: alt, azimuthRadians: az) {
                drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                         isDark: viewModel.isNight, precomputedColor: pos.precomputedColor,
                         altitude: pos.altitude,
                         moonBrightness: moonBright,
                         scintillationTime: scintillationTime,
                         starRA: pos.star.ra)
                if pos.star.magnitude < 1.5, !pos.star.localizedName.isEmpty {
                    drawStarLabel(ctx: ctx, at: pt, name: pos.star.localizedName)
                }
            }
        }

        // 星座名ラベル
        if viewModel.showsConstellationLines {
            var constellationLabelCandidates: [ConstellationLabelCandidate] = []
            for label in viewModel.constellationLabels {
                let alt = label.alt * .pi / 180
                let az  = label.az  * .pi / 180
                if let pt = projection.project(altitudeRadians: alt, azimuthRadians: az) {
                    constellationLabelCandidates.append(
                        ConstellationLabelCandidate(name: label.name, anchor: pt, priority: label.alt)
                    )
                }
            }

            for placement in Self.optimizedConstellationLabelPlacements(
                candidates: constellationLabelCandidates,
                canvasSize: size,
                reservedBottomInset: showsCardinalOverlay ? Double(cardinalOverlayBottomInset) + 20 : 0
            ) {
                ctx.draw(
                    Text(placement.name)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.52)),
                    at: placement.origin,
                    anchor: .topLeading
                )
            }
        }

        // 月
        if viewModel.moonAltitude > -1 {
            let alt = viewModel.moonAltitude * .pi / 180
            if let pt = projection.project(
                altitudeRadians: alt,
                azimuthRadians: viewModel.moonAzimuth * .pi / 180
            ) {
                drawMoon(ctx: ctx, at: pt, phase: viewModel.moonPhase)
            }
        }

        // 銀河系中心
        if viewModel.galacticCenterAltitude > -1 {
            let alt = viewModel.galacticCenterAltitude * .pi / 180
            if let pt = projection.project(
                altitudeRadians: alt,
                azimuthRadians: viewModel.galacticCenterAzimuth * .pi / 180
            ) {
                drawGalacticCenter(ctx: ctx, at: pt)
            }
        }

        // 惑星
        for planet in viewModel.planetPositions where planet.altitude > -1 {
            let alt = planet.altitude * .pi / 180
            if let pt = projection.project(
                altitudeRadians: alt,
                azimuthRadians: planet.azimuth * .pi / 180
            ) {
                drawPlanet(ctx: ctx, at: pt, planet: planet)
            }
        }

        // 流星群放射点
        for radiant in viewModel.meteorShowerRadiants where radiant.altitude > -1 {
            let alt = radiant.altitude * .pi / 180
            if let pt = projection.project(
                altitudeRadians: alt,
                azimuthRadians: radiant.azimuth * .pi / 180
            ) {
                drawMeteorShowerRadiant(ctx: ctx, at: pt, shower: radiant.shower)
            }
        }

        // 地形シルエット（最前面: 天体を自然に隠す）
        if let terrain = viewModel.terrainProfile {
            drawGnomonicTerrainSilhouette(
                ctx: ctx,
                project: { alt, az in
                    projection.project(altitudeRadians: alt, azimuthRadians: az)
                },
                centerAz: centerAz,
                fov: fov,
                size: size,
                terrain: terrain
            )
        }

        drawCrosshair(ctx: ctx, cx: cx, cy: cy)
    }

    // MARK: - Gnomonic Ground / Horizon / Cardinals

    private func drawGnomonicGround(ctx: GraphicsContext,
                                    size: CGSize,
                                    projection: GnomonicProjectionContext) {
        let rect = CGRect(origin: .zero, size: size)
        let coefficients = Self.horizonLineCoefficients(
            cx: projection.cx,
            cy: projection.cy,
            scale: projection.scale,
            forwardZ: projection.forward.z,
            rightZ: projection.right.z,
            upZ: projection.up.z
        )
        let groundPolygon = Self.clippedGroundPolygon(in: rect, coefficients: coefficients)

        if groundPolygon.count >= 3 {
            var groundPath = Path()
            groundPath.move(to: groundPolygon[0])
            for point in groundPolygon.dropFirst() {
                groundPath.addLine(to: point)
            }
            groundPath.closeSubpath()
            ctx.fill(
                groundPath,
                with: .color(
                    horizonOverlayStyle.groundFillColor.opacity(horizonOverlayStyle.groundFillOpacity)
                )
            )
        }

        if let horizonSegment = Self.horizonLineSegment(in: rect, coefficients: coefficients) {
            var horizonPath = Path()
            horizonPath.move(to: horizonSegment.0)
            horizonPath.addLine(to: horizonSegment.1)
            ctx.stroke(horizonPath,
                       with: .color(horizonOverlayStyle.horizonStrokeColor),
                       lineWidth: 1)
        }
    }

    private func cardinalLabelPlacements(size: CGSize) -> [CardinalOverlayPlacement] {
        let center = effectiveGnomonicCenter(size: size)
        return Self.cardinalLabelPlacements(
            size: size,
            centerAlt: center.alt,
            centerAz: center.az,
            roll: effectiveGnomonicRoll(),
            fov: effectiveGnomonicFOV()
        )
    }

    /// 画面下部オーバーレイに表示する方位ラベルの配置候補を返します。
    nonisolated static func cardinalLabelPlacements(
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        roll: Double,
        fov: Double
    ) -> [CardinalOverlayPlacement] {
        let cardinals: [(Double, String)] = [
            (0, StarMapPresentation.azimuthName(for: 0)),
            (45, StarMapPresentation.azimuthName(for: 45)),
            (90, StarMapPresentation.azimuthName(for: 90)),
            (135, StarMapPresentation.azimuthName(for: 135)),
            (180, StarMapPresentation.azimuthName(for: 180)),
            (225, StarMapPresentation.azimuthName(for: 225)),
            (270, StarMapPresentation.azimuthName(for: 270)),
            (315, StarMapPresentation.azimuthName(for: 315))
        ]

        return cardinals.compactMap { azimuthDegrees, label in
            guard let x = projectedCardinalLabelX(
                azimuthDegrees: azimuthDegrees,
                size: size,
                centerAlt: centerAlt,
                centerAz: centerAz,
                roll: roll,
                fov: fov
            ) else {
                return nil
            }

            return CardinalOverlayPlacement(
                azimuthDegrees: azimuthDegrees,
                label: label,
                x: x
            )
        }
    }

    /// 方位ラベルが画面端で切れないように X 座標を制限します。
    nonisolated static func clampedCardinalLabelX(_ x: Double, sizeWidth: Double) -> Double {
        let minX = Double(StarMapLayout.cardinalLabelSidePadding)
        let maxX = sizeWidth - Double(StarMapLayout.cardinalLabelSidePadding)
        return min(max(x, minX), maxX)
    }

    /// 方位ラベルの固定オーバーレイ Y 座標を返します。
    nonisolated static func cardinalOverlayY(
        sizeHeight: Double,
        bottomInset: Double = Double(StarMapLayout.cardinalLabelBottomInset)
    ) -> Double {
        sizeHeight - bottomInset
    }

    nonisolated static func optimizedConstellationLabelPlacements(
        candidates: [ConstellationLabelCandidate],
        canvasSize: CGSize,
        reservedBottomInset: Double = 0,
        fontSize: Double = 11
    ) -> [ConstellationLabelPlacement] {
        let sortedCandidates = candidates.sorted {
            if $0.priority == $1.priority {
                return $0.name.count < $1.name.count
            }
            return $0.priority > $1.priority
        }
        let reservedHeight = max(0, min(reservedBottomInset, canvasSize.height - 8))
        let availableHeight = max(0, canvasSize.height - reservedHeight - 8)
        let canvasRect = CGRect(x: 4, y: 4, width: max(0, canvasSize.width - 8), height: availableHeight)
        guard canvasRect.width > 0, canvasRect.height > 0 else { return [] }
        var acceptedPlacements: [ConstellationLabelPlacement] = []

        for candidate in sortedCandidates {
            let labelSize = estimateConstellationLabelSize(text: candidate.name, fontSize: fontSize)
            let placementOrigins = candidateLabelOrigins(anchor: candidate.anchor, labelSize: labelSize)

            for proposedOrigin in placementOrigins {
                let fittedOrigin = clampLabelOrigin(
                    proposedOrigin,
                    labelSize: labelSize,
                    canvasRect: canvasRect
                )
                let placement = ConstellationLabelPlacement(
                    name: candidate.name,
                    anchor: candidate.anchor,
                    origin: fittedOrigin,
                    size: labelSize
                )
                let paddedBounds = placement.bounds.insetBy(dx: -4, dy: -2)
                let overlapsExisting = acceptedPlacements.contains {
                    paddedBounds.intersects($0.bounds.insetBy(dx: -4, dy: -2))
                }
                if !overlapsExisting {
                    acceptedPlacements.append(placement)
                    break
                }
            }
        }

        return acceptedPlacements
    }

    nonisolated static func estimateConstellationLabelSize(
        text: String,
        fontSize: Double = 11
    ) -> CGSize {
        let measuredSize = NSString(string: text).size(
            withAttributes: [.font: PlatformFont.systemFont(ofSize: fontSize)]
        )
        return CGSize(
            width: ceil(max(measuredSize.width, fontSize * 2.6)),
            height: ceil(max(measuredSize.height, fontSize + 4))
        )
    }

    nonisolated private static func candidateLabelOrigins(anchor: CGPoint, labelSize: CGSize) -> [CGPoint] {
        let horizontalOffset = 8.0
        let verticalOffset = 6.0

        return [
            CGPoint(x: anchor.x + horizontalOffset, y: anchor.y - labelSize.height - verticalOffset),
            CGPoint(x: anchor.x + horizontalOffset, y: anchor.y + verticalOffset),
            CGPoint(x: anchor.x - labelSize.width - horizontalOffset, y: anchor.y - labelSize.height - verticalOffset),
            CGPoint(x: anchor.x - labelSize.width - horizontalOffset, y: anchor.y + verticalOffset),
            CGPoint(x: anchor.x - labelSize.width / 2, y: anchor.y - labelSize.height - 10),
            CGPoint(x: anchor.x - labelSize.width / 2, y: anchor.y + 8)
        ]
    }

    nonisolated private static func clampLabelOrigin(
        _ origin: CGPoint,
        labelSize: CGSize,
        canvasRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, canvasRect.minX), canvasRect.maxX - labelSize.width),
            y: min(max(origin.y, canvasRect.minY), canvasRect.maxY - labelSize.height)
        )
    }

    nonisolated private static func projectedCardinalLabelX(
        azimuthDegrees: Double,
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        roll: Double,
        fov: Double
    ) -> Double? {
        guard let point = projectPoint(
            size: size,
            centerAlt: centerAlt,
            centerAz: centerAz,
            roll: roll,
            fov: fov,
            altitudeDegrees: -1.5,
            azimuthDegrees: azimuthDegrees
        ) else {
            return nil
        }

        return clampedCardinalLabelX(point.x, sizeWidth: size.width)
    }

    nonisolated static func projectPoint(
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        roll: Double,
        fov: Double,
        altitudeDegrees: Double,
        azimuthDegrees: Double
    ) -> CGPoint? {
        let basis = cameraBasis(centerAlt: centerAlt, centerAz: centerAz, roll: roll)
        return projectPoint(
            cx: size.width / 2,
            cy: size.height / 2,
            scale: projectionScale(size: size, horizontalFOV: fov),
            forward: basis.forward,
            right: basis.right,
            up: basis.up,
            altitudeRadians: altitudeDegrees * .pi / 180,
            azimuthRadians: azimuthDegrees * .pi / 180
        )
    }

    nonisolated static func horizonLineValue(
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        roll: Double,
        fov: Double,
        point: CGPoint
    ) -> Double {
        let basis = cameraBasis(centerAlt: centerAlt, centerAz: centerAz, roll: roll)
        let coefficients = horizonLineCoefficients(
            cx: size.width / 2,
            cy: size.height / 2,
            scale: projectionScale(size: size, horizontalFOV: fov),
            forwardZ: basis.forward.z,
            rightZ: basis.right.z,
            upZ: basis.up.z
        )
        return coefficients.value(at: point)
    }

    nonisolated private static func altAzToCartesianStatic(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    nonisolated private static func cameraBasis(
        centerAlt: Double,
        centerAz: Double,
        roll: Double
    ) -> (
        forward: (x: Double, y: Double, z: Double),
        right: (x: Double, y: Double, z: Double),
        up: (x: Double, y: Double, z: Double)
    ) {
        let altitudeRadians = centerAlt * .pi / 180
        let azimuthRadians = centerAz * .pi / 180
        let rollRadians = roll * .pi / 180
        let forwardVector = altAzToCartesianStatic(alt: altitudeRadians, az: azimuthRadians)
        let forward = (x: forwardVector.0, y: forwardVector.1, z: forwardVector.2)
        let baseRight = (x: cos(azimuthRadians), y: -sin(azimuthRadians), z: 0.0)

        let upCrossX = baseRight.y * forward.z - baseRight.z * forward.y
        let upCrossY = baseRight.z * forward.x - baseRight.x * forward.z
        let upCrossZ = baseRight.x * forward.y - baseRight.y * forward.x
        let upLength = sqrt(upCrossX * upCrossX + upCrossY * upCrossY + upCrossZ * upCrossZ)
        let baseUp = upLength > 1e-10
            ? (x: upCrossX / upLength, y: upCrossY / upLength, z: upCrossZ / upLength)
            : (x: 0.0, y: 0.0, z: 1.0)
        let right = (
            x: baseRight.x * cos(rollRadians) - baseUp.x * sin(rollRadians),
            y: baseRight.y * cos(rollRadians) - baseUp.y * sin(rollRadians),
            z: baseRight.z * cos(rollRadians) - baseUp.z * sin(rollRadians)
        )
        let up = (
            x: baseRight.x * sin(rollRadians) + baseUp.x * cos(rollRadians),
            y: baseRight.y * sin(rollRadians) + baseUp.y * cos(rollRadians),
            z: baseRight.z * sin(rollRadians) + baseUp.z * cos(rollRadians)
        )
        return (forward: forward, right: right, up: up)
    }

    nonisolated private static func projectionScale(size: CGSize, horizontalFOV: Double) -> Double {
        let halfFovRad = max(0.01, (horizontalFOV / 2) * .pi / 180)
        return size.width / (2 * tan(halfFovRad))
    }

    nonisolated private static func projectPoint(
        cx: Double,
        cy: Double,
        scale: Double,
        forward: (x: Double, y: Double, z: Double),
        right: (x: Double, y: Double, z: Double),
        up: (x: Double, y: Double, z: Double),
        altitudeRadians: Double,
        azimuthRadians: Double
    ) -> CGPoint? {
        let point = altAzToCartesianStatic(alt: altitudeRadians, az: azimuthRadians)
        let dot = point.0 * forward.x + point.1 * forward.y + point.2 * forward.z
        guard dot > 0.1 else { return nil }

        let projectedX = (point.0 * right.x + point.1 * right.y + point.2 * right.z) / dot * scale
        let projectedY = (point.0 * up.x + point.1 * up.y + point.2 * up.z) / dot * scale
        return CGPoint(x: cx + projectedX, y: cy - projectedY)
    }

    nonisolated private static func horizonLineCoefficients(
        cx: Double,
        cy: Double,
        scale: Double,
        forwardZ: Double,
        rightZ: Double,
        upZ: Double
    ) -> HorizonLineCoefficients {
        HorizonLineCoefficients(
            a: rightZ,
            b: -upZ,
            c: forwardZ * scale - rightZ * cx + upZ * cy
        )
    }

    nonisolated private static func clippedGroundPolygon(
        in rect: CGRect,
        coefficients: HorizonLineCoefficients
    ) -> [CGPoint] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let epsilon = 1e-6
        var clipped: [CGPoint] = []

        for index in corners.indices {
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            let currentValue = coefficients.value(at: current)
            let nextValue = coefficients.value(at: next)
            let currentInside = currentValue <= epsilon
            let nextInside = nextValue <= epsilon

            if currentInside {
                clipped.append(current)
            }
            if currentInside != nextInside,
               let intersection = lineIntersection(
                from: current,
                to: next,
                startValue: currentValue,
                endValue: nextValue
               ) {
                clipped.append(intersection)
            }
        }

        return clipped
    }

    nonisolated private static func horizonLineSegment(
        in rect: CGRect,
        coefficients: HorizonLineCoefficients
    ) -> (CGPoint, CGPoint)? {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let epsilon = 1e-6
        var intersections: [CGPoint] = []

        func appendUnique(_ point: CGPoint) {
            let alreadyIncluded = intersections.contains { existing in
                abs(existing.x - point.x) < epsilon && abs(existing.y - point.y) < epsilon
            }
            if !alreadyIncluded {
                intersections.append(point)
            }
        }

        for index in corners.indices {
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            let currentValue = coefficients.value(at: current)
            let nextValue = coefficients.value(at: next)

            if abs(currentValue) < epsilon {
                appendUnique(current)
            }
            if currentValue * nextValue < 0,
               let intersection = lineIntersection(
                from: current,
                to: next,
                startValue: currentValue,
                endValue: nextValue
               ) {
                appendUnique(intersection)
            }
        }

        guard intersections.count >= 2 else { return nil }
        return (intersections[0], intersections[1])
    }

    nonisolated private static func lineIntersection(
        from start: CGPoint,
        to end: CGPoint,
        startValue: Double,
        endValue: Double
    ) -> CGPoint? {
        let denominator = startValue - endValue
        guard abs(denominator) > 1e-10 else { return nil }
        let t = startValue / denominator
        return CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }

    nonisolated private static func adjustedCenter(
        altitude: Double,
        azimuth: Double,
        translation: CGSize,
        scale: Double
    ) -> (alt: Double, az: Double) {
        let yawRadians = atan2(translation.width, scale)
        let pitchRadians = atan2(translation.height, scale)

        var adjustedAltitude = altitude + pitchRadians * 180 / .pi
        var adjustedAzimuth = azimuth - yawRadians * 180 / .pi

        adjustedAltitude = max(-10, min(89, adjustedAltitude))
        adjustedAzimuth = adjustedAzimuth.truncatingRemainder(dividingBy: 360)
        if adjustedAzimuth < 0 {
            adjustedAzimuth += 360
        }
        return (adjustedAltitude, adjustedAzimuth)
    }

    // MARK: - Drawing primitives

    private func drawStar(ctx: GraphicsContext, at point: CGPoint,
                          magnitude: Double, isDark: Bool, precomputedColor: Color,
                          altitude: Double = 90,
                          moonBrightness: Double = 0,
                          scintillationTime: Double = 0,
                          starRA: Double = 0) {
        let color = precomputedColor
        let radius = max(0.8, 5 - (magnitude + 1.5) * (4 / 4.5))
        let opacity = isDark ? 1.0 : max(0.1, 0.3 - magnitude * 0.05)
        let brightness = magnitude < 0 ? 1.0 : max(0.6, 1.0 - magnitude * 0.12)
        // 大気消光: 仰角 15° 以下で徐々に減光
        let extinction = altitude < 15 ? max(0, altitude / 15.0) : 1.0
        // 月光減衰: 月が明るいとき暗い星を減光
        let moonDimming = StarMapPalette.moonDimmingFactor(
            moonBrightness: moonBrightness, starMagnitude: magnitude
        )
        // シンチレーション: 明るい星の微小な明滅
        let scintillation = StarMapPalette.scintillation(
            starRA: starRA, magnitude: magnitude, altitude: altitude,
            isDark: isDark, time: scintillationTime
        )

        let finalOpacity = opacity * brightness * extinction * moonDimming * scintillation

        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(color.opacity(finalOpacity)))

        if magnitude < 2.0 {
            let glowR = radius * 3.0
            let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                                  width: glowR * 2, height: glowR * 2)
            ctx.fill(Circle().path(in: glowRect),
                     with: .color(color.opacity(0.12 * (isDark ? 1 : 0.3) * scintillation)))
        }

        if magnitude < 0.5 {
            let outerGlowR = radius * 5.0
            let outerRect = CGRect(x: point.x - outerGlowR, y: point.y - outerGlowR,
                                   width: outerGlowR * 2, height: outerGlowR * 2)
            ctx.fill(Circle().path(in: outerRect),
                     with: .color(color.opacity(0.04 * (isDark ? 1 : 0.2) * scintillation)))
        }
    }

    private func drawStarLabel(ctx: GraphicsContext, at point: CGPoint, name: String) {
        ctx.draw(
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65)),
            at: CGPoint(x: point.x + 7, y: point.y + 5))
    }
    private func drawCrosshair(ctx: GraphicsContext, cx: Double, cy: Double) {
        let r: Double = 12
        var path = Path()
        path.move(to: CGPoint(x: cx - r, y: cy))
        path.addLine(to: CGPoint(x: cx + r, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - r))
        path.addLine(to: CGPoint(x: cx, y: cy + r))
        ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
        let circleR: Double = 5
        ctx.stroke(
            Circle().path(in: CGRect(x: cx - circleR, y: cy - circleR,
                                     width: circleR * 2, height: circleR * 2)),
            with: .color(.white.opacity(0.5)), lineWidth: 1)
    }

    private func drawMoon(ctx: GraphicsContext, at point: CGPoint, phase: Double) {
        let radius: Double = 10
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(0.9)))

        let illumination = 1 - abs(phase * 2 - 1)
        if illumination < 0.98 {
            let shadowXScale = 1 - illumination * 2
            let shadowW = abs(shadowXScale) * radius * 2
            let shadowX = shadowXScale >= 0
                ? point.x - radius
                : point.x - radius + (radius * 2 - shadowW)
            let shadowRect = CGRect(x: shadowX, y: point.y - radius,
                                    width: shadowW, height: radius * 2)
            ctx.fill(Ellipse().path(in: shadowRect),
                     with: .color(Color.black.opacity(max(0, 1 - illumination))))
        }

        let glowR = radius * 1.8
        ctx.fill(Circle().path(in: CGRect(x: point.x - glowR, y: point.y - glowR,
                                           width: glowR * 2, height: glowR * 2)),
                 with: .color(.white.opacity(0.06)))
    }

    private func drawGalacticCenter(ctx: GraphicsContext, at point: CGPoint) {
        let r: Double = 8
        ctx.fill(
            Ellipse().path(in: CGRect(x: point.x - r*2, y: point.y - r,
                                       width: r*4, height: r*2)),
            with: .color(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.25)))
        ctx.fill(
            Circle().path(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(Color(red: 0.8, green: 0.6, blue: 1.0).opacity(0.85)))
    }

    // MARK: - Nearest Star (クリック判定用 — 心射図法)

    /// タップ/クリック座標に最も近い明るい星 (等級 ≤ 2.5) を返す。
    /// 閾値 (pt) 以内に星がなければ nil。
    private func nearestStar(at tapPoint: CGPoint, size: CGSize,
                               threshold: CGFloat = 25) -> StarPosition? {
        guard !viewModel.isGyroMode else { return nil }

        let fov = effectiveGnomonicFOV()
        let (centerAlt, centerAz) = effectiveGnomonicCenter(size: size)
        let projection = GnomonicProjectionContext(
            size: size,
            centerAlt: centerAlt,
            centerAz: centerAz,
            rollDegrees: 0,
            fov: fov
        )

        var nearest: StarPosition? = nil
        var nearestDist: CGFloat = threshold

        for pos in viewModel.starPositions where pos.star.magnitude <= 2.5 && pos.altitude > -3 {
            let alt = pos.altitude * .pi / 180
            let az = pos.azimuth * .pi / 180
            guard let screenPoint = projection.project(
                altitudeRadians: alt,
                azimuthRadians: az
            ) else {
                continue
            }
            let dx = screenPoint.x - tapPoint.x
            let dy = screenPoint.y - tapPoint.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < nearestDist {
                nearestDist = dist
                nearest = pos
            }
        }
        return nearest
    }

    // MARK: - Drag Gesture (心射図法 カメラ空間ドラッグ)

    private func gnomonicDragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { [self] value in
                let fov = effectiveGnomonicFOV()
                let scale = Self.projectionScale(size: size, horizontalFOV: fov)
                let adjustedCenter = Self.adjustedCenter(
                    altitude: viewModel.viewAltitude,
                    azimuth: viewModel.viewAzimuth,
                    translation: value.translation,
                    scale: scale
                )
                viewModel.viewAltitude = adjustedCenter.alt
                viewModel.viewAzimuth = adjustedCenter.az
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
                guard allowsManualFOVAdjustment else { return }
                viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov / value)
            }
    }

#if os(macOS)
    private func installMacScrollWheelMonitor() {
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            handleMacScrollWheel(event)
        }
    }

    private func removeMacScrollWheelMonitor() {
        guard let scrollWheelMonitor else { return }
        NSEvent.removeMonitor(scrollWheelMonitor)
        self.scrollWheelMonitor = nil
    }

    private func handleMacScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard isPointerOverCanvas, allowsManualFOVAdjustment else {
            return event
        }
        let updatedFOV = Self.zoomedFOV(
            currentFOV: viewModel.fov,
            scrollDeltaY: event.scrollingDeltaY,
            preciseScrolling: event.hasPreciseScrollingDeltas
        )
        if updatedFOV != viewModel.fov {
            viewModel.fov = updatedFOV
        }
        return nil
    }
#endif

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

private extension StarMapCanvasView {
    // MARK: Planet

    func planetColor(name: String) -> Color {
        switch name {
        case "水星": return Color(red: 0.75, green: 0.72, blue: 0.68)
        case "金星": return Color(red: 1.00, green: 0.95, blue: 0.80)
        case "火星": return Color(red: 1.00, green: 0.45, blue: 0.25)
        case "木星": return Color(red: 1.00, green: 0.90, blue: 0.70)
        case "土星": return Color(red: 0.95, green: 0.85, blue: 0.60)
        default:     return .white
        }
    }

    func drawPlanet(ctx: GraphicsContext, at point: CGPoint, planet: PlanetPosition) {
        let color = planetColor(name: planet.name)
        // magnitude → radius (bigger = brighter)
        let mag    = max(-5.5, min(3.0, planet.magnitude))
        let radius = max(2.0, 8.0 - (mag + 2.0) * (5.0 / 5.0))

        // Core disk
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect), with: .color(color.opacity(0.95)))

        // Glow for bright planets
        if mag < 0 {
            let gr = radius * 3.5
            ctx.fill(
                Circle().path(in: CGRect(x: point.x - gr, y: point.y - gr,
                                          width: gr * 2, height: gr * 2)),
                with: .color(color.opacity(0.15)))
        }

        // Label
        ctx.draw(
            Text(planet.localizedName)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.75)),
            at: CGPoint(x: point.x + radius + 5, y: point.y + 4))
    }

    // MARK: Meteor Shower Radiant

    func drawMeteorShowerRadiant(ctx: GraphicsContext, at point: CGPoint, shower: MeteorShower) {
        let color = StarMapPalette.meteorAccent
        let radius: CGFloat = 10
        // 放射アイコン（円 + 矢印風の短線）
        let circleRect = CGRect(x: point.x - radius, y: point.y - radius,
                                width: radius * 2, height: radius * 2)
        ctx.stroke(Circle().path(in: circleRect),
                   with: .color(color.opacity(0.7)), lineWidth: 1.2)
        // 中心点
        ctx.fill(Circle().path(in: CGRect(x: point.x - 2, y: point.y - 2,
                                          width: 4, height: 4)),
                 with: .color(color.opacity(0.9)))
        // 放射線（4方向）
        let rays: [(CGFloat, CGFloat)] = [(0,-1),(0,1),(-1,0),(1,0)]
        for (dx, dy) in rays {
            var ray = Path()
            ray.move(to: CGPoint(x: point.x + dx * (radius + 2),
                                  y: point.y + dy * (radius + 2)))
            ray.addLine(to: CGPoint(x: point.x + dx * (radius + 7),
                                     y: point.y + dy * (radius + 7)))
            ctx.stroke(ray, with: .color(color.opacity(0.6)), lineWidth: 1)
        }
        // ラベル
        ctx.draw(
            Text(shower.localizedName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color.opacity(0.85)),
            at: CGPoint(x: point.x + radius + 4, y: point.y + 4))
    }

    // MARK: - Gnomonic Milky Way Band

    /// 天の川バンドを心射図法に描画する。
    /// 各バンドポイント間をトラペゾイドスラブで塗りつぶす。
    func drawGnomonicMilkyWayBand(ctx: GraphicsContext,
                                   project: (Double, Double) -> CGPoint?) {
        let bandPoints = viewModel.milkyWayBandPoints
        guard bandPoints.count > 1 else { return }

        // マルチレイヤー定義: (幅倍率, 不透明度倍率)
        // 外側から描画し、中心ほど狭く明るくすることでガウシアン的フォールオフを再現
        let layers: [(widthScale: Double, opacityScale: Double)] = [
            (1.4, 0.25),   // 外側グロー — 広く薄い
            (1.0, 0.50),   // 中間層
            (0.6, 1.00),   // コア — 狭く明るい
        ]

        // 天の川レイヤーをサブコンテキストに描画し、ブラーで柔らかくする
        var milkyWayCtx = ctx
        milkyWayCtx.addFilter(.blur(radius: 6))

        for layer in layers {
            for i in 0..<bandPoints.count - 1 {
                let bp0 = bandPoints[i]
                let bp1 = bandPoints[i + 1]

                // ラップアラウンドの不連続をスキップ
                let azDiff = atan2(
                    sin((bp0.az - bp1.az) * .pi / 180),
                    cos((bp0.az - bp1.az) * .pi / 180)
                ) * 180 / .pi
                guard abs(azDiff) < 40 else { continue }

                let a0 = bp0.alt * .pi / 180
                let z0 = bp0.az * .pi / 180
                let h0 = bp0.halfH * .pi / 180 * layer.widthScale
                let a1 = bp1.alt * .pi / 180
                let z1 = bp1.az * .pi / 180
                let h1 = bp1.halfH * .pi / 180 * layer.widthScale

                guard let p0Top = project(a0 + h0, z0),
                      let p0Bot = project(a0 - h0, z0),
                      let p1Top = project(a1 + h1, z1),
                      let p1Bot = project(a1 - h1, z1) else { continue }

                // スクリーン上の大きなジャンプをスキップ（投影の不連続対策）
                let maxJump: Double = 800
                guard abs(p0Top.x - p1Top.x) < maxJump,
                      abs(p0Top.y - p1Top.y) < maxJump,
                      abs(p0Bot.x - p1Bot.x) < maxJump,
                      abs(p0Bot.y - p1Bot.y) < maxJump else { continue }

                var slab = Path()
                slab.move(to: p0Top)
                slab.addLine(to: p1Top)
                slab.addLine(to: p1Bot)
                slab.addLine(to: p0Bot)
                slab.closeSubpath()

                // 銀河中心（銀経 0°/360°）からの角距離で輝度を計算
                let lDeg = bp0.li <= 180 ? bp0.li : 360 - bp0.li
                let tCenter = 1.0 - lDeg / 180.0  // 1.0 = 銀河中心, 0.0 = 反銀心

                // 銀河中心付近: 暖色（淡いアンバー/ゴールド）
                // 反銀心付近: 冷色（淡いブルー）
                let red   = 0.55 + 0.30 * tCenter
                let green = 0.55 + 0.15 * tCenter
                let blue  = 0.85 - 0.35 * tCenter
                let slabColor = Color(red: red, green: green, blue: blue)

                // 銀河中心方向を明るくし、反銀心は暗くする
                let brightnessBoost = 0.6 + 0.4 * tCenter
                let baseOpacity = 0.08 * layer.opacityScale * brightnessBoost

                milkyWayCtx.fill(slab, with: .color(slabColor.opacity(baseOpacity)))
            }
        }
    }

    // MARK: - Gnomonic Terrain Silhouette

    /// 地形シルエットを心射図法に描画する。
    /// カメラの FOV より広い方位角範囲をスイープし、投影可能な点のみ描画する。
    func drawGnomonicTerrainSilhouette(ctx: GraphicsContext,
                                        project: (Double, Double) -> CGPoint?,
                                        centerAz: Double, fov: Double,
                                        size: CGSize,
                                        terrain: TerrainProfile) {
        let sweepRange = max(fov * 1.5, 90.0)
        let steps = 120

        var ridgePoints: [CGPoint] = []
        ridgePoints.reserveCapacity(steps + 1)

        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            var az = centerAz + (fraction - 0.5) * sweepRange
            az = az.truncatingRemainder(dividingBy: 360)
            if az < 0 { az += 360 }

            let hAngle = terrain.horizonAngle(forAzimuth: az)
            let altRad = max(hAngle, 0) * .pi / 180
            let azRad = (centerAz + (fraction - 0.5) * sweepRange) * .pi / 180

            if let pt = project(altRad, azRad) {
                guard pt.x > -200 && pt.x < size.width + 200 &&
                      pt.y > -200 && pt.y < size.height + 200 else { continue }
                ridgePoints.append(pt)
            }
        }

        guard ridgePoints.count > 1 else { return }

        var path = Path()
        path.move(to: ridgePoints[0])
        for i in 1..<ridgePoints.count {
            path.addLine(to: ridgePoints[i])
        }
        path.addLine(to: CGPoint(x: ridgePoints[ridgePoints.count - 1].x, y: size.height + 10))
        path.addLine(to: CGPoint(x: ridgePoints[0].x, y: size.height + 10))
        path.closeSubpath()
        ctx.fill(
            path,
            with: .color(
                horizonOverlayStyle.terrainFillColor.opacity(horizonOverlayStyle.terrainFillOpacity)
            )
        )

        var ridgePath = Path()
        ridgePath.move(to: ridgePoints[0])
        for i in 1..<ridgePoints.count {
            ridgePath.addLine(to: ridgePoints[i])
        }
        ctx.stroke(ridgePath,
                   with: .color(horizonOverlayStyle.terrainStrokeColor),
                   lineWidth: 1.5)
    }
}

extension StarMapCanvasView {
    /// スクロール量からズーム後の視野角を計算します。
    nonisolated static func zoomedFOV(currentFOV: Double, scrollDeltaY: Double, preciseScrolling: Bool) -> Double {
        let sensitivity = preciseScrolling ? 1.2 : 4.0
        return StarMapLayout.clampedFOV(currentFOV - scrollDeltaY * sensitivity)
    }
}

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return StarMapCanvasView(viewModel: vm)
        .frame(width: 400, height: 500)
}
