import Foundation
import Combine

struct DashboardSelection: Equatable {
    let location: FavoriteLocation
    let date: Date
}

@MainActor
final class DashboardCommandBridge: ObservableObject {
    let selectionPublisher: AnyPublisher<DashboardSelection, Never>
    private let selectionSubject = PassthroughSubject<DashboardSelection, Never>()

    init() {
        self.selectionPublisher = selectionSubject.eraseToAnyPublisher()
    }

    func selectFromDashboard(_ selection: DashboardSelection) {
        selectionSubject.send(selection)
    }
}
