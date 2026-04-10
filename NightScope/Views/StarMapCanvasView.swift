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

    @GestureState private var gestureScale: Double = 1.0

    // キーボードフォーカス
    @FocusState private var isFocused: Bool

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
                    let displayFov = StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale))
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
                var az = viewModel.viewAzimuth - StarMapLayout.directionStep
                if az < 0 { az += 360 }
                viewModel.viewAzimuth = az
                return .handled
            }
            .onKeyPress(.rightArrow) {
                var az = viewModel.viewAzimuth + StarMapLayout.directionStep
                az = az.truncatingRemainder(dividingBy: 360)
                viewModel.viewAzimuth = az
                return .handled
            }
            .onKeyPress(.upArrow) {
                viewModel.viewAltitude = min(90, viewModel.viewAltitude + StarMapLayout.directionStep)
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.viewAltitude = max(0, viewModel.viewAltitude - StarMapLayout.directionStep)
                return .handled
            }
            .onKeyPress(KeyEquivalent("=")) {
                // ズームイン (視野を狭める)
                viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov - StarMapLayout.zoomStep)
                return .handled
            }
            .onKeyPress(KeyEquivalent("-")) {
                // ズームアウト (視野を広げる)
                viewModel.fov = StarMapLayout.clampedFOV(viewModel.fov + StarMapLayout.zoomStep)
                return .handled
            }
            .onKeyPress(KeyEquivalent("n")) {
                viewModel.resetToNorth()
                return .handled
            }
        }
        .background(StarMapPalette.canvasBackground)
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
            - gestureDragOffset.height / hScale
        let azDelta = gestureDragOffset.width / hScale
        var az = viewModel.viewAzimuth - azDelta
        var alt = rawAlt
        if alt > 90 {
            // 天頂折り返し: 頭を後ろに倒すと反対方位の空が見える
            alt = 180 - alt
            az += 180
        }
        // 地面方向は 0° でクランプ（地平線以下にスクロールしない）
        alt = max(0, min(90, alt))
        az = az.truncatingRemainder(dividingBy: 360)
        if az < 0 { az += 360 }
        return (alt: alt, az: az)
    }

    private func drawPanoramicProjection(ctx: GraphicsContext,
                                         cx: Double, cy: Double, size: CGSize) {
        // 水平視野: ピンチで調整可能 (30°〜150°), デフォルト 90°
        let hFOV = StarMapLayout.clampedFOV(viewModel.fov / max(0.1, gestureScale))
        let hScale = size.width / hFOV           // pt/degree
        let (alt0, az0) = effectiveViewDirection(hScale: hScale)
        let horizonY = cy + alt0 * hScale        // 動的地平線Y座標（画面中心 = 視点高度）

        // ---- 空の背景グラデーション ----
        drawSkyBackground(ctx: ctx, horizonY: horizonY, size: size)

        // ---- 地面の塗りつぶし ----
        if horizonY < size.height {
            let groundY = max(0.0, horizonY)
            let groundPath = Path(CGRect(x: 0, y: groundY,
                                          width: size.width, height: size.height - groundY))
            ctx.fill(groundPath, with: .color(StarMapPalette.groundFill))
        }

        // ---- 地平線グラデーション ----
        drawHorizonGradient(ctx: ctx, horizonY: horizonY, size: size, sunAlt: viewModel.sunAltitude)

        // ---- 地平線ライン ----
        if horizonY >= 0 && horizonY <= size.height {
            var horizPath = Path()
            horizPath.move(to: CGPoint(x: 0, y: horizonY))
            horizPath.addLine(to: CGPoint(x: size.width, y: horizonY))
            ctx.stroke(horizPath, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }

        // ---- 高度/方位グリッド ----
        drawAltAzGrid(ctx: ctx, cx: cx, horizonY: horizonY, hScale: hScale, az0: az0, size: size)

        // ---- 星座線 ----
        drawPanoramicConstellationLines(ctx: ctx, cx: cx, horizonY: horizonY,
                                        hScale: hScale, az0: az0)

        // ---- 天の川バンド ----
        if viewModel.isNight {
            drawMilkyWayBand(ctx: ctx, cx: cx, horizonY: horizonY, hScale: hScale, az0: az0, size: size)
        }

        // ---- 恒星 ----
        for pos in viewModel.starPositions {
            // 広視野では暗い星をスキップして描画負荷を軽減
            if hFOV > 100 && pos.star.magnitude > 6.5 { continue }
            // 地平線近くの暗い星をスキップ
            if pos.altitude < 5 && pos.star.magnitude > 6.0 { continue }
            let pt = panoramicPoint(alt: pos.altitude, az: pos.azimuth,
                                     cx: cx, horizonY: horizonY,
                                     hScale: hScale, az0: az0)
            guard isVisible(x: pt.x, width: size.width) else { continue }
            drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                     isDark: viewModel.isNight, precomputedColor: pos.precomputedColor,
                     altitude: pos.altitude)
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

        // ---- 惑星 ----
        for planet in viewModel.planetPositions where planet.altitude > -3 {
            let pt = panoramicPoint(alt: planet.altitude, az: planet.azimuth,
                                     cx: cx, horizonY: horizonY, hScale: hScale, az0: az0)
            if isVisible(x: pt.x, width: size.width) {
                drawPlanet(ctx: ctx, at: pt, planet: planet)
            }
        }

        // ---- 流星群放射点（活動中のみ）----
        for radiant in viewModel.meteorShowerRadiants where radiant.altitude > -5 {
            let pt = panoramicPoint(alt: radiant.altitude, az: radiant.azimuth,
                                     cx: cx, horizonY: horizonY, hScale: hScale, az0: az0)
            if isVisible(x: pt.x, width: size.width) {
                drawMeteorShowerRadiant(ctx: ctx, at: pt, shower: radiant.shower)
            }
        }

        // ---- 地形シルエット（最前面: 天体を自然に隠す）----
        if let terrain = viewModel.terrainProfile {
            drawTerrainSilhouette(ctx: ctx, cx: cx, horizonY: horizonY,
                                  hScale: hScale, az0: az0, size: size, terrain: terrain)
        }

        // ---- 方位ラベル（地形より前面に）----
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
                    .font(.system(size: 11))
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
                    .font(.system(size: 13, weight: .medium))
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
            // 地平線近くの暗い星をスキップ
            if pos.altitude < 5 && pos.star.magnitude > 6.0 { continue }
            let alt = pos.altitude * .pi / 180
            let az  = pos.azimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                         isDark: viewModel.isNight, precomputedColor: pos.precomputedColor,
                         altitude: pos.altitude)
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
                        .font(.system(size: 11))
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

    // MARK: - Horizon Gradient (Phase 2-1)

    private func drawHorizonGradient(ctx: GraphicsContext, horizonY: Double,
                                     size: CGSize, sunAlt: Double) {
        let gradientHeight: Double = 40
        let topY = horizonY - gradientHeight
        guard topY < size.height && horizonY > 0 else { return }

        let (topColor, bottomColor) = horizonGradientColors(sunAltitude: sunAlt)
        let clampedTopY = max(0.0, topY)
        let rect = CGRect(x: 0, y: clampedTopY,
                          width: size.width, height: horizonY - clampedTopY)
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [topColor, bottomColor]),
                startPoint: CGPoint(x: 0, y: clampedTopY),
                endPoint:   CGPoint(x: 0, y: horizonY)
            )
        )
    }

    private func horizonGradientColors(sunAltitude: Double) -> (top: Color, bottom: Color) {
        if sunAltitude < -18 {
            return (Color(red: 0.05, green: 0.05, blue: 0.25).opacity(0.0),
                    Color(red: 0.05, green: 0.05, blue: 0.25).opacity(0.35))
        } else if sunAltitude < -6 {
            let t = (sunAltitude + 18) / 12
            return (Color(red: 0.1, green: 0.1, blue: 0.4).opacity(0.0),
                    Color(red: 0.15 + 0.25 * t, green: 0.1 + 0.2 * t, blue: 0.4 - 0.15 * t).opacity(0.5))
        } else if sunAltitude < 0 {
            let t = (sunAltitude + 6) / 6
            return (Color(red: 0.5, green: 0.3, blue: 0.1).opacity(0.0),
                    Color(red: 0.9, green: 0.5 + 0.2 * t, blue: 0.1).opacity(0.6))
        } else {
            return (Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.0),
                    Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.7))
        }
    }

    // MARK: - Alt/Az Grid (Phase 2-2)

    private func drawAltAzGrid(ctx: GraphicsContext, cx: Double, horizonY: Double,
                                hScale: Double, az0: Double, size: CGSize) {
        let gridColor = Color.white.opacity(0.08)
        let style = StrokeStyle(lineWidth: 0.5, dash: [4, 8])

        for alt in stride(from: 15.0, through: 75.0, by: 15.0) {
            let y = horizonY - alt * hScale
            guard y > 0 && y < size.height else { continue }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(path, with: .color(gridColor), style: style)
            ctx.draw(
                Text("\(Int(alt))°").font(.system(size: 9)).foregroundColor(.white.opacity(0.15)),
                at: CGPoint(x: 18, y: y - 6))
        }

        for azOffset in stride(from: -180.0, through: 180.0, by: 30.0) {
            let az = (az0 + azOffset).truncatingRemainder(dividingBy: 360)
            let dAz = angularDiff(az, az0)
            let x = cx + dAz * hScale
            guard x > 0 && x < size.width else { continue }
            let topY = max(0, horizonY - 90 * hScale)
            let bottomY = min(size.height, horizonY)
            guard topY < bottomY else { continue }
            var path = Path()
            path.move(to: CGPoint(x: x, y: topY))
            path.addLine(to: CGPoint(x: x, y: bottomY))
            ctx.stroke(path, with: .color(gridColor), style: style)
        }
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

    // MARK: - Milky Way Band (Phase 5)

    /// 天の川バンドをパノラマプロジェクションに描画する。
    /// ViewModel でバックグラウンド計算済みの milkyWayBandPoints を使用するため、
    /// 描画フレームごとの天文座標変換コストがゼロ。
    private func drawMilkyWayBand(ctx: GraphicsContext, cx: Double, horizonY: Double,
                                   hScale: Double, az0: Double, size: CGSize) {
        let cachedPoints = viewModel.milkyWayBandPoints
        guard cachedPoints.count > 2 else { return }

        struct ScreenPoint { var x, y, halfH: Double }
        var screenPoints = [ScreenPoint]()
        screenPoints.reserveCapacity(cachedPoints.count)

        for bp in cachedPoints {
            let px = cx + angularDiff(bp.az, az0) * hScale
            guard px > -100 && px < size.width + 100 else { continue }
            let py = horizonY - bp.alt * hScale
            screenPoints.append(ScreenPoint(x: px, y: py, halfH: bp.halfH * hScale))
        }

        guard screenPoints.count > 2 else { return }

        // 各スラブを個別に塗る（銀経依存の色変化）
        for i in 0..<screenPoints.count - 1 {
            let p0 = screenPoints[i], p1 = screenPoints[i + 1]
            var slab = Path()
            slab.move(to:    CGPoint(x: p0.x, y: p0.y - p0.halfH))
            slab.addLine(to: CGPoint(x: p1.x, y: p1.y - p1.halfH))
            slab.addLine(to: CGPoint(x: p1.x, y: p1.y + p1.halfH))
            slab.addLine(to: CGPoint(x: p0.x, y: p0.y + p0.halfH))
            slab.closeSubpath()
            let lDeg = cachedPoints[i].li <= 180 ? cachedPoints[i].li : 360 - cachedPoints[i].li
            let tCenter = 1.0 - lDeg / 180.0
            let slabColor = Color(red: 0.50 + 0.20 * tCenter, green: 0.55, blue: 0.85 - 0.25 * tCenter)
            ctx.fill(slab, with: .color(slabColor.opacity(0.10)))
        }
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

        let hFOV = StarMapLayout.clampedFOV(viewModel.fov)
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
        let hScale = width / StarMapLayout.clampedFOV(viewModel.fov)
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
                commitAlt = max(0, min(90, commitAlt))

                // --- 方位計算 ---
                let deltaAz = value.translation.width / hScale
                var newAz = viewModel.viewAzimuth - deltaAz + azFlip
                newAz = newAz.truncatingRemainder(dividingBy: 360)
                if newAz < 0 { newAz += 360 }

                viewModel.viewAltitude = commitAlt
                viewModel.viewAzimuth  = newAz
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

// MARK: - New Drawing Primitives

private extension StarMapCanvasView {

    // MARK: Sky Background

    func drawSkyBackground(ctx: GraphicsContext, horizonY: Double, size: CGSize) {
        let topY = 0.0
        let bottom = min(horizonY, size.height)
        guard bottom > topY else { return }
        let rect = CGRect(x: 0, y: topY, width: size.width, height: bottom - topY)
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.01, green: 0.02, blue: 0.08), location: 0),
                    .init(color: Color(red: 0.03, green: 0.06, blue: 0.18), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: topY),
                endPoint:   CGPoint(x: 0, y: bottom)
            )
        )
    }

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

    // MARK: Terrain Silhouette

    func drawTerrainSilhouette(ctx: GraphicsContext, cx: Double, horizonY: Double,
                                hScale: Double, az0: Double, size: CGSize,
                                terrain: TerrainProfile) {
        let fillColor = StarMapPalette.groundFill
        var path = Path()
        let steps = 180  // 2° resolution for smooth silhouette
        var started = false

        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            // Sweep ±90° from az0 (full visible panoramic range)
            let az  = (az0 + (fraction - 0.5) * 180.0)
                .truncatingRemainder(dividingBy: 360)
            let hAngle  = terrain.horizonAngle(forAzimuth: az)
            let terrainY = horizonY - hAngle * hScale
            let x = cx + (fraction - 0.5) * 180.0 * hScale

            if !started {
                path.move(to: CGPoint(x: x, y: terrainY))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: terrainY))
            }
        }
        // Close path downward
        let endX = cx + 0.5 * 180.0 * hScale
        let startX = cx - 0.5 * 180.0 * hScale
        path.addLine(to: CGPoint(x: endX,   y: size.height))
        path.addLine(to: CGPoint(x: startX, y: size.height))
        path.closeSubpath()

        ctx.fill(path, with: .color(fillColor))

        // Subtle airglow along ridge
        var ridgePath = Path()
        started = false
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let az  = (az0 + (fraction - 0.5) * 180.0)
                .truncatingRemainder(dividingBy: 360)
            let hAngle  = terrain.horizonAngle(forAzimuth: az)
            let terrainY = horizonY - hAngle * hScale
            let x = cx + (fraction - 0.5) * 180.0 * hScale
            if !started { ridgePath.move(to: CGPoint(x: x, y: terrainY)); started = true }
            else         { ridgePath.addLine(to: CGPoint(x: x, y: terrainY)) }
        }
        ctx.stroke(ridgePath,
                   with: .color(Color(red: 0.2, green: 0.35, blue: 0.15).opacity(0.4)),
                   lineWidth: 1.5)
    }
}

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return StarMapCanvasView(viewModel: vm)
        .frame(width: 400, height: 500)
}
