import SwiftUI

enum StarMapCanvasInteraction {
    private static let minimumSelectableMagnitude = 2.5
    private static let minimumSelectableAltitude = -3.0
    private static let minimumProjectedDot = 0.1

    static func movedAzimuth(current: Double, step: Double) -> Double {
        var azimuth = (current + step).truncatingRemainder(dividingBy: 360)
        if azimuth < 0 {
            azimuth += 360
        }
        return azimuth
    }

    static func movedAltitude(current: Double, step: Double) -> Double {
        max(-10, min(89, current + step))
    }

    static func committedFOV(currentFOV: Double, magnification: Double) -> Double {
        StarMapLayout.clampedFOV(currentFOV / magnification)
    }

    static func nearestStar(
        at tapPoint: CGPoint,
        starPositions: [StarPosition],
        size: CGSize,
        fov: Double,
        centerAlt: Double,
        centerAz: Double,
        threshold: CGFloat = 25
    ) -> StarPosition? {
        let scale = StarMapCanvasProjection.gnomonicScale(size: size, fov: fov)
        let cx = size.width / 2
        let cy = size.height / 2

        let cAlt = centerAlt * .pi / 180
        let cAz = centerAz * .pi / 180
        let (fwdX, fwdY, fwdZ) = StarMapCanvasProjection.altAzToCartesian(alt: cAlt, az: cAz)
        let rightX = cos(cAz)
        let rightY = -sin(cAz)
        let uCrossX = rightY * fwdZ
        let uCrossY = -rightX * fwdZ
        let uCrossZ = rightX * fwdY - rightY * fwdX
        let uLen = sqrt(uCrossX * uCrossX + uCrossY * uCrossY + uCrossZ * uCrossZ)
        let (upX, upY, upZ) = uLen > 1e-10
            ? (uCrossX / uLen, uCrossY / uLen, uCrossZ / uLen)
            : (0.0, 0.0, 1.0)

        var nearest: StarPosition?
        var nearestDistance = threshold

        for position in starPositions
        where position.star.magnitude <= minimumSelectableMagnitude && position.altitude > minimumSelectableAltitude {
            let alt = position.altitude * .pi / 180
            let az = position.azimuth * .pi / 180
            let (px, py, pz) = StarMapCanvasProjection.altAzToCartesian(alt: alt, az: az)
            let dot = px * fwdX + py * fwdY + pz * fwdZ
            guard dot > minimumProjectedDot else {
                continue
            }

            let projectedX = (px * rightX + py * rightY) / dot * scale
            let projectedY = (px * upX + py * upY + pz * upZ) / dot * scale
            let deltaX = (cx + projectedX) - tapPoint.x
            let deltaY = (cy - projectedY) - tapPoint.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

            if distance < nearestDistance {
                nearestDistance = distance
                nearest = position
            }
        }

        return nearest
    }
}
