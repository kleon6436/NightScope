import SwiftUI
import Combine

@MainActor
final class StarGazingIndexCardViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var fetchFailed: Bool = false

    private weak var lightPollutionService: LightPollutionService?
    private var cancellables = Set<AnyCancellable>()

    init(lightPollutionService: LightPollutionService) {
        self.lightPollutionService = lightPollutionService
        setupBindings()
    }

    private func setupBindings() {
        lightPollutionService?.$isLoading
            .assign(to: &$isLoading)

        lightPollutionService?.$fetchFailed
            .assign(to: &$fetchFailed)
    }
}
