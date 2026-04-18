import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class StarMapViewModelTests: XCTestCase {
    final class InMemoryLocationStorage: LocationStorage {
        var latitude: Double?
        var longitude: Double?
        var name: String?
        var timeZoneIdentifier: String?
    }

    struct NoopLocationSearchService: LocationSearchServicing {
        func search(query: String) async throws -> [MKMapItem] {
            []
        }
    }

    actor FixedLocationNameResolver: LocationNameResolving {
        let resolvedName: String
        let timeZoneIdentifier: String?

        init(resolvedName: String, timeZoneIdentifier: String?) {
            self.resolvedName = resolvedName
            self.timeZoneIdentifier = timeZoneIdentifier
        }

        func resolveDetails(for coordinate: CLLocationCoordinate2D) async -> ResolvedLocationDetails {
            ResolvedLocationDetails(name: resolvedName, timeZoneIdentifier: timeZoneIdentifier)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("条件を満たすまでにタイムアウトしました", file: file, line: line)
    }

    private func makeTokyoAppController() -> AppController {
        let storage = InMemoryLocationStorage()
        storage.latitude = 35.6762
        storage.longitude = 139.6503
        storage.name = "東京"
        storage.timeZoneIdentifier = "Asia/Tokyo"

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                resolvedName: "東京",
                timeZoneIdentifier: "Asia/Tokyo"
            )
        )

        return AppController(
            locationController: locationController,
            calculationService: MockNightCalculationService()
        )
    }

    private func observationCalendar(for timeZone: TimeZone) -> Calendar {
        ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
    }

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
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
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
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
        let baseDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 10,
            hour: 21,
            minute: 15
        ))!
        appController.selectedDate = baseDate
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
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
        let baseDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 10,
            hour: 20,
            minute: 0
        ))!
        appController.selectedDate = baseDate
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
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
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
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
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

    func test_StarMapViewModel_syncWithSelectedDate_movesAfterMidnightIntoNextDay() {
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 1,
            hour: 2,
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
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 2)
        XCTAssertEqual(components.minute, 7)
    }

    func test_StarMapViewModel_setTimeSliderMinutes_keepsObservationNightAcrossMidnight() {
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let calendar = observationCalendar(for: appController.locationController.selectedTimeZone)
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 1,
            hour: 2,
            minute: 7
        ))!

        appController.selectedDate = selectedDate
        viewModel.syncWithSelectedDate(referenceDate: referenceDate)
        viewModel.setTimeSliderMinutes(0)

        let twilight = MilkyWayCalculator.findCivilTwilightMinutes(
            date: selectedDate,
            location: appController.locationController.selectedLocation,
            timeZone: appController.locationController.selectedTimeZone
        )
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: viewModel.displayDate
        )

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, Int((twilight?.eveningMinutes ?? 0)) / 60)
        XCTAssertEqual(components.minute, Int((twilight?.eveningMinutes ?? 0)) % 60)
    }

    func test_StarMapViewModel_updatesTimeSliderWhenTimeZoneChanges() async {
        let storage = InMemoryLocationStorage()
        storage.latitude = 35.6762
        storage.longitude = 139.6503
        storage.name = "東京"
        storage.timeZoneIdentifier = "Asia/Tokyo"

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                resolvedName: "ロサンゼルス",
                timeZoneIdentifier: "America/Los_Angeles"
            )
        )
        let appController = AppController(
            locationController: locationController,
            calculationService: MockNightCalculationService()
        )
        let viewModel = StarMapViewModel(appController: appController)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let displayDate = utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 4,
            minute: 0
        ))!

        viewModel.displayDate = displayDate
        let initialTimeSliderMinutes = viewModel.timeSliderMinutes

        locationController.selectCoordinate(
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        )

        await waitUntil(timeout: 2.0) {
            locationController.selectedTimeZone.identifier == "America/Los_Angeles"
                && abs(viewModel.timeSliderMinutes - initialTimeSliderMinutes) > 0.5
        }

        let expectedRealMinutes = StarMapDateLogic.clockMinutes(
            for: displayDate,
            timeZone: locationController.selectedTimeZone
        )
        let expectedOffset = StarMapDateLogic.realMinutesToNightOffset(
            expectedRealMinutes,
            nightStartMinutes: viewModel.nightStartMinutes,
            nightDurationMinutes: viewModel.nightDurationMinutes
        )

        XCTAssertEqual(locationController.selectedTimeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(viewModel.timeSliderMinutes, expectedOffset, accuracy: 0.001)
    }

    func test_StarMapViewModel_timeZoneChange_reanchorsDisplayDateToObservationNight() async {
        let storage = InMemoryLocationStorage()
        storage.latitude = 35.6762
        storage.longitude = 139.6503
        storage.name = "東京"
        storage.timeZoneIdentifier = "Asia/Tokyo"

        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                resolvedName: "ロサンゼルス",
                timeZoneIdentifier: "America/Los_Angeles"
            )
        )
        let appController = AppController(
            locationController: locationController,
            calculationService: MockNightCalculationService()
        )
        let viewModel = StarMapViewModel(appController: appController)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let tokyoCalendar = ObservationTimeZone.gregorianCalendar(timeZone: tokyo)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        appController.selectedDate = tokyoCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12
        ))!
        let initialDisplayDate = utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 4,
            minute: 0
        ))!
        viewModel.displayDate = initialDisplayDate

        locationController.selectCoordinate(
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        )

        await waitUntil(timeout: 2.0) {
            locationController.selectedTimeZone.identifier == losAngeles.identifier
        }

        let expectedDate = StarMapDateLogic.resolvedPresentationDate(
            for: appController.selectedDate,
            referenceDate: initialDisplayDate,
            location: locationController.selectedLocation,
            timeZone: losAngeles
        )

        XCTAssertEqual(viewModel.displayDate, expectedDate)
    }

    func test_StarMapViewModel_setObservationDate_preservesDisplayedNightTime() {
        let appController = makeTokyoAppController()
        let viewModel = StarMapViewModel(appController: appController)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: tokyo)

        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let nextDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 1,
            hour: 21,
            minute: 7
        ))!

        appController.selectedDate = selectedDate
        viewModel.syncWithSelectedDate(referenceDate: referenceDate)
        viewModel.setObservationDate(nextDate)

        let displayComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: viewModel.displayDate)
        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: appController.selectedDate)

        XCTAssertEqual(selectedComponents.year, 2026)
        XCTAssertEqual(selectedComponents.month, 8)
        XCTAssertEqual(selectedComponents.day, 13)
        XCTAssertEqual(displayComponents.year, 2026)
        XCTAssertEqual(displayComponents.month, 8)
        XCTAssertEqual(displayComponents.day, 13)
        XCTAssertEqual(displayComponents.hour, 21)
        XCTAssertEqual(displayComponents.minute, 7)
    }

    func test_StarMapViewModel_setObservationDate_triggersNightRecalculation() async {
        let calculationService = MockNightCalculationService()
        let storage = InMemoryLocationStorage()
        storage.latitude = 35.6762
        storage.longitude = 139.6503
        storage.name = "東京"
        storage.timeZoneIdentifier = "Asia/Tokyo"
        let locationController = LocationController(
            storage: storage,
            searchService: NoopLocationSearchService(),
            locationNameResolver: FixedLocationNameResolver(
                resolvedName: "東京",
                timeZoneIdentifier: "Asia/Tokyo"
            )
        )
        let appController = AppController(
            locationController: locationController,
            calculationService: calculationService
        )
        let viewModel = StarMapViewModel(appController: appController)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: tokyo)
        let nextDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!

        viewModel.setObservationDate(nextDate)

        await waitUntil {
            appController.selectedDate == nextDate
        }

        for _ in 0..<30 {
            let nightCalls = await calculationService.getNightSummaryCallCount()
            if nightCalls > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let nightCallCount = await calculationService.getNightSummaryCallCount()
        XCTAssertGreaterThanOrEqual(nightCallCount, 1)
    }

    func test_StarMapViewModel_terrainCacheKey_roundsCoordinatesConsistently() {
        XCTAssertEqual(
            StarMapViewModel.terrainCacheKey(latitude: 35.1234, longitude: 139.5678),
            "35.125,139.57"
        )
        XCTAssertEqual(
            StarMapViewModel.terrainCacheKey(latitude: -35.1251, longitude: -139.5651),
            "-35.125,-139.565"
        )
    }
}
