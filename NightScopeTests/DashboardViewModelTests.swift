import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func test_reloadFavorites_initializesSelectionUpToMaxAndKeepsExisting() {
        let favorites = makeFavorites(count: 8)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()

        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        XCTAssertEqual(viewModel.selectedIDs, Set(favorites.prefix(DashboardViewModel.maxSelection).map(\.id)))

        let retainedID = favorites[2].id
        viewModel.selectedIDs = [retainedID, UUID()]
        viewModel.reloadFavorites()

        XCTAssertEqual(viewModel.selectedIDs, [retainedID])
    }

    func test_toggleSelection_respectsMaxLimit() {
        let favorites = makeFavorites(count: 7)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        let before = viewModel.selectedIDs
        let seventhID = favorites[6].id
        viewModel.toggleSelection(seventhID)
        XCTAssertEqual(viewModel.selectedIDs, before)

        let removableID = favorites[0].id
        viewModel.toggleSelection(removableID)
        XCTAssertFalse(viewModel.selectedIDs.contains(removableID))
    }

    func test_existingFavoriteNear_returnsMatchingWithin100m() {
        let favorite = makeFavorite(name: "Tokyo")
        let store = StubFavoriteStore(favorites: [favorite])
        let viewModel = DashboardViewModel(comparisonController: StubComparisonController(), favoriteStore: store)

        let mapItem = makeMapItem(
            latitude: favorite.latitude + 0.0005,
            longitude: favorite.longitude + 0.0005,
            name: "Nearby"
        )

        XCTAssertEqual(viewModel.existingFavorite(near: mapItem)?.id, favorite.id)
    }

    func test_existingFavoriteNear_returnsNilBeyond100m() {
        let favorite = makeFavorite(name: "Tokyo")
        let store = StubFavoriteStore(favorites: [favorite])
        let viewModel = DashboardViewModel(comparisonController: StubComparisonController(), favoriteStore: store)

        let mapItem = makeMapItem(
            latitude: favorite.latitude + 0.002,
            longitude: favorite.longitude + 0.002,
            name: "Far"
        )

        XCTAssertNil(viewModel.existingFavorite(near: mapItem))
    }

    func test_registerAndSelect_newLocation_addsToFavoritesAndSelectedIDs() {
        let store = StubFavoriteStore(favorites: [])
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        let outcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0),
            name: "New Location",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        guard case let .registered(newID, swap) = outcome else {
            return XCTFail("Expected registered outcome")
        }

        XCTAssertNil(swap)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(store.favorites.first?.id, newID)
        XCTAssertEqual(viewModel.selectedIDs, [newID])
        XCTAssertEqual(viewModel.selectionOrder, [newID])
    }

    func test_registerAndSelect_alreadyExisted_addsExistingIDToSelectedIDs_withoutNewFavorite() {
        let favorite = makeFavorite(name: "Existing")
        let store = StubFavoriteStore(favorites: [favorite])
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)
        viewModel.toggleSelection(favorite.id)

        let outcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude),
            name: "Ignored",
            timeZoneIdentifier: favorite.timeZoneIdentifier
        )

        guard case let .alreadyExisted(existingID) = outcome else {
            return XCTFail("Expected alreadyExisted outcome")
        }

        XCTAssertEqual(existingID, favorite.id)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(viewModel.selectedIDs, [favorite.id])
        XCTAssertEqual(viewModel.selectionOrder, [favorite.id])
    }

    func test_registerAndSelect_atSelectionLimit_swapsOldestSelection() {
        let favorites = makeFavorites(count: 6)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        let outcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 140.0),
            name: "Newest",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        guard case let .registered(newID, swap) = outcome else {
            return XCTFail("Expected registered outcome")
        }

        XCTAssertEqual(viewModel.selectedIDs.count, DashboardViewModel.maxSelection)
        XCTAssertFalse(viewModel.selectedIDs.contains(favorites[0].id))
        XCTAssertTrue(viewModel.selectedIDs.contains(newID))
        XCTAssertEqual(viewModel.selectionOrder.last, newID)
        XCTAssertEqual(swap?.removedID, favorites[0].id)
        XCTAssertEqual(swap?.addedID, newID)
    }

    func test_registerAndSelect_triggersSingleRefresh() async {
        let favorites = makeFavorites(count: 6)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController(matrix: .empty)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)
        try? await Task.sleep(for: .milliseconds(100))
        let beforeRefreshCalls = controller.computeMatrixCalls

        _ = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 140.0),
            name: "Newest",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(controller.computeMatrixCalls, beforeRefreshCalls + 1)
    }

    func test_undoLastSwap_restoresPreviousSelection() {
        let favorites = makeFavorites(count: 6)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        let outcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 140.0),
            name: "Newest",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        guard case let .registered(newID, swap) = outcome, let swap else {
            return XCTFail("Expected swap outcome")
        }

        viewModel.undoLastSwap()

        XCTAssertFalse(viewModel.selectedIDs.contains(newID))
        XCTAssertTrue(viewModel.selectedIDs.contains(swap.removedID))
        XCTAssertEqual(viewModel.selectionOrder.first, swap.removedID)
        XCTAssertNil(viewModel.lastSwap)
    }

    func test_undoLastSwap_restoresSwapsInLifoOrder() {
        let favorites = makeFavorites(count: 6)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        let firstOutcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 140.0),
            name: "Newest 1",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let secondOutcome = viewModel.registerAndSelect(
            coordinate: CLLocationCoordinate2D(latitude: 41.0, longitude: 141.0),
            name: "Newest 2",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        guard case let .registered(firstNewID, firstSwap?) = firstOutcome,
              case let .registered(secondNewID, secondSwap?) = secondOutcome else {
            return XCTFail("Expected swap outcomes")
        }

        viewModel.undoLastSwap()

        XCTAssertFalse(viewModel.selectedIDs.contains(secondNewID))
        XCTAssertTrue(viewModel.selectedIDs.contains(secondSwap.removedID))
        XCTAssertEqual(viewModel.lastSwap, firstSwap)

        viewModel.undoLastSwap()

        XCTAssertFalse(viewModel.selectedIDs.contains(firstNewID))
        XCTAssertTrue(viewModel.selectedIDs.contains(firstSwap.removedID))
        XCTAssertNil(viewModel.lastSwap)
    }

    func test_removeFavorite_removesFromStoreAndPrunesSelectedIDs() async {
        let favorites = makeFavorites(count: 3)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController(matrix: .empty)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        viewModel.removeFavorite(favorites[0].id)
        await Task.yield()

        XCTAssertEqual(store.favorites.map(\.id), [favorites[1].id, favorites[2].id])
        XCTAssertFalse(viewModel.selectedIDs.contains(favorites[0].id))
        XCTAssertFalse(viewModel.selectionOrder.contains(favorites[0].id))
    }

    func test_selectionOrder_isMaintainedOnToggleSelection() {
        let favorites = makeFavorites(count: 3)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController()
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        viewModel.toggleSelection(favorites[1].id)
        XCTAssertEqual(viewModel.selectionOrder, [favorites[0].id, favorites[2].id])

        viewModel.toggleSelection(favorites[1].id)
        XCTAssertEqual(viewModel.selectionOrder, [favorites[0].id, favorites[2].id, favorites[1].id])

        viewModel.toggleSelection(favorites[0].id)
        XCTAssertEqual(viewModel.selectionOrder, [favorites[2].id, favorites[1].id])
    }

    func test_sortedSelectedLocations_byScore_descendingWithNameTiebreak() async {
        let favorites = [
            makeFavorite(name: "Beta"),
            makeFavorite(name: "Alpha"),
            makeFavorite(name: "Gamma")
        ]
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = date1.addingTimeInterval(86_400)
        let matrix = makeMatrix(
            favorites: favorites,
            dates: [date1, date2],
            scores: [
                favorites[0].id: [5, 5],
                favorites[1].id: [10, 0],
                favorites[2].id: [4, 5]
            ]
        )
        let controller = StubComparisonController(matrix: matrix)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: StubFavoriteStore(favorites: favorites))
        await viewModel.refresh(referenceDate: date1)

        let sortedNames = viewModel.sortedSelectedLocations().map(\.name)
        XCTAssertEqual(sortedNames, ["Alpha", "Beta", "Gamma"])
    }

    func test_sortedSelectedLocations_byName_ascending() {
        let favorites = [
            makeFavorite(name: "Tokyo"),
            makeFavorite(name: "Aomori"),
            makeFavorite(name: "Osaka")
        ]
        let viewModel = DashboardViewModel(comparisonController: StubComparisonController(), favoriteStore: StubFavoriteStore(favorites: favorites))
        viewModel.sortKey = .name

        let sortedNames = viewModel.sortedSelectedLocations().map(\.name)
        XCTAssertEqual(sortedNames, ["Aomori", "Osaka", "Tokyo"])
    }

    func test_sortedSelectedLocations_byBestDate_ascendingWithNameTiebreak() async {
        let favorites = [
            makeFavorite(name: "Alpha"),
            makeFavorite(name: "Beta"),
            makeFavorite(name: "Gamma")
        ]
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = date1.addingTimeInterval(86_400)
        let matrix = makeMatrix(
            favorites: favorites,
            dates: [date1, date2],
            scores: [
                favorites[0].id: [1, 10],
                favorites[1].id: [9, 2],
                favorites[2].id: [1, 8]
            ]
        )
        let controller = StubComparisonController(matrix: matrix)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: StubFavoriteStore(favorites: favorites))
        await viewModel.refresh(referenceDate: date1)
        viewModel.sortKey = .bestDate

        let sortedNames = viewModel.sortedSelectedLocations().map(\.name)
        XCTAssertEqual(sortedNames, ["Beta", "Alpha", "Gamma"])
    }

    func test_bestLocationID_returnsHighestScoringLocationForDate_withNameTiebreakOnTie() async {
        let favorites = [
            makeFavorite(name: "Beta"),
            makeFavorite(name: "Alpha"),
            makeFavorite(name: "Gamma")
        ]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let matrix = makeMatrix(
            favorites: favorites,
            dates: [date],
            scores: [
                favorites[0].id: [10],
                favorites[1].id: [10],
                favorites[2].id: [8]
            ]
        )
        let controller = StubComparisonController(matrix: matrix)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: StubFavoriteStore(favorites: favorites))
        await viewModel.refresh(referenceDate: date)

        XCTAssertEqual(viewModel.bestLocationID(for: date.addingTimeInterval(21_600)), favorites[1].id)
    }

    func test_bestLocationID_returnsNilWhenAllScoresNil() async {
        let favorites = [makeFavorite(name: "Alpha"), makeFavorite(name: "Beta")]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let matrix = makeMatrix(
            favorites: favorites,
            dates: [date],
            scores: [
                favorites[0].id: [nil],
                favorites[1].id: [nil]
            ]
        )
        let controller = StubComparisonController(matrix: matrix)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: StubFavoriteStore(favorites: favorites))
        await viewModel.refresh(referenceDate: date)

        XCTAssertNil(viewModel.bestLocationID(for: date.addingTimeInterval(3_600)))
    }

    func test_refresh_callsControllerWithFilteredLocationsOnly() async {
        let favorites = makeFavorites(count: 3)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController(matrix: .empty)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        viewModel.selectedIDs = [favorites[0].id, favorites[2].id]
        await viewModel.refresh(referenceDate: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(controller.lastLocations?.map(\.id), [favorites[0].id, favorites[2].id])
    }

    func test_favoriteUpdates_pruneSelectionAndRefreshWhenSelectionRemains() async {
        let favorites = makeFavorites(count: 3)
        let store = StubFavoriteStore(favorites: favorites)
        let controller = StubComparisonController(matrix: .empty)
        let viewModel = DashboardViewModel(comparisonController: controller, favoriteStore: store)

        viewModel.selectedIDs = [favorites[0].id, favorites[1].id]
        let beforeRefreshCalls = controller.computeMatrixCalls
        store.favorites = [favorites[0]]
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.availableFavorites.map(\.id), [favorites[0].id])
        XCTAssertEqual(viewModel.selectedIDs, [favorites[0].id])
        XCTAssertGreaterThan(controller.computeMatrixCalls, beforeRefreshCalls)
    }

    private func makeFavorites(count: Int) -> [FavoriteLocation] {
        (0..<count).map { index in
            FavoriteLocation(
                id: UUID(),
                name: String(format: "Location %02d", index + 1),
                latitude: Double(index),
                longitude: Double(index),
                timeZoneIdentifier: TimeZone.current.identifier,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
    }

    private func makeFavorite(name: String) -> FavoriteLocation {
        FavoriteLocation(
            id: UUID(),
            name: name,
            latitude: 35.0,
            longitude: 135.0,
            timeZoneIdentifier: TimeZone.current.identifier,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeMapItem(latitude: Double, longitude: Double, name: String) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    private func makeMatrix(
        favorites: [FavoriteLocation],
        dates: [Date],
        scores: [UUID: [Int?]]
    ) -> ComparisonMatrix {
        var cellsByID: [String: ComparisonCell] = [:]
        for favorite in favorites {
            for (index, date) in dates.enumerated() {
                let score = scores[favorite.id]?[index]
                let indexValue = score.map {
                    StarGazingIndex(
                        score: $0,
                        milkyWayScore: 0,
                        constellationScore: 0,
                        weatherScore: 0,
                        lightPollutionScore: 0,
                        hasWeatherData: true,
                        hasLightPollutionData: true
                    )
                }
                let cell = ComparisonCell(
                    locationID: favorite.id,
                    date: date,
                    index: indexValue,
                    loadState: .loaded
                )
                cellsByID[cell.id] = cell
            }
        }
        return ComparisonMatrix(locations: favorites, dates: dates, cellsByID: cellsByID)
    }
}

@MainActor
private final class StubComparisonController: ComparisonControlling {
    var matrix: ComparisonMatrix
    var dayCount: Int = DashboardViewModel.dayCount
    private(set) var lastLocations: [FavoriteLocation]?
    private(set) var refreshCalls: Int = 0
    private(set) var computeMatrixCalls: Int = 0

    init(matrix: ComparisonMatrix = .empty) {
        self.matrix = matrix
    }

    func refresh(referenceDate: Date, locations: [FavoriteLocation]?) async {
        refreshCalls += 1
        lastLocations = locations
    }

    func computeMatrix(referenceDate: Date, locations: [FavoriteLocation]?) async -> ComparisonMatrix {
        computeMatrixCalls += 1
        lastLocations = locations
        return matrix
    }
}

private final class StubFavoriteStore: FavoriteLocationStoring, @unchecked Sendable {
    var favorites: [FavoriteLocation] {
        didSet { subject.send(favorites) }
    }
    private let subject: CurrentValueSubject<[FavoriteLocation], Never>

    init(favorites: [FavoriteLocation] = []) {
        self.favorites = favorites
        self.subject = CurrentValueSubject(favorites)
    }

    func loadAll() -> [FavoriteLocation] {
        favorites
    }

    var locationsPublisher: AnyPublisher<[FavoriteLocation], Never> {
        subject.eraseToAnyPublisher()
    }

    func save(_ favorites: [FavoriteLocation]) {
        self.favorites = favorites
    }
}
