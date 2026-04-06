import SwiftUI

// MARK: - StarMapCanvasView

/// 星空マップを描画する共有ビュー (iPhone / Mac 共通)
/// - 全天モード: 正距方位図法 (天頂中心, 地平線が外縁)
/// - ジャイロモード: 心射図法 (viewAltitude/viewAzimuth が画面中心)
struct StarMapCanvasView: View {
    @ObservedObject var viewModel: StarMapViewModel

    // 全天モードでのドラッグ回転 (北が上からのオフセット)
    @State private var dragOffset: Double = 0
    @GestureState private var gestureOffset: Double = 0

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvas(size: geo.size)
                    .gesture(
                        viewModel.isGyroMode ? nil : rotationDragGesture
                    )

                if viewModel.isGyroMode {
                    gyroModeIndicator
                }
            }
        }
        .background(Color.black)
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        Canvas { ctx, sz in
            let cx = sz.width / 2
            let cy = sz.height / 2
            let maxR = min(sz.width, sz.height) / 2 * 0.88

            if viewModel.isGyroMode {
                drawGnomonicProjection(ctx: ctx, cx: cx, cy: cy, size: sz)
            } else {
                // ---- 全天モード ----
                let rotationOffset = dragOffset + gestureOffset

                // 地平線円
                drawHorizonCircle(ctx: ctx, cx: cx, cy: cy, maxR: maxR)

                // 恒星
                for pos in viewModel.starPositions {
                    guard pos.altitude > -1 else { continue }
                    let pt = altAzToPoint(
                        alt: pos.altitude, az: pos.azimuth,
                        cx: cx, cy: cy, maxR: maxR,
                        rotationOffset: rotationOffset)
                    drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                             isDark: viewModel.isNight)
                }

                // 太陽
                drawSun(ctx: ctx, altitude: viewModel.sunAltitude,
                        azimuth: viewModel.sunAzimuth,
                        cx: cx, cy: cy, maxR: maxR, rotationOffset: rotationOffset)

                // 月
                if viewModel.moonAltitude > -1 {
                    let moonPt = altAzToPoint(
                        alt: viewModel.moonAltitude, az: viewModel.moonAzimuth,
                        cx: cx, cy: cy, maxR: maxR, rotationOffset: rotationOffset)
                    drawMoon(ctx: ctx, at: moonPt, phase: viewModel.moonPhase)
                }

                // 銀河系中心
                if viewModel.galacticCenterAltitude > -1 {
                    let gcPt = altAzToPoint(
                        alt: viewModel.galacticCenterAltitude,
                        az: viewModel.galacticCenterAzimuth,
                        cx: cx, cy: cy, maxR: maxR, rotationOffset: rotationOffset)
                    drawGalacticCenter(ctx: ctx, at: gcPt)
                }

                // 方位ラベル
                drawCardinalLabels(ctx: ctx, cx: cx, cy: cy, maxR: maxR,
                                   rotationOffset: rotationOffset)
            }
        }
    }

    // MARK: - Full-Sky Projection (正距方位図法)

    /// 高度・方位角 → スクリーン座標 (全天モード)
    private func altAzToPoint(alt: Double, az: Double,
                               cx: Double, cy: Double, maxR: Double,
                               rotationOffset: Double) -> CGPoint {
        let r = (90 - alt) / 90 * maxR
        let azRad = (az + rotationOffset) * .pi / 180
        let x = cx + r * sin(azRad)
        let y = cy - r * cos(azRad)
        return CGPoint(x: x, y: y)
    }

    private func drawHorizonCircle(ctx: GraphicsContext, cx: Double, cy: Double, maxR: Double) {
        let horizonPath = Circle().path(in: CGRect(
            x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2))
        ctx.stroke(horizonPath, with: .color(.white.opacity(0.25)), lineWidth: 1)
        // 中心点 (天頂)
        ctx.fill(
            Circle().path(in: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)),
            with: .color(.white.opacity(0.3)))
    }

    // MARK: - Gnomonic Projection (心射図法, ジャイロモード)

    private func drawGnomonicProjection(ctx: GraphicsContext,
                                        cx: Double, cy: Double, size: CGSize) {
        let scale = min(size.width, size.height) / (2 * tan(45 * .pi / 180))

        // 中心方向のデカルト座標
        let cAlt = viewModel.viewAltitude * .pi / 180
        let cAz  = viewModel.viewAzimuth  * .pi / 180
        let (cx3, cy3, cz3) = altAzToCartesian(alt: cAlt, az: cAz)

        // 投影用の基底ベクトル (中心方向に垂直な 2 軸)
        // e_east: 東方向 (方位角 +90°)
        // e_north: 仰角増加方向
        let eAzE = (cAz + .pi / 2)
        let eEastX = cos(eAzE)
        let eEastY = sin(eAzE)
        let eEastZ = 0.0

        // e_up: (c × eEast) を正規化
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

        // 恒星
        for pos in viewModel.starPositions {
            guard pos.altitude > -1 else { continue }
            let alt = pos.altitude * .pi / 180
            let az  = pos.azimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawStar(ctx: ctx, at: pt, magnitude: pos.star.magnitude,
                         isDark: viewModel.isNight)
            }
        }

        // 太陽
        if viewModel.sunAltitude > -1 {
            let alt = viewModel.sunAltitude * .pi / 180
            let az  = viewModel.sunAzimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawSunSymbol(ctx: ctx, at: pt, radius: 14)
            }
        }

        // 月
        if viewModel.moonAltitude > -1 {
            let alt = viewModel.moonAltitude * .pi / 180
            let az  = viewModel.moonAzimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawMoon(ctx: ctx, at: pt, phase: viewModel.moonPhase)
            }
        }

        // 銀河系中心
        if viewModel.galacticCenterAltitude > -1 {
            let alt = viewModel.galacticCenterAltitude * .pi / 180
            let az  = viewModel.galacticCenterAzimuth  * .pi / 180
            if let pt = project(alt: alt, az: az) {
                drawGalacticCenter(ctx: ctx, at: pt)
            }
        }

        // ジャイロモード: 中心クロスヘア
        drawCrosshair(ctx: ctx, cx: cx, cy: cy)
    }

    /// 仰角・方位角 (ラジアン) → 単位球面デカルト座標
    /// x = 東, y = 北, z = 上
    private func altAzToCartesian(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    // MARK: - Drawing primitives

    /// 恒星の描画 (等級に応じたサイズ)
    private func drawStar(ctx: GraphicsContext, at point: CGPoint,
                          magnitude: Double, isDark: Bool) {
        // 等級が小さい (明るい) ほど大きく描画
        // magnitude -1.5 → radius 5, magnitude 3 → radius 1
        let radius = max(0.8, 5 - (magnitude + 1.5) * (4 / 4.5))
        let opacity = isDark ? 1.0 : max(0.1, 0.3 - magnitude * 0.05)
        let brightness = magnitude < 0 ? 1.0 : max(0.6, 1.0 - magnitude * 0.12)

        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(Color.white.opacity(opacity * brightness)))

        // 1等星以上は薄いグロー
        if magnitude < 1.5 {
            let glowR = radius * 2.5
            let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                                  width: glowR * 2, height: glowR * 2)
            ctx.fill(Circle().path(in: glowRect),
                     with: .color(Color.white.opacity(0.06 * (isDark ? 1 : 0.3))))
        }
    }

    /// 太陽の描画 (全天モード)
    private func drawSun(ctx: GraphicsContext,
                         altitude: Double, azimuth: Double,
                         cx: Double, cy: Double, maxR: Double,
                         rotationOffset: Double) {
        let opacity = altitude > 0 ? 0.9 : max(0, 0.3 + altitude / 18)
        guard opacity > 0 else { return }
        let pt = altAzToPoint(alt: max(altitude, -5), az: azimuth,
                               cx: cx, cy: cy, maxR: maxR,
                               rotationOffset: rotationOffset)
        drawSunSymbol(ctx: ctx, at: pt, radius: 12, opacity: opacity)
    }

    private func drawSunSymbol(ctx: GraphicsContext, at point: CGPoint,
                                radius: Double, opacity: Double = 0.9) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect),
                 with: .color(Color.yellow.opacity(opacity)))
        // 光芒
        let glowR = radius * 2.2
        let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                              width: glowR * 2, height: glowR * 2)
        ctx.fill(Circle().path(in: glowRect),
                 with: .color(Color.yellow.opacity(0.08 * opacity)))
    }

    /// 月の描画 (位相に応じたクレセント)
    private func drawMoon(ctx: GraphicsContext, at point: CGPoint, phase: Double) {
        let radius: Double = 10
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)

        // ベース円 (白)
        ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(0.9)))

        // 影で三日月を表現: phase に応じて暗い楕円を重ねる
        // phase 0 = 新月 (全体が影), 0.5 = 満月 (影なし), 1 = 新月
        let illumination = 1 - abs(phase * 2 - 1)  // 0=新月, 1=満月
        if illumination < 0.98 {
            // 影楕円の横幅: -1(完全な円)〜+1(完全な円) で変化
            let shadowXScale = 1 - illumination * 2
            let shadowW = abs(shadowXScale) * radius * 2
            let shadowX = shadowXScale >= 0
                ? point.x - radius
                : point.x - radius + (radius * 2 - shadowW)
            let shadowRect = CGRect(x: shadowX, y: point.y - radius,
                                    width: shadowW, height: radius * 2)
            let alpha = max(0.0, 1.0 - illumination)
            ctx.fill(Ellipse().path(in: shadowRect),
                     with: .color(Color.black.opacity(alpha)))
        }

        // 月の光輪
        let glowR = radius * 1.8
        let glowRect = CGRect(x: point.x - glowR, y: point.y - glowR,
                              width: glowR * 2, height: glowR * 2)
        ctx.fill(Circle().path(in: glowRect),
                 with: .color(.white.opacity(0.06)))
    }

    /// 銀河系中心のマーカー
    private func drawGalacticCenter(ctx: GraphicsContext, at point: CGPoint) {
        let r: Double = 8
        // 外周の楕円 (銀河をイメージした薄い楕円)
        let outerRect = CGRect(x: point.x - r * 2, y: point.y - r,
                               width: r * 4, height: r * 2)
        ctx.fill(Ellipse().path(in: outerRect),
                 with: .color(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.25)))
        // 中心点
        let innerR: Double = 3
        let innerRect = CGRect(x: point.x - innerR, y: point.y - innerR,
                               width: innerR * 2, height: innerR * 2)
        ctx.fill(Circle().path(in: innerRect),
                 with: .color(Color(red: 0.8, green: 0.6, blue: 1.0).opacity(0.85)))
    }

    /// 方位ラベル (北/東/南/西)
    private func drawCardinalLabels(ctx: GraphicsContext,
                                    cx: Double, cy: Double, maxR: Double,
                                    rotationOffset: Double) {
        let labels: [(text: String, az: Double)] = [
            ("北", 0), ("東", 90), ("南", 180), ("西", 270)
        ]
        let labelR = maxR + 16
        for label in labels {
            let az = label.az + rotationOffset
            let azRad = az * .pi / 180
            let x = cx + labelR * sin(azRad)
            let y = cy - labelR * cos(azRad)
            ctx.draw(
                Text(label.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6)),
                at: CGPoint(x: x, y: y))
        }
    }

    /// ジャイロモードのクロスヘア (照準)
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

    // MARK: - Drag Gesture (全天モード回転)

    private var rotationDragGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                // 右ドラッグ → 時計回り回転 (方位角増加), 左ドラッグ → 反時計回り
                state = value.translation.width / 2
            }
            .onEnded { value in
                dragOffset += value.translation.width / 2
                dragOffset = dragOffset.truncatingRemainder(dividingBy: 360)
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
                    .background(.black.opacity(0.4))
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
        .frame(width: 400, height: 400)
        .background(Color.black)
}
