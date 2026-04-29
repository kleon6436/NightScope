import SwiftUI
import Combine

/// 光害取得状態を星空指数カードへ伝える ViewModel。
@MainActor
final class StarGazingIndexCardViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var fetchFailed: Bool = false

    private let lightPollutionService: LightPollutionService
    private var cancellables = Set<AnyCancellable>()

    init(lightPollutionService: LightPollutionService) {
        self.lightPollutionService = lightPollutionService
        setupBindings()
    }

    /// 光害サービスの状態をそのままカードの表示状態へ反映する。
    private func setupBindings() {
        lightPollutionService.$isLoading
            .assign(to: &$isLoading)

        lightPollutionService.$fetchFailed
            .assign(to: &$fetchFailed)
    }
}
