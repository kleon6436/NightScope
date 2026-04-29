#if os(macOS)
import SwiftUI
import MapKit
import AppKit

/// 複数地点ダッシュボードのヘッダー直下に表示するインライン検索セクション。
struct DashboardSearchSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var searchController: DashboardSearchController

    @FocusState private var searchFieldFocused: Bool

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _searchController = ObservedObject(wrappedValue: viewModel.searchController)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            searchBar
            if shouldShowContent {
                content
            }
        }
    }

    private var shouldShowContent: Bool {
        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return searchController.state.phase != .idle
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                L10n.tr("地名検索"),
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                )
            )
            .textFieldStyle(.plain)
            .focused($searchFieldFocused)
            .accessibilityLabel(L10n.tr("地名検索"))
            .onSubmit(handleSubmit)
            .onChange(of: viewModel.searchText) { _, newValue in
                viewModel.updateSearchText(newValue)
            }

            if searchController.state.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.tr("検索中…"))
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.tr("検索語を消去"))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch searchController.state.phase {
        case .idle:
            EmptyView()

        case .loading:
            if searchController.state.results.isEmpty {
                statusMessageView(L10n.tr("検索中…"))
            } else {
                resultsList()
            }

        case .empty:
            statusMessageView(L10n.tr("一致する地点が見つかりません"))

        case .failure:
            failureView(message: searchController.state.errorMessage ?? L10n.tr("検索に失敗しました"))

        case .results:
            resultsList()
        }
    }

    private func statusMessageView(_ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func failureView(message: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Status.warning)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(L10n.tr("再試行")) {
                viewModel.updateSearchText(viewModel.searchText)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityLabel(L10n.format("エラー: %@", message))
    }

    private static let resultRowEstimatedHeight: CGFloat = 64
    private static let maxVisibleResultRows: CGFloat = 4

    private func resultsList() -> some View {
        let items = Array(searchController.state.results.enumerated())
        let visibleCount = min(CGFloat(items.count), Self.maxVisibleResultRows)
        let maxHeight = max(Self.resultRowEstimatedHeight, visibleCount * Self.resultRowEstimatedHeight)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.offset) { index, mapItem in
                    DashboardSearchResultRow(
                        viewModel: viewModel,
                        mapItem: mapItem
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)

                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: maxHeight)
        .scrollBounceBehavior(.basedOnSize)
        .background(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func handleSubmit() {
        if let mapItem = searchController.state.results.first {
            _ = viewModel.registerAndSelect(mapItem)
        } else {
            viewModel.updateSearchText(viewModel.searchText)
        }
    }
}

/// 検索結果の 1 行を、登録状態に応じて分岐表示する。
private struct DashboardSearchResultRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let mapItem: MKMapItem

    private var existingFavorite: FavoriteLocation? {
        viewModel.existingFavorite(near: mapItem)
    }

    private var isSelected: Bool {
        guard let existingFavorite else { return false }
        return viewModel.selectedIDs.contains(existingFavorite.id)
    }

    private var subtitleText: String {
        if #available(iOS 26, macOS 26, *),
           let address = mapItem.address {
            let subtitle = address.shortAddress ?? address.fullAddress.nilIfEmpty
            if let subtitle, !subtitle.isEmpty {
                return subtitle
            }
        }

        let placemark = mapItem.placemark
        let parts = [
            placemark.title,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { $0?.nilIfEmpty }

        return parts.joined(separator: ", ")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rowContent(isCompact: false)
            rowContent(isCompact: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private func rowContent(isCompact: Bool) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                leadingContent
                trailingState
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.sm) {
                leadingContent
                Spacer(minLength: 0)
                trailingState
            }
        }
    }

    private var leadingContent: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(mapItem.name ?? L10n.tr("現在地"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
    }

    private var accessibilityLabel: String {
        let name = mapItem.name ?? L10n.tr("現在地")
        if existingFavorite != nil {
            return isSelected
                ? "\(name)、\(L10n.tr("選択中"))"
                : "\(name)、\(L10n.tr("登録済み"))"
        }
        return "\(name)、\(L10n.tr("+ 登録"))"
    }

    private var accessibilityValue: String {
        if let subtitle = subtitleText.nilIfEmpty {
            return subtitle
        }
        return existingFavorite != nil
            ? (isSelected ? L10n.tr("既にお気に入りに登録されています") : L10n.tr("リストに追加"))
            : L10n.tr("リストに追加")
    }

    @ViewBuilder
    private var trailingState: some View {
        if existingFavorite != nil {
            if isSelected {
                Label(L10n.tr("選択中"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(L10n.tr("選択中"))
                    .accessibilityHint(L10n.tr("既にお気に入りに登録されています"))
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Label {
                        Text(L10n.tr("登録済み"))
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.24))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    )
                    .accessibilityLabel(L10n.tr("既にお気に入りに登録されています"))

                    Button {
                        _ = viewModel.registerAndSelect(mapItem)
                    } label: {
                        Label(L10n.tr("リストに追加"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(L10n.tr("お気に入りに追加してリストに加えます"))
                }
            }
        } else {
            Button {
                _ = viewModel.registerAndSelect(mapItem)
            } label: {
                Label(L10n.tr("+ 登録"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(L10n.tr("お気に入りに追加してリストに加えます"))
        }
    }
}
#endif
