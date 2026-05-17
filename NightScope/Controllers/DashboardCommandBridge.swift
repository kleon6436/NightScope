import Foundation
import Combine

/// Dashboard から選択された地点と日付。
struct DashboardSelection: Equatable {
    let location: FavoriteLocation
    let date: Date
}

/// Dashboard の選択イベントを AppController に伝えるブリッジ。
@MainActor
final class DashboardCommandBridge: ObservableObject {
    let selectionPublisher: AnyPublisher<DashboardSelection, Never>
    private let selectionSubject = PassthroughSubject<DashboardSelection, Never>()

    /// Combine 購読先へ流す Subject を初期化する。
    init() {
        self.selectionPublisher = selectionSubject.eraseToAnyPublisher()
    }

    /// Dashboard 側の選択をイベントとして送信する。
    func selectFromDashboard(_ selection: DashboardSelection) {
        selectionSubject.send(selection)
    }
}
