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
                installMacScrollWheelMonitor()
#endif
            }
            .onDisappear {
#if os(macOS)
                removeMacScrollWheelMonitor()
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
                handleAltitudeKey(step: StarMapLayout.directionStep, size: size)
            }
            .onKeyPress(.downArrow) {
                handleAltitudeKey(step: -StarMapLayout.directionStep, size: size)
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
        let displayFov = StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale))

        return VStack {
            Spacer()
            Text(String(format: "視野 %.0f°", displayFov))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 24)
        }
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

    private func handleAltitudeKey(step: Double, size: CGSize) -> KeyPress.Result {
        viewModel.viewAltitude = max(-10, min(89, viewModel.viewAltitude + step))
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
        let placements = cardinalLabelPlacements(size: size)

        return ZStack {
            ForEach(placements) { placement in
                Text(placement.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, StarMapLayout.cardinalLabelHorizontalPadding)
                    .padding(.vertical, StarMapLayout.cardinalLabelVerticalPadding)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .position(
                        x: placement.x,
                        y: Self.cardinalOverlayY(sizeHeight: size.height)
                    )
                    .allowsHitTesting(false)
            }
        }
    }


    // MARK: - Gnomonic Projection (心射図法)

    /// ピンチ中のライブ視野角（心射図法用）
    private func effectiveGnomonicFOV() -> Double {
        StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale))
    }

    /// ドラッグ中のライブ中心方向（心射図法用）。
    /// スクリーン移動量をカメラ空間の角度変化に正確に変換する。
    private func effectiveGnomonicCenter(size: CGSize) -> (alt: Double, az: Double) {
        guard gestureDragOffset != .zero else {
            return (viewModel.viewAltitude, viewModel.viewAzimuth)
        }
        let fov = effectiveGnomonicFOV()
        let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
        let scale = min(size.width, size.height) / (2 * tan(halfFovRad))

        // スクリーン移動 → カメラ空間の角度変化 (atan で正確に)
        let yawRad = atan2(gestureDragOffset.width, scale)
        let pitchRad = atan2(gestureDragOffset.height, scale)

        var newAlt = viewModel.viewAltitude + pitchRad * 180 / .pi
        var newAz = viewModel.viewAzimuth - yawRad * 180 / .pi

        newAlt = max(-10, min(89, newAlt))
        newAz = newAz.truncatingRemainder(dividingBy: 360)
        if newAz < 0 { newAz += 360 }
        return (newAlt, newAz)
    }


    private func drawGnomonicProjection(ctx: GraphicsContext,
                                        cx: Double, cy: Double, size: CGSize,
                                        centerAlt: Double, centerAz: Double, fov: Double) {
        let simplifyDuringScrub = viewModel.isTimeSliderScrubbing
        let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
        let scale = min(size.width, size.height) / (2 * tan(halfFovRad))

        let cAlt = centerAlt * .pi / 180
        let cAz  = centerAz * .pi / 180

        // カメラ中心方向 (forward)
        let (fwdX, fwdY, fwdZ) = altAzToCartesian(alt: cAlt, az: cAz)

        // 水平右方向ベクトル (方位に直交、水平面内)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)
        let rightZ = 0.0

        // 上方向ベクトル = right × forward, 正規化
        let uCrossX = rightY * fwdZ - rightZ * fwdY
        let uCrossY = rightZ * fwdX - rightX * fwdZ
        let uCrossZ = rightX * fwdY - rightY * fwdX
        let uLen = sqrt(uCrossX * uCrossX + uCrossY * uCrossY + uCrossZ * uCrossZ)
        let (upX, upY, upZ) = uLen > 1e-10
            ? (uCrossX / uLen, uCrossY / uLen, uCrossZ / uLen)
            : (0.0, 0.0, 1.0)

        func project(alt: Double, az: Double) -> CGPoint? {
            let (px, py, pz) = altAzToCartesian(alt: alt, az: az)
            let dot = px * fwdX + py * fwdY + pz * fwdZ
            guard dot > 0.1 else { return nil }
            let projX = (px * rightX + py * rightY + pz * rightZ) / dot * scale
            let projY = (px * upX    + py * upY    + pz * upZ)    / dot * scale
            return CGPoint(x: cx + projX, y: cy - projY)
        }

        // 地平線・地面描画
        let horizonScreenY = Self.horizonScreenY(centerAlt: centerAlt, cy: cy, scale: scale)
        drawGnomonicGround(ctx: ctx, cx: cx, cy: cy, size: size,
                           centerAlt: centerAlt, scale: scale,
                           fwdX: fwdX, fwdY: fwdY, fwdZ: fwdZ,
                           upX: upX, upY: upY, upZ: upZ,
                           horizonScreenY: horizonScreenY)

        // 星座線
        var constPath = Path()
        for line in viewModel.constellationLines {
            let a1 = max(line.startAlt, -5) * .pi / 180
            let a2 = max(line.endAlt,   -5) * .pi / 180
            if let p1 = project(alt: a1, az: line.startAz * .pi / 180),
               let p2 = project(alt: a2, az: line.endAz   * .pi / 180) {
                constPath.move(to: p1)
                constPath.addLine(to: p2)
            }
        }
        ctx.stroke(constPath,
                   with: .color(Color(red: 0.4, green: 0.6, blue: 0.9).opacity(0.35)),
                   lineWidth: 1)

        // 天の川バンド（星座線の上、恒星の下に描画）
        if viewModel.isNight {
            drawGnomonicMilkyWayBand(ctx: ctx, project: project)
        }

        // 恒星
        for pos in viewModel.starPositions {
            // 地平線近くの暗い星をスキップ
            if pos.altitude < 5 && pos.star.magnitude > 6.0 { continue }
            let alt = pos.altitude * .pi / 180
            let az  = pos.azimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                         isDark: viewModel.isNight, precomputedColor: pos.precomputedColor,
                         altitude: pos.altitude)
                if !simplifyDuringScrub, pos.star.magnitude < 1.5, !pos.star.name.isEmpty {
                    drawStarLabel(ctx: ctx, at: pt, name: pos.star.name)
                }
            }
        }

        // 星座名ラベル
        if !simplifyDuringScrub {
            for label in viewModel.constellationLabels {
                let alt = label.alt * .pi / 180
                let az  = label.az  * .pi / 180
                if let pt = project(alt: alt, az: az) {
                    ctx.draw(
                        Text(label.name)
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.45)),
                        at: pt)
                }
            }
        }

        // 月
        if viewModel.moonAltitude > -1 {
            let alt = viewModel.moonAltitude * .pi / 180
            if let pt = project(alt: alt, az: viewModel.moonAzimuth * .pi / 180) {
                drawMoon(ctx: ctx, at: pt, phase: viewModel.moonPhase)
            }
        }

        // 銀河系中心
        if viewModel.galacticCenterAltitude > -1 {
            let alt = viewModel.galacticCenterAltitude * .pi / 180
            if let pt = project(alt: alt, az: viewModel.galacticCenterAzimuth * .pi / 180) {
                drawGalacticCenter(ctx: ctx, at: pt)
            }
        }

        // 惑星
        for planet in viewModel.planetPositions where planet.altitude > -1 {
            let alt = planet.altitude * .pi / 180
            if let pt = project(alt: alt, az: planet.azimuth * .pi / 180) {
                drawPlanet(ctx: ctx, at: pt, planet: planet)
            }
        }

        // 流星群放射点
        for radiant in viewModel.meteorShowerRadiants where radiant.altitude > -1 {
            let alt = radiant.altitude * .pi / 180
            if let pt = project(alt: alt, az: radiant.azimuth * .pi / 180) {
                drawMeteorShowerRadiant(ctx: ctx, at: pt, shower: radiant.shower)
            }
        }

        // 地形シルエット（最前面: 天体を自然に隠す）
        if let terrain = viewModel.terrainProfile {
            drawGnomonicTerrainSilhouette(ctx: ctx, project: project,
                                           centerAz: centerAz, fov: fov,
                                           size: size, terrain: terrain)
        }

        drawCrosshair(ctx: ctx, cx: cx, cy: cy)
    }

    private func altAzToCartesian(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    // MARK: - Gnomonic Ground / Horizon / Cardinals

    /// 地平線と地面を解析的に描画する。
    /// 心射図法では地平線（大円）は直線に射影されるため、
    /// カメラの仰角から地平線の Y 座標を直接計算する。
    static func horizonScreenY(centerAlt: Double, cy: Double, scale: Double) -> Double {
        let cAltRad = centerAlt * .pi / 180
        let horizonProjY = -tan(cAltRad) * scale
        return cy - horizonProjY
    }

    private func drawGnomonicGround(ctx: GraphicsContext,
                                    cx: Double, cy: Double, size: CGSize,
                                    centerAlt: Double, scale: Double,
                                    fwdX: Double, fwdY: Double, fwdZ: Double,
                                    upX: Double, upY: Double, upZ: Double,
                                    horizonScreenY: Double) {

        // 地面色 (暗い緑/茶)
        let groundColor = Color(red: 0.08, green: 0.12, blue: 0.06)

        if horizonScreenY < size.height {
            // 地平線が画面内にある場合: 地平線より下を地面色で塗る
            let groundRect = CGRect(x: 0, y: horizonScreenY,
                                    width: size.width,
                                    height: size.height - horizonScreenY)
            ctx.fill(Path(groundRect), with: .color(groundColor.opacity(0.6)))

            // 地平線ライン
            var horizonPath = Path()
            horizonPath.move(to: CGPoint(x: 0, y: horizonScreenY))
            horizonPath.addLine(to: CGPoint(x: size.width, y: horizonScreenY))
            ctx.stroke(horizonPath,
                       with: .color(Color(red: 0.3, green: 0.5, blue: 0.3).opacity(0.5)),
                       lineWidth: 1)
        } else if centerAlt < 0 {
            // カメラが地平線より下を向いている: 全面地面
            let groundRect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(groundRect), with: .color(groundColor.opacity(0.6)))
        }
    }

    private func cardinalLabelPlacements(size: CGSize) -> [CardinalOverlayPlacement] {
        let center = effectiveGnomonicCenter(size: size)
        return Self.cardinalLabelPlacements(
            size: size,
            centerAlt: center.alt,
            centerAz: center.az,
            fov: effectiveGnomonicFOV()
        )
    }

    static func cardinalLabelPlacements(
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
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

    static func clampedCardinalLabelX(_ x: Double, sizeWidth: Double) -> Double {
        let minX = Double(StarMapLayout.cardinalLabelSidePadding)
        let maxX = sizeWidth - Double(StarMapLayout.cardinalLabelSidePadding)
        return min(max(x, minX), maxX)
    }

    static func cardinalOverlayY(sizeHeight: Double) -> Double {
        sizeHeight - Double(StarMapLayout.cardinalLabelBottomInset)
    }

    private static func projectedCardinalLabelX(
        azimuthDegrees: Double,
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        fov: Double
    ) -> Double? {
        let cx = size.width / 2
        let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
        let scale = min(size.width, size.height) / (2 * tan(halfFovRad))

        let cAlt = centerAlt * .pi / 180
        let cAz = centerAz * .pi / 180
        let (fwdX, fwdY, fwdZ) = altAzToCartesianStatic(alt: cAlt, az: cAz)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)
        let rightZ = 0.0

        let alt = -1.5 * .pi / 180
        let az = azimuthDegrees * .pi / 180
        let (px, py, pz) = altAzToCartesianStatic(alt: alt, az: az)
        let dot = px * fwdX + py * fwdY + pz * fwdZ
        guard dot > 0.1 else { return nil }

        let projX = (px * rightX + py * rightY + pz * rightZ) / dot * scale
        return clampedCardinalLabelX(cx + projX, sizeWidth: size.width)
    }

    private static func altAzToCartesianStatic(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    // MARK: - Drawing primitives

    private func drawStar(ctx: GraphicsContext, at point: CGPoint,
                          magnitude: Double, isDark: Bool, precomputedColor: Color,
                          altitude: Double = 90) {
        let color = precomputedColor
        let radius = max(0.8, 5 - (magnitude + 1.5) * (4 / 4.5))
        let opacity = isDark ? 1.0 : max(0.1, 0.3 - magnitude * 0.05)
        let brightness = magnitude < 0 ? 1.0 : max(0.6, 1.0 - magnitude * 0.12)
        // 大気消光: 仰角 15° 以下で徐々に減光
        let extinction = altitude < 15 ? max(0, altitude / 15.0) : 1.0

        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(color.opacity(opacity * brightness * extinction)))

        if magnitude < 2.0 {
            let glowR = radius * 3.0
            let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                                  width: glowR * 2, height: glowR * 2)
            ctx.fill(Circle().path(in: glowRect),
                     with: .color(color.opacity(0.12 * (isDark ? 1 : 0.3))))
        }

        if magnitude < 0.5 {
            let outerGlowR = radius * 5.0
            let outerRect = CGRect(x: point.x - outerGlowR, y: point.y - outerGlowR,
                                   width: outerGlowR * 2, height: outerGlowR * 2)
            ctx.fill(Circle().path(in: outerRect),
                     with: .color(color.opacity(0.04 * (isDark ? 1 : 0.2))))
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
        let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
        let scale = min(size.width, size.height) / (2 * tan(halfFovRad))
        let cx = size.width / 2
        let cy = size.height / 2

        let (centerAlt, centerAz) = effectiveGnomonicCenter(size: size)
        let cAlt = centerAlt * .pi / 180
        let cAz = centerAz * .pi / 180

        let (fwdX, fwdY, fwdZ) = altAzToCartesian(alt: cAlt, az: cAz)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)
        let uCrossX = rightY * fwdZ
        let uCrossY = -rightX * fwdZ
        let uCrossZ = rightX * fwdY - rightY * fwdX
        let uLen = sqrt(uCrossX * uCrossX + uCrossY * uCrossY + uCrossZ * uCrossZ)
        let (upX, upY, upZ) = uLen > 1e-10
            ? (uCrossX / uLen, uCrossY / uLen, uCrossZ / uLen)
            : (0.0, 0.0, 1.0)

        var nearest: StarPosition? = nil
        var nearestDist: CGFloat = threshold

        for pos in viewModel.starPositions where pos.star.magnitude <= 2.5 && pos.altitude > -3 {
            let alt = pos.altitude * .pi / 180
            let az = pos.azimuth * .pi / 180
            let (px, py, pz) = altAzToCartesian(alt: alt, az: az)
            let dot = px * fwdX + py * fwdY + pz * fwdZ
            guard dot > 0.1 else { continue }
            let projX = (px * rightX + py * rightY) / dot * scale
            let projY = (px * upX + py * upY + pz * upZ) / dot * scale
            let sx = cx + projX
            let sy = cy - projY
            let dx = sx - tapPoint.x
            let dy = sy - tapPoint.y
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
                let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
                let scale = min(size.width, size.height) / (2 * tan(halfFovRad))

                let yawRad = atan2(value.translation.width, scale)
                let pitchRad = atan2(value.translation.height, scale)

                var newAlt = viewModel.viewAltitude + pitchRad * 180 / .pi
                var newAz = viewModel.viewAzimuth - yawRad * 180 / .pi

                newAlt = max(-10, min(89, newAlt))
                newAz = newAz.truncatingRemainder(dividingBy: 360)
                if newAz < 0 { newAz += 360 }

                viewModel.viewAltitude = newAlt
                viewModel.viewAzimuth = newAz
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
                viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov / value)
            }
    }

#if os(macOS)
    private func installMacScrollWheelMonitor() {
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [viewModel] event in
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
    }

    private func removeMacScrollWheelMonitor() {
        guard let scrollWheelMonitor else { return }
        NSEvent.removeMonitor(scrollWheelMonitor)
        self.scrollWheelMonitor = nil
    }
#endif

    private func onCanvasAppear(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewModel.updateCanvasSize(size)
        viewModel.applyInitialPoseIfNeeded()
    }

    // MARK: - Gyro Mode Indicator

    private var gyroModeIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Text(String(format: "方位 %.0f° 仰角 %.0f°",
                            viewModel.viewAzimuth,
                            viewModel.viewAltitude))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.trailing, Spacing.sm)
                    .padding(.top, Spacing.sm)
            }
            Spacer()
        }
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
            Text(planet.name)
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
            Text(shower.name)
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
            let h0 = bp0.halfH * .pi / 180
            let a1 = bp1.alt * .pi / 180
            let z1 = bp1.az * .pi / 180
            let h1 = bp1.halfH * .pi / 180

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

            let lDeg = bp0.li <= 180 ? bp0.li : 360 - bp0.li
            let tCenter = 1.0 - lDeg / 180.0
            let slabColor = Color(red: 0.50 + 0.20 * tCenter,
                                  green: 0.55,
                                  blue: 0.85 - 0.25 * tCenter)
            ctx.fill(slab, with: .color(slabColor.opacity(0.10)))
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
        let fillColor = StarMapPalette.groundFill
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
        path.addLine(to: CGPoint(x: ridgePoints.last!.x, y: size.height + 10))
        path.addLine(to: CGPoint(x: ridgePoints.first!.x, y: size.height + 10))
        path.closeSubpath()
        ctx.fill(path, with: .color(fillColor))

        var ridgePath = Path()
        ridgePath.move(to: ridgePoints[0])
        for i in 1..<ridgePoints.count {
            ridgePath.addLine(to: ridgePoints[i])
        }
        ctx.stroke(ridgePath,
                   with: .color(Color(red: 0.2, green: 0.35, blue: 0.15).opacity(0.4)),
                   lineWidth: 1.5)
    }
}

extension StarMapCanvasView {
    static func zoomedFOV(currentFOV: Double, scrollDeltaY: Double, preciseScrolling: Bool) -> Double {
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
