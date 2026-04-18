import XCTest
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class MapKitSharedLogicTests: XCTestCase {
    func test_applyViewportSyncIfNeeded_returnsRegionForNewTrigger() {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let syncState = MapKitSyncState(
            trigger: 1,
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        var lastSyncTrigger = 0

        let region = MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            syncState: syncState,
            lastSyncTrigger: &lastSyncTrigger
        )

        guard let region else {
            return XCTFail("sync region が返されませんでした")
        }
        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(region.span.latitudeDelta, 0.5, accuracy: 0.000001)
        XCTAssertEqual(region.span.longitudeDelta, 0.5, accuracy: 0.000001)
        XCTAssertEqual(lastSyncTrigger, 1)
    }

    func test_centerOnCurrentLocationIfNeeded_returnsRegionForNewTrigger() {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        var lastCenterTrigger = 0

        let region = MapKitViewSharedLogic.centerOnCurrentLocationIfNeeded(
            coordinate: coordinate,
            centerTrigger: 1,
            lastCenterTrigger: &lastCenterTrigger
        )

        guard let region else {
            return XCTFail("center region が返されませんでした")
        }
        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(region.span.latitudeDelta, 0.5, accuracy: 0.000001)
        XCTAssertEqual(region.span.longitudeDelta, 0.5, accuracy: 0.000001)
        XCTAssertEqual(lastCenterTrigger, 1)
    }

    func test_applyViewportSyncIfNeeded_sanitizesInvalidCenterToDefaultCoordinate() {
        let syncState = MapKitSyncState(
            trigger: 1,
            center: CLLocationCoordinate2D(latitude: 90.0522, longitude: -62.2437),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        var lastSyncTrigger = 0

        let region = MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            syncState: syncState,
            lastSyncTrigger: &lastSyncTrigger
        )

        guard let region else {
            return XCTFail("sync region が返されませんでした")
        }
        XCTAssertEqual(region.center.latitude, GeoStateValidator.defaultCoordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(region.center.longitude, GeoStateValidator.defaultCoordinate.longitude, accuracy: 0.000001)
    }

    func test_applyViewportSyncIfNeeded_clampsInvalidSpan() {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let syncState = MapKitSyncState(
            trigger: 1,
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: -1, longitudeDelta: 720)
        )
        var lastSyncTrigger = 0

        let region = MapKitViewSharedLogic.applyViewportSyncIfNeeded(
            syncState: syncState,
            lastSyncTrigger: &lastSyncTrigger
        )

        guard let region else {
            return XCTFail("sync region が返されませんでした")
        }
        XCTAssertEqual(region.span.latitudeDelta, 1, accuracy: 0.000001)
        XCTAssertEqual(region.span.longitudeDelta, 360, accuracy: 0.000001)
    }

    func test_consumePendingRegionChangeIgnore_decrementsCounter() {
        var pendingIgnoredRegionChanges = 2

        XCTAssertTrue(MapKitViewSharedLogic.consumePendingRegionChangeIgnore(&pendingIgnoredRegionChanges))
        XCTAssertEqual(pendingIgnoredRegionChanges, 1)
        XCTAssertTrue(MapKitViewSharedLogic.consumePendingRegionChangeIgnore(&pendingIgnoredRegionChanges))
        XCTAssertEqual(pendingIgnoredRegionChanges, 0)
        XCTAssertFalse(MapKitViewSharedLogic.consumePendingRegionChangeIgnore(&pendingIgnoredRegionChanges))
    }

    func test_coordinatorState_noOpScheduleDoesNotIgnoreNextUserRegionChange() async {
        let state = MapKitCoordinatorState(syncTrigger: 0, centerTrigger: 0)
        let mapView = MKMapView()
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        mapView.region = region
        let normalizedRegion = mapView.region

        state.scheduleRegionChange(on: mapView, region: normalizedRegion, animated: false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let expectation = expectation(description: "user region change")
        state.handleRegionDidChange(mapView: mapView) { _, _ in
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_coordinatorState_pendingIgnoreExpiresWhenCallbackDoesNotArrive() async {
        let state = MapKitCoordinatorState(syncTrigger: 0, centerTrigger: 0)
        let mapView = MKMapView()
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        state.scheduleRegionChange(
            on: mapView,
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
                span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
            ),
            animated: false
        )

        try? await Task.sleep(nanoseconds: 650_000_000)

        let expectation = expectation(description: "stale ignore reset")
        state.handleRegionDidChange(mapView: mapView) { _, _ in
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_coordinatorState_tracksViewportAndCenterTriggers() {
        let coordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let syncState = MapKitSyncState(
            trigger: 1,
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
        let state = MapKitCoordinatorState(syncTrigger: 0, centerTrigger: 0)

        let syncedRegion = state.syncedRegion(syncState: syncState)
        let centeredRegion = state.centeredRegion(coordinate: coordinate, centerTrigger: 1)

        XCTAssertEqual(syncedRegion?.span.latitudeDelta ?? -1, 0.4, accuracy: 0.000001)
        XCTAssertEqual(centeredRegion?.center.latitude ?? -1, coordinate.latitude, accuracy: 0.000001)
    }

    func test_geoStateValidator_rejectsOutOfBoundsCoordinate() {
        XCTAssertNil(
            GeoStateValidator.sanitizedCoordinate(
                CLLocationCoordinate2D(latitude: 95, longitude: 139.6503)
            )
        )
    }
}
