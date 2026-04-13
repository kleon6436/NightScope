import XCTest
import SwiftUI
@testable import NightScope

@MainActor
final class StarMapSupportTests: XCTestCase {
    func test_StarMapPresentation_azimuthName_normalizesDegrees() {
        XCTAssertEqual(StarMapPresentation.azimuthName(for: -1), "北")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 44), "北東")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 225), "南西")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 359), "北")
    }

    func test_StarMapPresentation_azimuthName_supportsEightDirections() {
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 0), "北")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 45), "北東")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 90), "東")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 135), "南東")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 180), "南")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 225), "南西")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 270), "西")
        XCTAssertEqual(StarMapPresentation.azimuthName(for: 315), "北西")
    }

    func test_StarMapPresentation_timeString_formatsMinutes() {
        XCTAssertEqual(StarMapPresentation.timeString(from: 0), "00:00")
        XCTAssertEqual(StarMapPresentation.timeString(from: 61), "01:01")
        XCTAssertEqual(StarMapPresentation.timeString(from: 1_439), "23:59")
    }

    func test_StarMapLayout_clampedFOV_limitsRange() {
        XCTAssertEqual(StarMapLayout.clampedFOV(20), StarMapLayout.minFOV)
        XCTAssertEqual(StarMapLayout.clampedFOV(90), 90)
        XCTAssertEqual(StarMapLayout.clampedFOV(160), StarMapLayout.maxFOV)
    }

    func test_StarMapUpdatePolicy_trailingDelay_switchesByScrubbingState() {
        XCTAssertEqual(
            StarMapUpdatePolicy.trailingDelay(now: 10.02, lastUpdateTime: 10.0, isScrubbing: false) ?? -1,
            (1.0 / 30) - 0.02,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapUpdatePolicy.trailingDelay(now: 10.02, lastUpdateTime: 10.0, isScrubbing: true) ?? -1,
            (1.0 / 20) - 0.02,
            accuracy: 0.0001
        )
        XCTAssertNil(StarMapUpdatePolicy.trailingDelay(now: 10.06, lastUpdateTime: 10.0, isScrubbing: true))
    }

    func test_StarMapUpdatePolicy_commitDelay_returnsNilWhenImmediateCommitIsAllowed() {
        XCTAssertEqual(
            StarMapUpdatePolicy.commitDelay(now: 10.02, lastCommitTime: 10.0) ?? -1,
            (1.0 / 20) - 0.02,
            accuracy: 0.0001
        )
        XCTAssertNil(StarMapUpdatePolicy.commitDelay(now: 10.1, lastCommitTime: 10.0))
    }

    func test_StarMapTimelinePolicy_clampedSliderMinutes_roundsAndClamps() {
        XCTAssertEqual(StarMapTimelinePolicy.clampedSliderMinutes(-3, nightDurationMinutes: 120), 0, accuracy: 0.001)
        XCTAssertEqual(StarMapTimelinePolicy.clampedSliderMinutes(18.6, nightDurationMinutes: 120), 19, accuracy: 0.001)
        XCTAssertEqual(StarMapTimelinePolicy.clampedSliderMinutes(180, nightDurationMinutes: 120), 120, accuracy: 0.001)
    }

    func test_StarMapTimelinePolicy_updateMode_controlsNightRangeAndSliderSync() {
        let oldDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 20))!
        let sameDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 22))!
        let nextDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 22))!

        XCTAssertFalse(StarMapTimelinePolicy.shouldUpdateNightRange(from: oldDate, to: sameDay, updateMode: .standard))
        XCTAssertTrue(StarMapTimelinePolicy.shouldUpdateNightRange(from: oldDate, to: nextDay, updateMode: .standard))
        XCTAssertFalse(
            StarMapTimelinePolicy.shouldUpdateNightRange(
                from: oldDate,
                to: nextDay,
                updateMode: .preserveNightRangeAndSlider
            )
        )
        XCTAssertFalse(StarMapTimelinePolicy.shouldSyncTimeSlider(updateMode: .preserveNightRangeAndSlider))
    }

    func test_StarMapCanvasProjection_zoomedFOV_clampsAndFollowsScrollDirection() {
        XCTAssertEqual(
            StarMapCanvasProjection.zoomedFOV(currentFOV: 90, scrollDeltaY: 1, preciseScrolling: false),
            86,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StarMapCanvasProjection.zoomedFOV(currentFOV: 90, scrollDeltaY: -1, preciseScrolling: true),
            91.2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StarMapCanvasProjection.zoomedFOV(currentFOV: 31, scrollDeltaY: 10, preciseScrolling: false),
            StarMapLayout.minFOV,
            accuracy: 0.001
        )
    }

    func test_StarMapCanvasProjection_cardinalLabelHelpers_placeLabelsInFixedBottomOverlay() {
        XCTAssertEqual(
            StarMapCanvasProjection.cardinalOverlayY(sizeHeight: 400),
            400 - Double(StarMapLayout.cardinalLabelBottomInset),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapCanvasProjection.clampedCardinalLabelX(-5, sizeWidth: 320),
            Double(StarMapLayout.cardinalLabelSidePadding),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapCanvasProjection.clampedCardinalLabelX(400, sizeWidth: 320),
            320 - Double(StarMapLayout.cardinalLabelSidePadding),
            accuracy: 0.0001
        )

        let placements = StarMapCanvasProjection.cardinalLabelPlacements(
            size: CGSize(width: 320, height: 400),
            centerAlt: 30,
            centerAz: 0,
            fov: 90
        )
        XCTAssertEqual(placements.map(\.label), ["北", "北東", "北西"])
    }

    func test_StarMapCanvasProjection_adjustedCenter_convertsDragIntoClampedOrientation() {
        let center = StarMapCanvasProjection.adjustedCenter(
            viewAltitude: 20,
            viewAzimuth: 15,
            translation: CGSize(width: 200, height: -120),
            size: CGSize(width: 400, height: 300),
            fov: 90
        )

        XCTAssertGreaterThan(center.az, 300)
        XCTAssertLessThan(center.alt, 0)
    }

    func test_StarMapCanvasInteraction_wrapsAzimuthAndClampsAltitude() {
        XCTAssertEqual(StarMapCanvasInteraction.movedAzimuth(current: 350, step: 20), 10, accuracy: 0.0001)
        XCTAssertEqual(StarMapCanvasInteraction.movedAzimuth(current: 5, step: -20), 345, accuracy: 0.0001)
        XCTAssertEqual(StarMapCanvasInteraction.movedAltitude(current: 85, step: 10), 89, accuracy: 0.0001)
        XCTAssertEqual(StarMapCanvasInteraction.movedAltitude(current: -8, step: -10), -10, accuracy: 0.0001)
    }

    func test_StarMapCanvasInteraction_committedFOV_clampsMagnificationResult() {
        XCTAssertEqual(
            StarMapCanvasInteraction.committedFOV(currentFOV: 90, magnification: 2),
            45,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapCanvasInteraction.committedFOV(currentFOV: 40, magnification: 5),
            StarMapLayout.minFOV,
            accuracy: 0.0001
        )
    }

    func test_StarMapCanvasInteraction_nearestStar_prefersClosestBrightVisibleStar() {
        let sirius = Star(name: "シリウス", ra: 0, dec: 0, magnitude: -1.46, colorIndex: 0.01)
        let rigel = Star(name: "リゲル", ra: 0, dec: 0, magnitude: 0.13, colorIndex: -0.03)
        let dimStar = Star(name: "暗い星", ra: 0, dec: 0, magnitude: 4.5, colorIndex: nil)
        let positions = [
            StarPosition(star: sirius, altitude: 45, azimuth: 0, precomputedColor: .white),
            StarPosition(star: rigel, altitude: 45, azimuth: 8, precomputedColor: .white),
            StarPosition(star: dimStar, altitude: 45, azimuth: 1, precomputedColor: .white)
        ]

        let nearest = StarMapCanvasInteraction.nearestStar(
            at: CGPoint(x: 102, y: 100),
            starPositions: positions,
            size: CGSize(width: 200, height: 200),
            fov: 90,
            centerAlt: 45,
            centerAz: 0
        )

        XCTAssertEqual(nearest?.star.name, "シリウス")
    }
}
