import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
protocol ComparisonControlling: AnyObject {
    var matrix: ComparisonMatrix { get }
    var dayCount: Int { get set }

    func refresh(referenceDate: Date, locations: [FavoriteLocation]?) async
    func computeMatrix(referenceDate: Date, locations: [FavoriteLocation]?) async -> ComparisonMatrix
}

extension ComparisonController: ComparisonControlling {}

@MainActor
final class DashboardViewModel: ObservableObject {
    enum SortKey: String, CaseIterable, Identifiable {
        case score
        case name
        case bestDate

        var id: String { rawValue }

        var label: String {
            switch self {
            case .score:
                return L10n.tr("スコア順")
            case .name:
                return L10n.tr("地点名")
            case .bestDate:
                return L10n.tr("最良日順")
            }
        }
    }

    struct SwappedSelection: Equatable, Sendable {
        let removedID: UUID
        let removedName: String
        let addedID: UUID
        let addedName: String
    }

    enum RegistrationOutcome: Equatable, Sendable {
        case alreadyExisted(existingID: UUID)
        case registered(newID: UUID, swap: SwappedSelection?)
    }

    @Published private(set) var availableFavorites: [FavoriteLocation] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var sortKey: SortKey = .score
    let searchController: DashboardSearchController
    @Published var searchText: String = ""
    @Published private(set) var selectionOrder: [UUID] = []
    @Published private(set) var lastSwap: SwappedSelection?
    @Published private(set) var matrix: ComparisonMatrix = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var isInitialLoad = true

    static let maxSelection = 6
    static let dayCount = 7

    private let comparisonController: any ComparisonControlling
    private let favoriteStore: any FavoriteLocationStoring
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var swapResetTask: Task<Void, Never>?
    private struct PendingSwap {
        let id: UUID
        let swap: SwappedSelection
        let resetTask: Task<Void, Never>
    }
    private var pendingSwaps: [PendingSwap] = []
    private var refreshGeneration = 0
    private var didApplyInitialSelection = false

    init(
        comparisonController: some ComparisonControlling,
        favoriteStore: some FavoriteLocationStoring
    ) {
        self.comparisonController = comparisonController
        self.favoriteStore = favoriteStore
        self.searchController = DashboardSearchController()
        self.comparisonController.dayCount = Self.dayCount
        reloadFavorites()
        favoriteStore.locationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] favorites in
                self?.applyFavorites(favorites, triggerRefresh: true)
            }
            .store(in: &cancellables)
    }

    deinit {
        refreshTask?.cancel()
        swapResetTask?.cancel()
        pendingSwaps.forEach { $0.resetTask.cancel() }
    }

    var canSelectMore: Bool { selectedIDs.count < Self.maxSelection }

    func reloadFavorites() {
        applyFavorites(favoriteStore.loadAll(), triggerRefresh: false)
    }

    private func applyFavorites(_ favorites: [FavoriteLocation], triggerRefresh: Bool) {
        availableFavorites = favorites
        let favoriteIDs = Set(favorites.map(\.id))
        selectedIDs.formIntersection(favoriteIDs)

        if !didApplyInitialSelection, selectedIDs.isEmpty {
            selectedIDs = Set(favorites.prefix(Self.maxSelection).map(\.id))
        }

        if !didApplyInitialSelection {
            selectionOrder = favorites.filter { selectedIDs.contains($0.id) }.map(\.id)
        } else {
            selectionOrder.removeAll { !selectedIDs.contains($0) || !favoriteIDs.contains($0) }
            if selectionOrder.isEmpty, !selectedIDs.isEmpty {
                selectionOrder = favorites.filter { selectedIDs.contains($0.id) }.map(\.id)
            }
        }

        didApplyInitialSelection = true

        if selectedIDs.isEmpty {
            refreshTask?.cancel()
            refreshGeneration += 1
            matrix = .empty
            lastError = nil
            isRefreshing = false
        } else if triggerRefresh {
            _ = requestRefresh()
        }
    }

    func refresh(referenceDate: Date = Date()) async {
        let task = requestRefresh(referenceDate: referenceDate)
        await task.value
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            selectionOrder.removeAll { $0 == id }
            return
        }

        guard canSelectMore else { return }
        guard availableFavorites.contains(where: { $0.id == id }) else { return }
        selectedIDs.insert(id)
        selectionOrder.removeAll { $0 == id }
        selectionOrder.append(id)
    }

    func updateSearchText(_ text: String) {
        searchText = text
        searchController.search(query: text)
    }

    func clearSearch() {
        searchText = ""
        searchController.clear()
    }

    func existingFavorite(near mapItem: MKMapItem) -> FavoriteLocation? {
        existingFavorite(near: coordinate(for: mapItem))
    }

    func registerAndSelect(_ mapItem: MKMapItem) -> RegistrationOutcome {
        let details = MapItemLocationDetailsExtractor.details(from: mapItem)
        let name = mapItem.name ?? L10n.tr("現在地")
        return registerAndSelect(
            coordinate: coordinate(for: mapItem),
            name: name,
            timeZoneIdentifier: details.timeZoneIdentifier
        )
    }

    func registerAndSelect(
        coordinate: CLLocationCoordinate2D,
        name: String,
        timeZoneIdentifier: String?
    ) -> RegistrationOutcome {
        if let existing = existingFavorite(near: coordinate) {
            _ = selectFavorite(id: existing.id, name: existing.name, allowSwap: true)
            _ = requestRefresh()
            return .alreadyExisted(existingID: existing.id)
        }

        let favorite = FavoriteLocation(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZoneIdentifier ?? ApproximateTimeZoneResolver.provisionalIdentifier(for: coordinate)
        )
        let swap = selectFavorite(id: favorite.id, name: favorite.name, allowSwap: true)
        favoriteStore.save(availableFavorites + [favorite])
        return .registered(newID: favorite.id, swap: swap)
    }

    func removeFavorite(_ id: UUID) {
        let updated = availableFavorites.filter { $0.id != id }
        guard updated.count != availableFavorites.count else { return }
        favoriteStore.save(updated)
    }

    func undoLastSwap() {
        guard let pending = pendingSwaps.popLast() else { return }
        pending.resetTask.cancel()

        let swap = pending.swap
        guard let removedFavorite = availableFavorites.first(where: { $0.id == swap.removedID }) else {
            lastSwap = pendingSwaps.last?.swap
            return
        }

        selectedIDs.remove(swap.addedID)
        selectionOrder.removeAll { $0 == swap.addedID }

        selectedIDs.insert(removedFavorite.id)
        selectionOrder.removeAll { $0 == removedFavorite.id }
        selectionOrder.insert(removedFavorite.id, at: 0)

        lastSwap = pendingSwaps.last?.swap
        _ = requestRefresh()
    }

    func sortedSelectedLocations() -> [FavoriteLocation] {
        let selectedLocations = availableFavorites.filter { selectedIDs.contains($0.id) }

        switch sortKey {
        case .score:
            return selectedLocations.sorted { lhs, rhs in
                let lhsScore = scoreSum(for: lhs)
                let rhsScore = scoreSum(for: rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        case .name:
            return selectedLocations.sorted {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
        case .bestDate:
            return selectedLocations.sorted { lhs, rhs in
                let lhsDate = bestScoredDate(for: lhs) ?? .distantFuture
                let rhsDate = bestScoredDate(for: rhs) ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        }
    }

    func bestLocationID(for date: Date) -> UUID? {
        guard let matrixDate = matchingMatrixDate(for: date) else { return nil }

        let scoredLocations = matrix.locations.compactMap { location -> (location: FavoriteLocation, score: Int)? in
            guard let score = cell(for: location.id, date: matrixDate)?.index?.score else { return nil }
            return (location: location, score: score)
        }

        guard let highestScore = scoredLocations.map(\.score).max() else { return nil }

        return scoredLocations
            .filter { $0.score == highestScore }
            .sorted {
                $0.location.name.localizedCompare($1.location.name) == .orderedAscending
            }
            .first?
            .location.id
    }

    func cell(for locationID: UUID, date: Date) -> ComparisonCell? {
        guard let matrixDate = matchingMatrixDate(for: date) else { return nil }
        return matrix.cellsByID[ComparisonCell.makeID(locationID: locationID, date: matrixDate)]
    }

    private func scoreSum(for location: FavoriteLocation) -> Int {
        matrix.dates.reduce(0) { partialResult, date in
            partialResult + (cell(for: location.id, date: date)?.index?.score ?? 0)
        }
    }

    private func bestScoredDate(for location: FavoriteLocation) -> Date? {
        var best: (date: Date, score: Int)?

        for date in matrix.dates {
            guard let score = cell(for: location.id, date: date)?.index?.score else { continue }
            if let currentBest = best {
                if score > currentBest.score || (score == currentBest.score && date < currentBest.date) {
                    best = (date, score)
                }
            } else {
                best = (date, score)
            }
        }

        return best?.date
    }

    private func matchingMatrixDate(for date: Date) -> Date? {
        matrix.dates.first { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    private func makeLoadingMatrix(locations: [FavoriteLocation], referenceDate: Date) -> ComparisonMatrix {
        let dates = (0..<Self.dayCount).compactMap { offset in
            Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: offset,
                to: Calendar(identifier: .gregorian).startOfDay(for: referenceDate)
            )
        }
        let cellsByID = Dictionary(uniqueKeysWithValues: locations.flatMap { location in
            dates.map { date in
                let cell = ComparisonCell(locationID: location.id, date: date, loadState: .loading)
                return (cell.id, cell)
            }
        })
        return ComparisonMatrix(locations: locations, dates: dates, cellsByID: cellsByID)
    }

    private func selectFavorite(id: UUID, name: String, allowSwap: Bool) -> SwappedSelection? {
        if selectedIDs.contains(id) {
            selectionOrder.removeAll { $0 == id }
            selectionOrder.append(id)
            return nil
        }

        var swap: SwappedSelection?
        if allowSwap, selectedIDs.count >= Self.maxSelection, let removedFavorite = oldestSelectedFavorite() {
            selectedIDs.remove(removedFavorite.id)
            selectionOrder.removeAll { $0 == removedFavorite.id }
            swap = SwappedSelection(
                removedID: removedFavorite.id,
                removedName: removedFavorite.name,
                addedID: id,
                addedName: name
            )
            setLastSwap(swap!)
        }

        selectedIDs.insert(id)
        selectionOrder.removeAll { $0 == id }
        selectionOrder.append(id)
        return swap
    }

    private func oldestSelectedFavorite() -> FavoriteLocation? {
        if let oldestID = selectionOrder.first,
           let favorite = availableFavorites.first(where: { $0.id == oldestID }) {
            return favorite
        }
        return availableFavorites.first(where: { selectedIDs.contains($0.id) })
    }

    private func setLastSwap(_ swap: SwappedSelection) {
        let id = UUID()
        let resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.removePendingSwap(id: id)
            }
        }
        let pending = PendingSwap(id: id, swap: swap, resetTask: resetTask)
        pendingSwaps.append(pending)
        lastSwap = pendingSwaps.last?.swap
        swapResetTask = resetTask
    }

    private func removePendingSwap(id: UUID) {
        guard let index = pendingSwaps.firstIndex(where: { $0.id == id }) else { return }
        pendingSwaps[index].resetTask.cancel()
        pendingSwaps.remove(at: index)
        lastSwap = pendingSwaps.last?.swap
        if pendingSwaps.isEmpty {
            swapResetTask = nil
        }
    }

    private func requestRefresh(referenceDate: Date = Date()) -> Task<Void, Never> {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        let locations = availableFavorites.filter { selectedIDs.contains($0.id) }
        if locations.isEmpty {
            matrix = .empty
            lastError = nil
            isInitialLoad = false
            isRefreshing = false
            refreshTask = nil
            return Task {}
        }

        isRefreshing = true
        if isInitialLoad {
            matrix = makeLoadingMatrix(locations: locations, referenceDate: referenceDate)
        }

        let task = Task { @MainActor [weak self, locations, referenceDate] in
            guard let self else { return }
            defer {
                if generation == self.refreshGeneration {
                    self.refreshTask = nil
                    self.isRefreshing = false
                }
            }
            let computed = await self.comparisonController.computeMatrix(referenceDate: referenceDate, locations: locations)
            guard generation == self.refreshGeneration, !Task.isCancelled else { return }

            self.matrix = computed
            self.lastError = computed.locations.isEmpty ? L10n.tr("ダッシュボードのデータ取得に失敗しました") : nil
            self.isInitialLoad = false
        }
        refreshTask = task
        return task
    }

    private func existingFavorite(near coordinate: CLLocationCoordinate2D) -> FavoriteLocation? {
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return availableFavorites.first { favorite in
            let favoriteLocation = CLLocation(latitude: favorite.latitude, longitude: favorite.longitude)
            return favoriteLocation.distance(from: targetLocation) <= 100
        }
    }

    private func coordinate(for mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, macOS 26, *) {
            return mapItem.location.coordinate
        } else {
            return mapItem.placemark.coordinate
        }
    }
}
