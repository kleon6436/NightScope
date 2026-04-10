import SwiftUI

// MARK: - StarMapCanvasView

/// 星空マップを描画する共有ビュー (iPhone / Mac 共通)
/// - パノラマモード: 円筒等距離図法 (地平線が水平, ドラッグで方位を切り替え)
/// - ジャイロモード: 心射図法 (viewAltitude/viewAzimuth が画面中心, iPhone 専用)
struct StarMapCanvasView: View {
    @ObservedObject var viewModel: StarMapViewModel

    /// クリック/タップで天体を選択したときに呼ばれるコールバック (macOS で使用)
    var onStarSelected: ((StarPosition) -> Void)? = nil

    // ドラッグ中の一時オフセット (ピクセル単位, 横・縦)
    @GestureState private var gestureDragOffset: CGSize = .zero
    // 累積ドラッグ量 (onEnded で viewAzimuth/viewAltitude に反映済み, 常に 0)
    @State private var dragPixelOffset: Double = 0
    @State private var dragPixelOffsetY: Double = 0

    @GestureState private var gestureScale: Double = 1.0

    // キーボードフォーカス
    @FocusState private var isFocused: Bool
#if os(macOS)
    @State private var scrollEventMonitor: Any?
#endif

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvas(size: geo.size)
                    .gesture(
                        viewModel.isGyroMode ? nil : panoramaDragGesture(width: geo.size.width)
                    )
                    .gesture(pinchGesture)
                    .onTapGesture(coordinateSpace: .local) { location in
                        isFocused = true
                        if let star = nearestStar(at: location, size: geo.size) {
                            onStarSelected?(star)
                        }
                    }

                if viewModel.isGyroMode {
                    gyroModeIndicator
                }

                // ピンチ中のみ視野角を表示
                if gestureScale != 1.0 {
                    let displayFov = max(30.0, min(150.0, viewModel.fov / max(0.1, gestureScale)))
                    VStack {
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
            }
            .focusable()
            .focused($isFocused)
            // MARK: Keyboard Navigation (デフォルト phases = [.down, .repeat])
            .onKeyPress(.leftArrow) {
                var az = viewModel.viewAzimuth - 5
                if az < 0 { az += 360 }
                viewModel.viewAzimuth = az
                return .handled
            }
            .onKeyPress(.rightArrow) {
                var az = viewModel.viewAzimuth + 5
                az = az.truncatingRemainder(dividingBy: 360)
                viewModel.viewAzimuth = az
                return .handled
            }
            .onKeyPress(.upArrow) {
                viewModel.viewAltitude = min(90, viewModel.viewAltitude + 5)
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.viewAltitude = max(-45, viewModel.viewAltitude - 5)
                return .handled
            }
            .onKeyPress(KeyEquivalent("=")) {
                // ズームイン (視野を狭める)
                viewModel.fov = max(30, viewModel.fov - 10)
                return .handled
            }
            .onKeyPress(KeyEquivalent("-")) {
                // ズームアウト (視野を広げる)
                viewModel.fov = min(150, viewModel.fov + 10)
                return .handled
            }
            .onKeyPress(KeyEquivalent("n")) {
                viewModel.resetToNorth()
                return .handled
            }
        }
        .background(Color(red: 0.02, green: 0.04, blue: 0.12))
#if os(macOS)
        .onAppear {
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let delta = event.scrollingDeltaY
                guard delta != 0 else { return event }
                Task { @MainActor in
                    viewModel.fov = max(30, min(150, viewModel.fov - delta))
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
                scrollEventMonitor = nil
            }
        }
#endif
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        Canvas { ctx, sz in
            let cx = sz.width / 2
            let cy = sz.height / 2

            if viewModel.isGyroMode {
                drawGnomonicProjection(ctx: ctx, cx: cx, cy: cy, size: sz)
            } else {
                drawPanoramicProjection(ctx: ctx, cx: cx, cy: cy, size: sz)
            }
        }
    }

    // MARK: - Panoramic Projection (水平パノラマ, 円筒等距離図法)

    /// リアルタイムのドラッグオフセットを考慮した表示方向 (alt, az) を返す。
    /// 天頂 (alt > 90°) を越えたときは方位を反転し折り返す。
    private func effectiveViewDirection(hScale: Double) -> (alt: Double, az: Double) {
        let rawAlt = viewModel.viewAltitude
            - (dragPixelOffsetY + gestureDragOffset.height) / hScale
        let azDelta = (dragPixelOffset + gestureDragOffset.width) / hScale
        var az = viewModel.viewAzimuth - azDelta
        var alt = rawAlt
        if alt > 90 {
            // 天頂折り返し: 頭を後ろに倒すと反対方位の空が見える
            alt = 180 - alt
            az += 180
        }
        // 地面方向は -90° でクランプ
        alt = max(-90, min(90, alt))
        az = az.truncatingRemainder(dividingBy: 360)
        if az < 0 { az += 360 }
        return (alt: alt, az: az)
    }

    private func drawPanoramicProjection(ctx: GraphicsContext,
                                         cx: Double, cy: Double, size: CGSize) {
        // 水平視野: ピンチで調整可能 (30°〜150°), デフォルト 90°
        let hFOV = max(30.0, min(150.0, viewModel.fov / max(0.1, gestureScale)))
        let hScale = size.width / hFOV           // pt/degree
        let (alt0, az0) = effectiveViewDirection(hScale: hScale)
        let horizonY = cy + alt0 * hScale        // 動的地平線Y座標（画面中心 = 視点高度）

        // ---- 地面の塗りつぶし ----
        if horizonY < size.height {
            let groundY = max(0.0, horizonY)
            let groundPath = Path(CGRect(x: 0, y: groundY,
                                          width: size.width, height: size.height - groundY))
            ctx.fill(groundPath, with: .color(Color(red: 0.06, green: 0.04, blue: 0.02)))
        }

        // ---- 地平線ライン ----
        if horizonY >= 0 && horizonY <= size.height {
            var horizPath = Path()
            horizPath.move(to: CGPoint(x: 0, y: horizonY))
            horizPath.addLine(to: CGPoint(x: size.width, y: horizonY))
            ctx.stroke(horizPath, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }

        // ---- 星座線 ----
        drawPanoramicConstellationLines(ctx: ctx, cx: cx, horizonY: horizonY,
                                        hScale: hScale, az0: az0)

        // ---- 恒星 ----
        for pos in viewModel.starPositions {
            guard pos.altitude > -3 else { continue }
            let pt = panoramicPoint(alt: pos.altitude, az: pos.azimuth,
                                     cx: cx, horizonY: horizonY,
                                     hScale: hScale, az0: az0)
            guard isVisible(x: pt.x, width: size.width) else { continue }
            drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                     isDark: viewModel.isNight)
            if pos.star.magnitude < 1.5, !pos.star.name.isEmpty {
                drawStarLabel(ctx: ctx, at: pt, name: pos.star.name)
            }
        }

        // ---- 星座名ラベル ----
        drawPanoramicConstellationLabels(ctx: ctx, cx: cx, horizonY: horizonY,
                                         hScale: hScale, az0: az0)

        // ---- 太陽 ----
        if viewModel.sunAltitude > -10 {
            let pt = panoramicPoint(alt: viewModel.sunAltitude, az: viewModel.sunAzimuth,
                                     cx: cx, horizonY: horizonY, hScale: hScale, az0: az0)
            if isVisible(x: pt.x, width: size.width) {
                let opacity = viewModel.sunAltitude > 0 ? 0.9
                              : max(0, 0.3 + viewModel.sunAltitude / 18)
                drawSunSymbol(ctx: ctx, at: pt, radius: 12, opacity: opacity)
            }
        }

        // ---- 月 ----
        if viewModel.moonAltitude > -3 {
            let pt = panoramicPoint(alt: viewModel.moonAltitude, az: viewModel.moonAzimuth,
                                     cx: cx, horizonY: horizonY, hScale: hScale, az0: az0)
            if isVisible(x: pt.x, width: size.width) {
                drawMoon(ctx: ctx, at: pt, phase: viewModel.moonPhase)
            }
        }

        // ---- 銀河系中心 ----
        if viewModel.galacticCenterAltitude > -3 {
            let pt = panoramicPoint(alt: viewModel.galacticCenterAltitude,
                                     az: viewModel.galacticCenterAzimuth,
                                     cx: cx, horizonY: horizonY, hScale: hScale, az0: az0)
            if isVisible(x: pt.x, width: size.width) {
                drawGalacticCenter(ctx: ctx, at: pt)
            }
        }

        // ---- 方位ラベル ----
        drawPanoramicCardinalLabels(ctx: ctx, cx: cx, horizonY: horizonY,
                                     hScale: hScale, az0: az0, width: size.width)
    }

    /// 高度・方位角 → パノラマ画面座標
    private func panoramicPoint(alt: Double, az: Double,
                                  cx: Double, horizonY: Double,
                                  hScale: Double, az0: Double) -> CGPoint {
        let dAz = angularDiff(az, az0)
        let x = cx + dAz * hScale
        let y = horizonY - alt * hScale
        return CGPoint(x: x, y: y)
    }

    /// 方位角の差 (-180〜+180, 折り返し考慮)
    private func angularDiff(_ az: Double, _ center: Double) -> Double {
        atan2(
            sin((az - center) * .pi / 180),
            cos((az - center) * .pi / 180)
        ) * 180 / .pi
    }

    /// 画面内に表示されるか (横方向クリッピング)
    private func isVisible(x: Double, width: Double) -> Bool {
        x > -40 && x < width + 40
    }

    private func drawPanoramicConstellationLines(ctx: GraphicsContext,
                                                  cx: Double, horizonY: Double,
                                                  hScale: Double, az0: Double) {
        var path = Path()
        for line in viewModel.constellationLines {
            let dAz1 = angularDiff(line.startAz, az0)
            let dAz2 = angularDiff(line.endAz, az0)
            // 両端とも視野外 (±80°以上) ならスキップ
            guard abs(dAz1) < 80 || abs(dAz2) < 80 else { continue }
            let p1 = CGPoint(x: cx + dAz1 * hScale,
                             y: horizonY - max(line.startAlt, -5) * hScale)
            let p2 = CGPoint(x: cx + dAz2 * hScale,
                             y: horizonY - max(line.endAlt, -5) * hScale)
            path.move(to: p1)
            path.addLine(to: p2)
        }
        ctx.stroke(path,
                   with: .color(Color(red: 0.4, green: 0.6, blue: 0.9).opacity(0.35)),
                   lineWidth: 1)
    }

    private func drawPanoramicConstellationLabels(ctx: GraphicsContext,
                                                   cx: Double, horizonY: Double,
                                                   hScale: Double, az0: Double) {
        for label in viewModel.constellationLabels {
            guard label.alt > -2 else { continue }
            let dAz = angularDiff(label.az, az0)
            guard abs(dAz) < 70 else { continue }
            let pt = CGPoint(x: cx + dAz * hScale,
                             y: horizonY - label.alt * hScale)
            ctx.draw(
                Text(label.name)
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.45)),
                at: pt)
        }
    }

    private func drawPanoramicCardinalLabels(ctx: GraphicsContext,
                                              cx: Double, horizonY: Double,
                                              hScale: Double, az0: Double,
                                              width: Double) {
        let cardinals: [(String, Double)] = [
            ("北", 0), ("北東", 45), ("東", 90), ("南東", 135),
            ("南", 180), ("南西", 225), ("西", 270), ("北西", 315)
        ]
        let labelY = horizonY + 14
        for (text, az) in cardinals {
            let dAz = angularDiff(az, az0)
            guard abs(dAz) < 70 else { continue }
            let x = cx + dAz * hScale
            ctx.draw(
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6)),
                at: CGPoint(x: x, y: labelY))
        }
    }

    // MARK: - Gnomonic Projection (心射図法, ジャイロモード)

    private func drawGnomonicProjection(ctx: GraphicsContext,
                                        cx: Double, cy: Double, size: CGSize) {
        let scale = min(size.width, size.height) / (2 * tan(45 * .pi / 180))

        let cAlt = viewModel.viewAltitude * .pi / 180
        let cAz  = viewModel.viewAzimuth  * .pi / 180
        let (cx3, cy3, cz3) = altAzToCartesian(alt: cAlt, az: cAz)

        let eAzE = (cAz + .pi / 2)
        let eEastX = cos(eAzE)
        let eEastY = sin(eAzE)
        let eEastZ = 0.0

        let eUpX = cy3 * eEastZ - cz3 * eEastY
        let eUpY = cz3 * eEastX - cx3 * eEastZ
        let eUpZ = cx3 * eEastY - cy3 * eEastX
        let eUpLen = sqrt(eUpX*eUpX + eUpY*eUpY + eUpZ*eUpZ)
        let (eUX, eUY, eUZ) = eUpLen > 1e-10
            ? (eUpX/eUpLen, eUpY/eUpLen, eUpZ/eUpLen)
            : (0.0, 0.0, 1.0)

        func project(alt: Double, az: Double) -> CGPoint? {
            let (px, py, pz) = altAzToCartesian(alt: alt, az: az)
            let dot = px*cx3 + py*cy3 + pz*cz3
            guard dot > 0.1 else { return nil }
            let projX = (px*eEastX + py*eEastY + pz*eEastZ) / dot * scale
            let projY = (px*eUX    + py*eUY    + pz*eUZ)    / dot * scale
            return CGPoint(x: cx + projX, y: cy - projY)
        }

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

        // 恒星
        for pos in viewModel.starPositions {
            guard pos.altitude > -1 else { continue }
            let alt = pos.altitude * .pi / 180
            let az  = pos.azimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                         isDark: viewModel.isNight)
                if pos.star.magnitude < 1.5, !pos.star.name.isEmpty {
                    drawStarLabel(ctx: ctx, at: pt, name: pos.star.name)
                }
            }
        }

        // 星座名ラベル
        for label in viewModel.constellationLabels {
            let alt = label.alt * .pi / 180
            let az  = label.az  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                ctx.draw(
                    Text(label.name)
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.45)),
                    at: pt)
            }
        }

        // 太陽
        if viewModel.sunAltitude > -1 {
            let alt = viewModel.sunAltitude * .pi / 180
            if let pt = project(alt: alt, az: viewModel.sunAzimuth * .pi / 180) {
                drawSunSymbol(ctx: ctx, at: pt, radius: 14)
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

        drawCrosshair(ctx: ctx, cx: cx, cy: cy)
    }

    private func altAzToCartesian(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    // MARK: - Drawing primitives

    private func drawStar(ctx: GraphicsContext, at point: CGPoint,
                          magnitude: Double, isDark: Bool) {
        let radius = max(0.8, 5 - (magnitude + 1.5) * (4 / 4.5))
        let opacity = isDark ? 1.0 : max(0.1, 0.3 - magnitude * 0.05)
        let brightness = magnitude < 0 ? 1.0 : max(0.6, 1.0 - magnitude * 0.12)

        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(Color.white.opacity(opacity * brightness)))

        if magnitude < 1.5 {
            let glowR = radius * 2.5
            let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                                  width: glowR * 2, height: glowR * 2)
            ctx.fill(Circle().path(in: glowRect),
                     with: .color(Color.white.opacity(0.06 * (isDark ? 1 : 0.3))))
        }
    }

    private func drawStarLabel(ctx: GraphicsContext, at point: CGPoint, name: String) {
        ctx.draw(
            Text(name)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.65)),
            at: CGPoint(x: point.x + 7, y: point.y + 5))
    }

    private func drawSunSymbol(ctx: GraphicsContext, at point: CGPoint,
                                radius: Double, opacity: Double = 0.9) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(Color.yellow.opacity(opacity)))
        let glowR = radius * 2.2
        let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                              width: glowR * 2, height: glowR * 2)
        ctx.fill(Circle().path(in: glowRect),
                 with: .color(Color.yellow.opacity(0.08 * opacity)))
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

    // MARK: - Nearest Star (クリック判定用)

    /// タップ/クリック座標に最も近い明るい星 (等級 ≤ 2.5) を返す。
    /// パノラマモード専用。閾値 (pt) 以内に星がなければ nil。
    private func nearestStar(at tapPoint: CGPoint, size: CGSize,
                              threshold: CGFloat = 25) -> StarPosition? {
        guard !viewModel.isGyroMode else { return nil }

        let hFOV = max(30.0, min(150.0, viewModel.fov))
        let hScale = size.width / hFOV
        let cx = size.width / 2
        let cy = size.height / 2

        // gestureDragOffset は tap 時点では .zero
        var az0 = viewModel.viewAzimuth
        az0 = az0.truncatingRemainder(dividingBy: 360)
        if az0 < 0 { az0 += 360 }
        let alt0 = viewModel.viewAltitude
        let horizonY = cy + alt0 * hScale

        var nearest: StarPosition? = nil
        var nearestDist: CGFloat = threshold

        for pos in viewModel.starPositions where pos.star.magnitude <= 2.5 && pos.altitude > -3 {
            let pt = panoramicPoint(alt: pos.altitude, az: pos.azimuth,
                                    cx: cx, horizonY: horizonY,
                                    hScale: hScale, az0: az0)
            guard isVisible(x: pt.x, width: size.width) else { continue }
            let dx = CGFloat(pt.x) - tapPoint.x
            let dy = CGFloat(pt.y) - tapPoint.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist < nearestDist {
                nearestDist = dist
                nearest = pos
            }
        }
        return nearest
    }

    // MARK: - Drag Gesture (パノラマ 上下左右スクロール)

    private func panoramaDragGesture(width: Double) -> some Gesture {
        let hScale = width / viewModel.fov
        return DragGesture()
            .updating($gestureDragOffset) { value, state, _ in
                state = value.translation      // CGSize (width, height) をそのまま保持
            }
            .onEnded { [self] value in
                // --- 仰角計算（天頂折り返しを考慮）---
                let rawAlt = viewModel.viewAltitude - value.translation.height / hScale
                var commitAlt = rawAlt
                var azFlip: Double = 0
                if commitAlt > 90 {
                    commitAlt = 180 - commitAlt
                    azFlip = 180
                }
                commitAlt = max(-90, min(90, commitAlt))

                // --- 方位計算 ---
                let deltaAz = value.translation.width / hScale
                var newAz = viewModel.viewAzimuth - deltaAz + azFlip
                newAz = newAz.truncatingRemainder(dividingBy: 360)
                if newAz < 0 { newAz += 360 }

                viewModel.viewAltitude = commitAlt
                viewModel.viewAzimuth  = newAz
                dragPixelOffset  = 0
                dragPixelOffsetY = 0
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
                viewModel.fov = max(30, min(150, viewModel.fov / value))
            }
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

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return StarMapCanvasView(viewModel: vm)
        .frame(width: 400, height: 500)
}
