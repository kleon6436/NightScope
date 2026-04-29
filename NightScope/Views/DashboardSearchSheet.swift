#if os(macOS)
import SwiftUI
import MapKit
import AppKit

struct DashboardSearchSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var searchController: DashboardSearchController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFieldFocused: Bool
    @State private var dismissedSwap: DashboardViewModel.SwappedSelection?

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _searchController = ObservedObject(wrappedValue: viewModel.searchController)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            searchBar
            inlineSwapBanner
            content
        }
        .padding(Spacing.md)
        .frame(minWidth: 480, minHeight: 480, idealHeight: 600)
        .onAppear {
            searchFieldFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(L10n.tr("地点を検索"))
                .font(.title2.bold())

            Spacer(minLength: 0)

            Button(L10n.tr("閉じる")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
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
    private var inlineSwapBanner: some View {
        if let swap = viewModel.lastSwap, swap != dismissedSwap {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text(L10n.format("%@ を外して %@ を追加しました", swap.removedName, swap.addedName))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Button(L10n.tr("元に戻す")) {
                    viewModel.undoLastSwap()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismissedSwap = swap
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("閉じる"))
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.format("%@ を外して %@ を追加しました", swap.removedName, swap.addedName))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch searchController.state.phase {
        case .idle:
            ContentUnavailableView(
                L10n.tr("地名を入力してください"),
                systemImage: "magnifyingglass"
            )

        case .loading:
            if searchController.state.results.isEmpty {
                loadingEmptyState
            } else {
                resultsList(isLoading: true)
            }

        case .empty:
            ContentUnavailableView(
                L10n.tr("一致する地点が見つかりません"),
                systemImage: "mappin.slash",
                description: Text(viewModel.searchText)
            )

        case .failure:
            DashboardSearchFailureView(
                message: searchController.state.errorMessage ?? L10n.tr("検索に失敗しました"),
                onRetry: {
                    viewModel.updateSearchText(viewModel.searchText)
                }
            )

        case .results:
            resultsList(isLoading: false)
        }
    }

    private var loadingEmptyState: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.tr("検索中…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultsList(isLoading: Bool) -> some View {
        List {
            ForEach(Array(searchController.state.results.enumerated()), id: \.offset) { _, mapItem in
                DashboardSearchResultRow(
                    viewModel: viewModel,
                    mapItem: mapItem
                )
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.inset)
        .overlay(alignment: .topLeading) {
            if isLoading {
                loadingStrip
                    .padding(.top, 6)
                    .padding(.leading, 12)
            }
        }
    }

    private var loadingStrip: some View {
        HStack(spacing: Spacing.xs) {
            ProgressView()
                .controlSize(.mini)
            Text(L10n.tr("検索中…"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
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

private struct DashboardSearchFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.tr("検索に失敗しました"), systemImage: AppIcons.Status.warning)
        } description: {
            Text(message)
        } actions: {
            Button(L10n.tr("再試行"), action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
#endif
