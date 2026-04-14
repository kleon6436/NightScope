import XCTest
import Combine
@testable import NightScope

@MainActor
final class StarMapViewModelTests: XCTestCase {

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

    func test_StarMapCanvasView_zoomedFOV_clampsAndFollowsScrollDirection() {
        XCTAssertEqual(
            StarMapCanvasView.zoomedFOV(currentFOV: 90, scrollDeltaY: 1, preciseScrolling: false),
            86,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StarMapCanvasView.zoomedFOV(currentFOV: 90, scrollDeltaY: -1, preciseScrolling: true),
            91.2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StarMapCanvasView.zoomedFOV(currentFOV: 31, scrollDeltaY: 10, preciseScrolling: false),
            StarMapLayout.minFOV,
            accuracy: 0.001
        )
    }

    func test_StarMapCanvasView_cardinalLabelHelpers_placeLabelsInFixedBottomOverlay() {
        XCTAssertEqual(
            StarMapCanvasView.cardinalOverlayY(sizeHeight: 400),
            400 - Double(StarMapLayout.cardinalLabelBottomInset),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapCanvasView.clampedCardinalLabelX(-5, sizeWidth: 320),
            Double(StarMapLayout.cardinalLabelSidePadding),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StarMapCanvasView.clampedCardinalLabelX(400, sizeWidth: 320),
            320 - Double(StarMapLayout.cardinalLabelSidePadding),
            accuracy: 0.0001
        )

        let placements = StarMapCanvasView.cardinalLabelPlacements(
            size: CGSize(width: 320, height: 400),
            centerAlt: 30,
            centerAz: 0,
            fov: 90
        )
        XCTAssertEqual(placements.map(\.label), ["北", "北東", "北西"])
    }

    func test_StarDisplayDensity_usesExpectedThresholdsAndLabels() {
        XCTAssertEqual(StarDisplayDensity.maximum.settingsLabel, "最大（7.5等級まで）")
        XCTAssertEqual(StarDisplayDensity.large.settingsLabel, "大（6.8等級まで）")
        XCTAssertEqual(StarDisplayDensity.medium.settingsLabel, "中（6.0等級まで）")
        XCTAssertEqual(StarDisplayDensity.small.settingsLabel, "小（5.0等級まで）")

        XCTAssertEqual(StarDisplayDensity.maximum.maxMagnitude, 7.5, accuracy: 0.0001)
        XCTAssertEqual(StarDisplayDensity.large.maxMagnitude, 6.8, accuracy: 0.0001)
        XCTAssertEqual(StarDisplayDensity.medium.maxMagnitude, 6.0, accuracy: 0.0001)
        XCTAssertEqual(StarDisplayDensity.small.maxMagnitude, 5.0, accuracy: 0.0001)
    }

    func test_StarMapViewModel_recomputesWhenStarDisplayDensityChanges() {
        let key = StarDisplayDensity.defaultsKey
        let previousValue = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(StarDisplayDensity.maximum.rawValue, forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        var cancellables = Set<AnyCancellable>()

        let initialExpectation = expectation(description: "initial star positions")
        var initialCount = 0
        var initialCancellable: AnyCancellable?
        initialCancellable = viewModel.$starPositions
            .sink { stars in
                guard stars.count > 0 else { return }
                guard initialCount == 0 else { return }
                initialCount = stars.count
                initialExpectation.fulfill()
                initialCancellable?.cancel()
            }
        if let initialCancellable {
            initialCancellable.store(in: &cancellables)
        }
        wait(for: [initialExpectation], timeout: 5)

        let reducedExpectation = expectation(description: "reduced star positions")
        var reducedCancellable: AnyCancellable?
        reducedCancellable = viewModel.$starPositions
            .dropFirst()
            .sink { stars in
                guard stars.count < initialCount else { return }
                reducedExpectation.fulfill()
                reducedCancellable?.cancel()
            }
        if let reducedCancellable {
            reducedCancellable.store(in: &cancellables)
        }

        viewModel.setStarDisplayDensity(.small)

        wait(for: [reducedExpectation], timeout: 5)
    }

    func test_StarMapViewModel_initialPose_usesResetAltitude() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let size = CGSize(width: 860, height: 620)

        viewModel.viewAzimuth = 123
        viewModel.viewAltitude = 10
        viewModel.updateCanvasSize(size)
        viewModel.prepareForStarMapPresentation()
        viewModel.applyInitialPoseIfNeeded()

        XCTAssertEqual(viewModel.viewAzimuth, 0)
        XCTAssertEqual(viewModel.viewAltitude, StarMapLayout.resetAltitude, accuracy: 0.001)
    }

    func test_StarMapViewModel_resetToNorth_usesResetAltitude() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)

        viewModel.viewAzimuth = 180
        viewModel.viewAltitude = 60
        viewModel.resetToNorth()

        XCTAssertEqual(viewModel.viewAzimuth, 0)
        XCTAssertEqual(viewModel.viewAltitude, StarMapLayout.resetAltitude, accuracy: 0.001)
    }

    func test_StarMapViewModel_displayDate_updatesTimeSliderMinutes() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = Calendar.current
        let targetDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 10,
            hour: 22,
            minute: 45
        ))!

        viewModel.displayDate = targetDate

        let realMinutes = 22 * 60 + 45
        var expectedOffset = Double(realMinutes) - viewModel.nightStartMinutes
        if expectedOffset < 0 { expectedOffset += 1_440 }
        expectedOffset = max(0, min(viewModel.nightDurationMinutes, expectedOffset))

        XCTAssertEqual(viewModel.timeSliderMinutes, expectedOffset, accuracy: 0.001)
        XCTAssertEqual(viewModel.displayTimeString, "22:45")
    }

    func test_StarMapViewModel_setTimeSliderMinutes_updatesDisplayDateKeepingDate() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = Calendar.current
        let baseDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 10,
            hour: 21,
            minute: 15
        ))!
        viewModel.displayDate = baseDate

        let sliderOffset = min(120.0, viewModel.nightDurationMinutes)
        viewModel.setTimeSliderMinutes(sliderOffset)

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: viewModel.displayDate
        )
        let expectedRealMinutes = (viewModel.nightStartMinutes + sliderOffset)
            .truncatingRemainder(dividingBy: 1_440)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, Int(expectedRealMinutes) / 60)
        XCTAssertEqual(components.minute, Int(expectedRealMinutes) % 60)
        XCTAssertEqual(viewModel.timeSliderMinutes, sliderOffset, accuracy: 0.001)
    }

    func test_StarMapViewModel_timeSliderInteraction_commitsFinalDateOnEnd() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = Calendar.current
        let baseDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 10,
            hour: 20,
            minute: 0
        ))!
        viewModel.displayDate = baseDate

        viewModel.beginTimeSliderInteraction()
        viewModel.setTimeSliderMinutes(90)

        XCTAssertTrue(viewModel.isTimeSliderScrubbing)
        XCTAssertEqual(viewModel.timeSliderMinutes, 90, accuracy: 0.001)

        viewModel.endTimeSliderInteraction()

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: viewModel.displayDate
        )
        let expectedRealMinutes = (viewModel.nightStartMinutes + 90)
            .truncatingRemainder(dividingBy: 1_440)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, Int(expectedRealMinutes) / 60)
        XCTAssertEqual(components.minute, Int(expectedRealMinutes) % 60)
        XCTAssertFalse(viewModel.isTimeSliderScrubbing)
    }

    func test_StarMapViewModel_syncWithSelectedDate_snapsDaytimeToSelectedEvening() throws {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 1,
            hour: 6,
            minute: 7
        ))!

        appController.selectedDate = selectedDate
        viewModel.syncWithSelectedDate(referenceDate: referenceDate)

        let twilight = try XCTUnwrap(
            MilkyWayCalculator.findCivilTwilightMinutes(
                date: selectedDate,
                location: appController.locationController.selectedLocation,
                timeZone: appController.locationController.selectedTimeZone
            )
        )
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: viewModel.displayDate
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, Int(twilight.eveningMinutes) / 60)
        XCTAssertEqual(components.minute, Int(twilight.eveningMinutes) % 60)
        XCTAssertEqual(viewModel.timeSliderMinutes, 0, accuracy: 0.001)
    }

    func test_StarMapViewModel_syncWithSelectedDate_keepsCurrentTimeDuringNight() {
        let appController = AppController(calculationService: MockNightCalculationService())
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 1,
            hour: 21,
            minute: 7
        ))!

        appController.selectedDate = selectedDate
        viewModel.syncWithSelectedDate(referenceDate: referenceDate)

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: viewModel.displayDate
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 21)
        XCTAssertEqual(components.minute, 7)
        let realMinutes = 21 * 60 + 7
        var expectedOffset = Double(realMinutes) - viewModel.nightStartMinutes
        if expectedOffset < 0 { expectedOffset += 1_440 }
        expectedOffset = max(0, min(viewModel.nightDurationMinutes, expectedOffset))
        XCTAssertEqual(viewModel.timeSliderMinutes, expectedOffset, accuracy: 0.001)
    }

    func test_StarMapViewModel_terrainCacheKey_roundsCoordinatesConsistently() {
        XCTAssertEqual(
            StarMapViewModel.terrainCacheKey(latitude: 35.1234, longitude: 139.5678),
            "35.12,139.57"
        )
        XCTAssertEqual(
            StarMapViewModel.terrainCacheKey(latitude: -35.1251, longitude: -139.5651),
            "-35.13,-139.57"
        )
    }
}
