import SwiftUI

enum StarMapCanvasProjection {
    private static let minimumProjectedDot = 0.1
    private static let cardinalAltitudeDegrees = -1.5

    static func effectiveFOV(baseFOV: Double, gestureScale: Double) -> Double {
        StarMapLayout.clampedFOV(baseFOV / max(0.1, gestureScale))
    }

    static func gnomonicScale(size: CGSize, fov: Double) -> Double {
        let halfFovRad = max(0.01, (fov / 2) * .pi / 180)
        return min(size.width, size.height) / (2 * tan(halfFovRad))
    }

    static func adjustedCenter(
        viewAltitude: Double,
        viewAzimuth: Double,
        translation: CGSize,
        size: CGSize,
        fov: Double
    ) -> (alt: Double, az: Double) {
        let scale = gnomonicScale(size: size, fov: fov)
        let yawRad = atan2(translation.width, scale)
        let pitchRad = atan2(translation.height, scale)
        let altitude = viewAltitude + pitchRad * 180 / .pi
        let azimuth = viewAzimuth - yawRad * 180 / .pi
        return clampedCenter(altitude: altitude, azimuth: azimuth)
    }

    static func clampedCenter(altitude: Double, azimuth: Double) -> (alt: Double, az: Double) {
        let clampedAltitude = max(-10, min(89, altitude))
        var normalizedAzimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if normalizedAzimuth < 0 {
            normalizedAzimuth += 360
        }
        return (clampedAltitude, normalizedAzimuth)
    }

    static func altAzToCartesian(alt: Double, az: Double) -> (Double, Double, Double) {
        let x = cos(alt) * sin(az)
        let y = cos(alt) * cos(az)
        let z = sin(alt)
        return (x, y, z)
    }

    static func horizonScreenY(centerAlt: Double, cy: Double, scale: Double) -> Double {
        let cAltRad = centerAlt * .pi / 180
        let horizonProjY = -tan(cAltRad) * scale
        return cy - horizonProjY
    }

    static func cardinalLabelPlacements(
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        fov: Double
    ) -> [StarMapCanvasView.CardinalOverlayPlacement] {
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

            return StarMapCanvasView.CardinalOverlayPlacement(
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

    static func zoomedFOV(currentFOV: Double, scrollDeltaY: Double, preciseScrolling: Bool) -> Double {
        let sensitivity = preciseScrolling ? 1.2 : 4.0
        return StarMapLayout.clampedFOV(currentFOV - scrollDeltaY * sensitivity)
    }

    private static func projectedCardinalLabelX(
        azimuthDegrees: Double,
        size: CGSize,
        centerAlt: Double,
        centerAz: Double,
        fov: Double
    ) -> Double? {
        let cx = size.width / 2
        let scale = gnomonicScale(size: size, fov: fov)

        let cAlt = centerAlt * .pi / 180
        let cAz = centerAz * .pi / 180
        let (fwdX, fwdY, fwdZ) = altAzToCartesian(alt: cAlt, az: cAz)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)

        let alt = cardinalAltitudeDegrees * .pi / 180
        let az = azimuthDegrees * .pi / 180
        let (px, py, pz) = altAzToCartesian(alt: alt, az: az)
        let dot = px * fwdX + py * fwdY + pz * fwdZ
        guard dot > minimumProjectedDot else {
            return nil
        }

        let projX = (px * rightX + py * rightY) / dot * scale
        return clampedCardinalLabelX(cx + projX, sizeWidth: size.width)
    }
}
