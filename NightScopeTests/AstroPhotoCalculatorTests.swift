import XCTest
@testable import NightScope

final class AstroPhotoCalculatorTests: XCTestCase {
    func test_maxShutterSeconds_matchesNPFRule() {
        let shutter = AstroPhotoCalculator.maxShutterSeconds(
            focalLength: 50,
            aperture: 2.8,
            pixelPitch: 3.76
        )

        XCTAssertEqual(shutter, 4.216, accuracy: 0.01)
    }

    func test_maxShutterSeconds_returnsZeroWhenFocalLengthIsZero() {
        let shutter = AstroPhotoCalculator.maxShutterSeconds(
            focalLength: 0,
            aperture: 2.8,
            pixelPitch: 3.76
        )

        XCTAssertEqual(shutter, 0)
    }

    func test_recommendedISO_matchesBortleRanges() {
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 1, stacking: true), 3200)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 3, stacking: true), 3200)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 4, stacking: true), 1600)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 5, stacking: true), 1600)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 6, stacking: true), 800)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 7, stacking: true), 800)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 8, stacking: true), 400)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 10, stacking: true), 400)
    }

    func test_recommendedISO_nonStacking_isOneStopHigher() {
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 4, stacking: false), 3200)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 6, stacking: false), 1600)
        XCTAssertEqual(AstroPhotoCalculator.recommendedISO(bortleClass: 8, stacking: false), 800)
    }

    func test_calculate_stacking_usesTargetFrameCount() {
        let settings = AstroPhotoCalculator.calculate(
            focalLength: 50,
            aperture: 2.8,
            pixelPitch: 3.76,
            bortleClass: 4,
            targetFrameCount: 30,
            stacking: true
        )

        XCTAssertEqual(settings.frameCount, 30)
        XCTAssertGreaterThan(settings.totalMinutes, 0)
    }

    func test_calculate_nonStacking_frameCountIsOne() {
        let settings = AstroPhotoCalculator.calculate(
            focalLength: 50,
            aperture: 2.8,
            pixelPitch: 3.76,
            bortleClass: 4,
            targetFrameCount: 30,
            stacking: false
        )

        XCTAssertEqual(settings.frameCount, 1)
        XCTAssertEqual(settings.totalMinutes, 0)
    }

    @MainActor
    func test_viewModel_clampsBortleClassToValidRange() {
        let low = AstroPhotoCalculatorViewModel(bortleClass: 0)
        XCTAssertEqual(low.bortleClass, 1)
        low.bortleClass = 0
        XCTAssertEqual(low.bortleClass, 1)

        let high = AstroPhotoCalculatorViewModel(bortleClass: 10)
        XCTAssertEqual(high.bortleClass, 9)
        high.bortleClass = 10
        XCTAssertEqual(high.bortleClass, 9)
    }
}
