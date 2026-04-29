import Combine
import Foundation

/// Dashboard 上の地点検索入力を遅延実行付きで管理する。
@MainActor
final class DashboardSearchController: ObservableObject {
    @Published private(set) var state: LocationSearchState = .idle

    private let searchService: any LocationSearchServicing
    private var searchTask: Task<Void, Never>?
    private var latestQuery: String = ""

    /// 検索サービスを注入する。
    init(searchService: any LocationSearchServicing = MKLocationSearchService()) {
        self.searchService = searchService
    }

    /// クエリを正規化し、短時間の連続入力をまとめて検索する。
    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            clear()
            return
        }

        let isSameAsLatestQuery = normalizedQuery == latestQuery
        if isSameAsLatestQuery, (state.isSearching || state.phase == .results) {
            return
        }

        latestQuery = normalizedQuery
        searchTask?.cancel()
        state = .loading(query: normalizedQuery, previousResults: state.results)

        searchTask = Task { [normalizedQuery] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            do {
                let mapItems = try await searchService.search(query: normalizedQuery)
                guard !Task.isCancelled else { return }
                guard latestQuery == normalizedQuery else { return }
                state = mapItems.isEmpty
                    ? .empty(query: normalizedQuery)
                    : .results(query: normalizedQuery, items: mapItems)
            } catch {
                guard !Task.isCancelled else { return }
                guard latestQuery == normalizedQuery else { return }
                state = .failure(
                    query: normalizedQuery,
                    errorMessage: L10n.tr("場所を検索できませんでした。通信状況を確認して、もう一度お試しください。")
                )
            }
        }
    }

    /// 検索状態と進行中タスクを破棄する。
    func clear() {
        searchTask?.cancel()
        searchTask = nil
        latestQuery = ""
        state = .idle
    }

    deinit {
        searchTask?.cancel()
    }
}
