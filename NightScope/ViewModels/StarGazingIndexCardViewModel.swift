import SwiftUI
import Combine

@MainActor
final class StarGazingIndexCardViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var fetchFailed: Bool = false

    init(
        isLoading: Bool,
        fetchFailed: Bool,
        isLoadingPublisher: AnyPublisher<Bool, Never>,
        fetchFailedPublisher: AnyPublisher<Bool, Never>
    ) {
        self.isLoading = isLoading
        self.fetchFailed = fetchFailed
        isLoadingPublisher
            .assign(to: &$isLoading)

        fetchFailedPublisher
            .assign(to: &$fetchFailed)
    }
}
