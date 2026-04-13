import SwiftUI

extension StarMapCanvasView {
    func drawGnomonicProjection(
        ctx: GraphicsContext,
        cx: Double,
        cy: Double,
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        fov: Double
    ) {
        let simplifyDuringScrub = viewModel.isTimeSliderScrubbing
        let scale = StarMapCanvasProjection.gnomonicScale(size: size, fov: fov)

        let cAlt = centerAlt * .pi / 180
        let cAz = centerAz * .pi / 180

        let (fwdX, fwdY, fwdZ) = StarMapCanvasProjection.altAzToCartesian(alt: cAlt, az: cAz)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)
        let rightZ = 0.0

        let uCrossX = rightY * fwdZ - rightZ * fwdY
        let uCrossY = rightZ * fwdX - rightX * fwdZ
        let uCrossZ = rightX * fwdY - rightY * fwdX
        let uLen = sqrt(uCrossX * uCrossX + uCrossY * uCrossY + uCrossZ * uCrossZ)
        let (upX, upY, upZ) = uLen > 1e-10
            ? (uCrossX / uLen, uCrossY / uLen, uCrossZ / uLen)
            : (0.0, 0.0, 1.0)

        func project(alt: Double, az: Double) -> CGPoint? {
            let (px, py, pz) = StarMapCanvasProjection.altAzToCartesian(alt: alt, az: az)
            let dot = px * fwdX + py * fwdY + pz * fwdZ
            guard dot > 0.1 else { return nil }
            let projX = (px * rightX + py * rightY + pz * rightZ) / dot * scale
            let projY = (px * upX + py * upY + pz * upZ) / dot * scale
            return CGPoint(x: cx + projX, y: cy - projY)
        }

        let horizonScreenY = StarMapCanvasProjection.horizonScreenY(centerAlt: centerAlt, cy: cy, scale: scale)
        drawGnomonicGround(ctx: ctx, size: size, centerAlt: centerAlt, horizonScreenY: horizonScreenY)

        var constellationPath = Path()
        for line in viewModel.constellationLines {
            let startAlt = max(line.startAlt, -5) * .pi / 180
            let endAlt = max(line.endAlt, -5) * .pi / 180
            if let startPoint = project(alt: startAlt, az: line.startAz * .pi / 180),
               let endPoint = project(alt: endAlt, az: line.endAz * .pi / 180) {
                constellationPath.move(to: startPoint)
                constellationPath.addLine(to: endPoint)
            }
        }
        ctx.stroke(
            constellationPath,
            with: .color(StarMapPalette.constellationLine.opacity(0.35)),
            lineWidth: 1
        )

        if viewModel.isNight {
            drawGnomonicMilkyWayBand(ctx: ctx, project: project)
        }

        for position in viewModel.starPositions {
            if position.altitude < 5 && position.star.magnitude > 6.0 {
                continue
            }

            let alt = position.altitude * .pi / 180
            let az = position.azimuth * .pi / 180
            if let point = project(alt: alt, az: az) {
                drawStar(
                    ctx: ctx,
                    at: point,
                    magnitude: position.star.magnitude,
                    isDark: viewModel.isNight,
                    precomputedColor: position.precomputedColor,
                    altitude: position.altitude
                )
                if !simplifyDuringScrub, position.star.magnitude < 1.5, !position.star.name.isEmpty {
                    drawStarLabel(ctx: ctx, at: point, name: position.star.name)
                }
            }
        }

        if !simplifyDuringScrub {
            for label in viewModel.constellationLabels {
                let alt = label.alt * .pi / 180
                let az = label.az * .pi / 180
                if let point = project(alt: alt, az: az) {
                    ctx.draw(
                        Text(label.name)
                            .font(.system(size: 11))
                            .foregroundColor(StarMapPalette.constellationLabel.opacity(0.45)),
                        at: point
                    )
                }
            }
        }

        if viewModel.moonAltitude > -1 {
            let alt = viewModel.moonAltitude * .pi / 180
            if let point = project(alt: alt, az: viewModel.moonAzimuth * .pi / 180) {
                drawMoon(ctx: ctx, at: point, phase: viewModel.moonPhase)
            }
        }

        if viewModel.galacticCenterAltitude > -1 {
            let alt = viewModel.galacticCenterAltitude * .pi / 180
            if let point = project(alt: alt, az: viewModel.galacticCenterAzimuth * .pi / 180) {
                drawGalacticCenter(ctx: ctx, at: point)
            }
        }

        for planet in viewModel.planetPositions where planet.altitude > -1 {
            let alt = planet.altitude * .pi / 180
            if let point = project(alt: alt, az: planet.azimuth * .pi / 180) {
                drawPlanet(ctx: ctx, at: point, planet: planet)
            }
        }

        for radiant in viewModel.meteorShowerRadiants where radiant.altitude > -1 {
            let alt = radiant.altitude * .pi / 180
            if let point = project(alt: alt, az: radiant.azimuth * .pi / 180) {
                drawMeteorShowerRadiant(ctx: ctx, at: point, shower: radiant.shower)
            }
        }

        if let terrain = viewModel.terrainProfile {
            drawGnomonicTerrainSilhouette(
                ctx: ctx,
                project: project,
                centerAz: centerAz,
                fov: fov,
                size: size,
                terrain: terrain
            )
        }

        drawCrosshair(ctx: ctx, cx: cx, cy: cy)
    }
}

private extension StarMapCanvasView {
    func drawGnomonicGround(ctx: GraphicsContext, size: CGSize, centerAlt: Double, horizonScreenY: Double) {
        let groundColor = StarMapPalette.horizonGround

        if horizonScreenY < size.height {
            let groundRect = CGRect(
                x: 0,
                y: horizonScreenY,
                width: size.width,
                height: size.height - horizonScreenY
            )
            ctx.fill(Path(groundRect), with: .color(groundColor.opacity(0.6)))

            var horizonPath = Path()
            horizonPath.move(to: CGPoint(x: 0, y: horizonScreenY))
            horizonPath.addLine(to: CGPoint(x: size.width, y: horizonScreenY))
            ctx.stroke(horizonPath, with: .color(StarMapPalette.horizonLine.opacity(0.5)), lineWidth: 1)
        } else if centerAlt < 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(groundColor.opacity(0.6)))
        }
    }

    func drawStar(
        ctx: GraphicsContext,
        at point: CGPoint,
        magnitude: Double,
        isDark: Bool,
        precomputedColor: Color,
        altitude: Double = 90
    ) {
        let color = precomputedColor
        let radius = max(0.8, 5 - (magnitude + 1.5) * (4 / 4.5))
        let opacity = isDark ? 1.0 : max(0.1, 0.3 - magnitude * 0.05)
        let brightness = magnitude < 0 ? 1.0 : max(0.6, 1.0 - magnitude * 0.12)
        let extinction = altitude < 15 ? max(0, altitude / 15.0) : 1.0

        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(
            Circle().path(in: rect),
            with: .color(color.opacity(opacity * brightness * extinction))
        )

        if magnitude < 2.0 {
            let glowRadius = radius * 3.0
            let glowRect = CGRect(
                x: point.x - glowRadius,
                y: point.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            ctx.fill(
                Circle().path(in: glowRect),
                with: .color(color.opacity(0.12 * (isDark ? 1 : 0.3)))
            )
        }

        if magnitude < 0.5 {
            let outerGlowRadius = radius * 5.0
            let outerRect = CGRect(
                x: point.x - outerGlowRadius,
                y: point.y - outerGlowRadius,
                width: outerGlowRadius * 2,
                height: outerGlowRadius * 2
            )
            ctx.fill(
                Circle().path(in: outerRect),
                with: .color(color.opacity(0.04 * (isDark ? 1 : 0.2)))
            )
        }
    }

    func drawStarLabel(ctx: GraphicsContext, at point: CGPoint, name: String) {
        ctx.draw(
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65)),
            at: CGPoint(x: point.x + 7, y: point.y + 5)
        )
    }

    func drawCrosshair(ctx: GraphicsContext, cx: Double, cy: Double) {
        let radius: Double = 12
        var path = Path()
        path.move(to: CGPoint(x: cx - radius, y: cy))
        path.addLine(to: CGPoint(x: cx + radius, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - radius))
        path.addLine(to: CGPoint(x: cx, y: cy + radius))
        ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)

        let circleRadius: Double = 5
        ctx.stroke(
            Circle().path(
                in: CGRect(
                    x: cx - circleRadius,
                    y: cy - circleRadius,
                    width: circleRadius * 2,
                    height: circleRadius * 2
                )
            ),
            with: .color(.white.opacity(0.5)),
            lineWidth: 1
        )
    }

    func drawMoon(ctx: GraphicsContext, at point: CGPoint, phase: Double) {
        let radius: Double = 10
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(0.9)))

        let illumination = 1 - abs(phase * 2 - 1)
        if illumination < 0.98 {
            let shadowXScale = 1 - illumination * 2
            let shadowWidth = abs(shadowXScale) * radius * 2
            let shadowX = shadowXScale >= 0
                ? point.x - radius
                : point.x - radius + (radius * 2 - shadowWidth)
            let shadowRect = CGRect(x: shadowX, y: point.y - radius, width: shadowWidth, height: radius * 2)
            ctx.fill(
                Ellipse().path(in: shadowRect),
                with: .color(Color.black.opacity(max(0, 1 - illumination)))
            )
        }

        let glowRadius = radius * 1.8
        ctx.fill(
            Circle().path(
                in: CGRect(
                    x: point.x - glowRadius,
                    y: point.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
            ),
            with: .color(.white.opacity(0.06))
        )
    }

    func drawGalacticCenter(ctx: GraphicsContext, at point: CGPoint) {
        let radius: Double = 8
        ctx.fill(
            Ellipse().path(in: CGRect(x: point.x - radius * 2, y: point.y - radius, width: radius * 4, height: radius * 2)),
            with: .color(StarMapPalette.galacticCenterGlow.opacity(0.25))
        )
        ctx.fill(
            Circle().path(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(StarMapPalette.galacticCenterCore.opacity(0.85))
        )
    }

    func planetColor(name: String) -> Color {
        StarMapPalette.planet(named: name)
    }

    func drawPlanet(ctx: GraphicsContext, at point: CGPoint, planet: PlanetPosition) {
        let color = planetColor(name: planet.name)
        let magnitude = max(-5.5, min(3.0, planet.magnitude))
        let radius = max(2.0, 8.0 - (magnitude + 2.0) * (5.0 / 5.0))
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Circle().path(in: rect), with: .color(color.opacity(0.95)))

        if magnitude < 0 {
            let glowRadius = radius * 3.5
            ctx.fill(
                Circle().path(
                    in: CGRect(
                        x: point.x - glowRadius,
                        y: point.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )
                ),
                with: .color(color.opacity(0.15))
            )
        }

        ctx.draw(
            Text(planet.name)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.75)),
            at: CGPoint(x: point.x + radius + 5, y: point.y + 4)
        )
    }

    func drawMeteorShowerRadiant(ctx: GraphicsContext, at point: CGPoint, shower: MeteorShower) {
        let color = StarMapPalette.meteorAccent
        let radius: CGFloat = 10
        let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ctx.stroke(Circle().path(in: circleRect), with: .color(color.opacity(0.7)), lineWidth: 1.2)
        ctx.fill(
            Circle().path(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
            with: .color(color.opacity(0.9))
        )

        let rays: [(CGFloat, CGFloat)] = [(0, -1), (0, 1), (-1, 0), (1, 0)]
        for (deltaX, deltaY) in rays {
            var ray = Path()
            ray.move(to: CGPoint(x: point.x + deltaX * (radius + 2), y: point.y + deltaY * (radius + 2)))
            ray.addLine(to: CGPoint(x: point.x + deltaX * (radius + 7), y: point.y + deltaY * (radius + 7)))
            ctx.stroke(ray, with: .color(color.opacity(0.6)), lineWidth: 1)
        }

        ctx.draw(
            Text(shower.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color.opacity(0.85)),
            at: CGPoint(x: point.x + radius + 4, y: point.y + 4)
        )
    }

    func drawGnomonicMilkyWayBand(ctx: GraphicsContext, project: (Double, Double) -> CGPoint?) {
        let bandPoints = viewModel.milkyWayBandPoints
        guard bandPoints.count > 1 else { return }

        for index in 0..<(bandPoints.count - 1) {
            let start = bandPoints[index]
            let end = bandPoints[index + 1]

            let azimuthDifference = atan2(
                sin((start.az - end.az) * .pi / 180),
                cos((start.az - end.az) * .pi / 180)
            ) * 180 / .pi
            guard abs(azimuthDifference) < 40 else { continue }

            let startAlt = start.alt * .pi / 180
            let startAz = start.az * .pi / 180
            let startHalfHeight = start.halfH * .pi / 180
            let endAlt = end.alt * .pi / 180
            let endAz = end.az * .pi / 180
            let endHalfHeight = end.halfH * .pi / 180

            guard let startTop = project(startAlt + startHalfHeight, startAz),
                  let startBottom = project(startAlt - startHalfHeight, startAz),
                  let endTop = project(endAlt + endHalfHeight, endAz),
                  let endBottom = project(endAlt - endHalfHeight, endAz) else {
                continue
            }

            let maxJump: Double = 800
            guard abs(startTop.x - endTop.x) < maxJump,
                  abs(startTop.y - endTop.y) < maxJump,
                  abs(startBottom.x - endBottom.x) < maxJump,
                  abs(startBottom.y - endBottom.y) < maxJump else {
                continue
            }

            var slab = Path()
            slab.move(to: startTop)
            slab.addLine(to: endTop)
            slab.addLine(to: endBottom)
            slab.addLine(to: startBottom)
            slab.closeSubpath()

            let longitude = start.li <= 180 ? start.li : 360 - start.li
            let normalizedCenter = 1.0 - longitude / 180.0
            let slabColor = StarMapPalette.milkyWaySlabColor(normalizedCenter: normalizedCenter)
            ctx.fill(slab, with: .color(slabColor.opacity(0.10)))
        }
    }

    func drawGnomonicTerrainSilhouette(
        ctx: GraphicsContext,
        project: (Double, Double) -> CGPoint?,
        centerAz: Double,
        fov: Double,
        size: CGSize,
        terrain: TerrainProfile
    ) {
        let fillColor = StarMapPalette.groundFill
        let sweepRange = max(fov * 1.5, 90.0)
        let steps = 120

        var ridgePoints: [CGPoint] = []
        ridgePoints.reserveCapacity(steps + 1)

        for index in 0...steps {
            let fraction = Double(index) / Double(steps)
            var azimuth = centerAz + (fraction - 0.5) * sweepRange
            azimuth = azimuth.truncatingRemainder(dividingBy: 360)
            if azimuth < 0 {
                azimuth += 360
            }

            let horizonAngle = terrain.horizonAngle(forAzimuth: azimuth)
            let altitude = max(horizonAngle, 0) * .pi / 180
            let projectedAzimuth = (centerAz + (fraction - 0.5) * sweepRange) * .pi / 180

            if let point = project(altitude, projectedAzimuth) {
                guard point.x > -200 && point.x < size.width + 200 &&
                      point.y > -200 && point.y < size.height + 200 else {
                    continue
                }
                ridgePoints.append(point)
            }
        }

        guard ridgePoints.count > 1 else { return }

        var fillPath = Path()
        fillPath.move(to: ridgePoints[0])
        for point in ridgePoints.dropFirst() {
            fillPath.addLine(to: point)
        }
        fillPath.addLine(to: CGPoint(x: ridgePoints.last!.x, y: size.height + 10))
        fillPath.addLine(to: CGPoint(x: ridgePoints.first!.x, y: size.height + 10))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(fillColor))

        var ridgePath = Path()
        ridgePath.move(to: ridgePoints[0])
        for point in ridgePoints.dropFirst() {
            ridgePath.addLine(to: point)
        }
        ctx.stroke(ridgePath, with: .color(StarMapPalette.terrainRidge.opacity(0.4)), lineWidth: 1.5)
    }
}
