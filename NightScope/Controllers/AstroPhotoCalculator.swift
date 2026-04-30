enum AstroPhotoCalculator: Sendable {
    /// NPF ルール: 星点が流れない最長シャッタースピード
    static func maxShutterSeconds(focalLength: Double, aperture: Double, pixelPitch: Double) -> Double {
        guard focalLength > 0 else { return 0 }
        return (35 * aperture + 30 * pixelPitch) / focalLength
    }

    static func recommendedISO(bortleClass: Int, stacking: Bool) -> Int {
        let iso: Int
        switch bortleClass {
        case 1...3:
            iso = 3200
        case 4...5:
            iso = stacking ? 1600 : 3200
        case 6...7:
            iso = stacking ? 800 : 1600
        default:
            iso = stacking ? 400 : 800
        }

        return min(iso, 3200)
    }

    static func calculate(
        focalLength: Double,
        aperture: Double,
        pixelPitch: Double,
        bortleClass: Int,
        targetFrameCount: Int,
        stacking: Bool
    ) -> AstroPhotoSettings {
        let shutter = maxShutterSeconds(
            focalLength: focalLength,
            aperture: aperture,
            pixelPitch: pixelPitch
        )
        let iso = recommendedISO(bortleClass: bortleClass, stacking: stacking)
        let frameCount: Int
        let totalMinutes: Int
        if stacking {
            totalMinutes = Int((Double(targetFrameCount) * shutter / 60).rounded())
            frameCount = max(1, targetFrameCount)
        } else {
            totalMinutes = 0
            frameCount = 1
        }

        return AstroPhotoSettings(
            recommendedISO: iso,
            shutterSeconds: shutter,
            frameCount: frameCount,
            totalMinutes: totalMinutes
        )
    }
}
