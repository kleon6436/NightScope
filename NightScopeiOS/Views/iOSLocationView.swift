import SwiftUI
import MapKit
import UIKit

/// 場所検索、現在地取得、地図選択、お気に入り管理をまとめた画面。
struct iOSLocationView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var sidebarViewModel: SidebarViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var locationInputMode: LocationInputMode = .map

    private var showLightPollution: Bool {
        // モード切り替えでも同じ地図を使うため、表示の差分だけをここで判定する。
        locationInputMode == .lightPollutionMap
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        headerSection
                        searchSection
                        searchResultsList
                        mapArea
                        bottomBar
                        iOSFavoritesSection(
                            viewModel: sidebarViewModel,
                            onSelect: selectFavorite
                        )
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                }
                .scrollDismissesKeyboard(.interactively)
                .toolbarBackground(.hidden, for: .navigationBar)
                .alert(
                    "位置情報エラー",
                    isPresented: locationErrorAlertBinding,
                    presenting: sidebarViewModel.locationError
                ) { error in
                    if error == .denied {
                        Button("設定を開く", action: openAppSettings)
                    }
                    Button("OK") {
                        sidebarViewModel.clearLocationError()
                    }
                } message: { error in
                    Text(error.localizedDescription)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            sidebarViewModel.refreshLocationAuthorizationState()
        }
    }

    private var headerSection: some View {
        iOSTabHeaderView(
            title: "場所",
            horizontalPadding: Spacing.xs
        ) {
            Text("場所を検索")
                .font(.subheadline)
                .lineLimit(1)
        } trailing: {
            Button {
                isSearchFocused = false
                sidebarViewModel.requestCurrentLocation()
            } label: {
                Group {
                    if sidebarViewModel.isLocating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.headline)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .glassButtonStyle()
            .disabled(sidebarViewModel.isLocating)
            .accessibilityLabel(L10n.tr("現在地を取得"))
            .accessibilityHint(L10n.tr("地図を現在地へ移動します"))
        }
    }

    private var searchSection: some View {
        LocationSearchField(
            searchText: searchTextBinding,
            isSearching: sidebarViewModel.isSearching,
            isSearchFocused: $isSearchFocused,
            onClear: {
                clearSearchInteraction()
            }
        )
        .onChange(of: sidebarViewModel.searchFocusTrigger) {
            isSearchFocused = true
        }
    }

    // MARK: - 検索結果

    private var searchResultsList: some View {
        iOSLocationSearchResultsSection(
            presentation: sidebarViewModel.searchPresentation,
            searchResultsContent: searchResultsCard,
            onRetry: sidebarViewModel.retrySearch
        )
    }

    private func searchResultsCard(_ results: [MKMapItem]) -> some View {
        Group {
            if SearchResultsLayout.needsScroll(
                resultCount: results.count,
                visibleRowCapacity: IOSDesignTokens.Location.searchResultsVisibleRowCapacity
            ) {
                ScrollView {
                    searchResultsContent(results)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: IOSDesignTokens.Location.searchResultsMaxHeight)
            } else {
                searchResultsContent(results)
            }
        }
        .iOSMaterialPanel()
    }

    private func searchResultsContent(_ results: [MKMapItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                searchResultRow(item)
                if index < results.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func searchResultRow(_ item: MKMapItem) -> some View {
        Button {
            selectSearchResult(item)
        } label: {
            LocationSearchResultContent(
                item: item,
                titleFont: .body,
                subtitleFont: .caption,
                lineSpacing: IOSDesignTokens.Location.searchResultLineSpacing,
                titleFallback: L10n.tr("不明な場所"),
                iconWidth: 18
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.format("場所を選択: %@", item.name ?? L10n.tr("不明"))
        )
    }

    // MARK: - 地図

    private var mapArea: some View {
        ZStack(alignment: .bottomTrailing) {
            iOSMapView(
                pinCoordinate: sidebarViewModel.selectedCoordinate,
                onTap: handleMapTap,
                syncState: mapSyncState,
                onRegionChange: { center, span in
                    sidebarViewModel.updateViewportIfNeeded(center: center, span: span)
                },
                showLightPollution: showLightPollution,
                centerTrigger: sidebarViewModel.currentLocationCenterTrigger
            )
            .ignoresSafeArea(edges: .horizontal)
        }
        .frame(minHeight: mapAreaMinHeight, maxHeight: .infinity)
        .layoutPriority(1)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }

    private var mapSyncState: MapKitSyncState {
        // 地図と光害オーバーレイは同じ MKMapView を再利用するので、
        // モード切り替えで古い viewport を押し戻さない。
        MapKitSyncState(
            trigger: 0,
            center: sidebarViewModel.viewport.center,
            span: sidebarViewModel.viewport.span
        )
    }

    // MARK: - 下部バー

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            Picker("地図表示モード", selection: $locationInputMode) {
                Text("地図").tag(LocationInputMode.map)
                Text("光害").tag(LocationInputMode.lightPollutionMap)
            }
            .pickerStyle(.segmented)

            infoRow
        }
        .padding(Spacing.sm)
        .iOSMaterialPanel()
        .padding(.bottom, Spacing.sm)
    }

    private var infoRow: some View {
        HStack(spacing: Spacing.xs) {
            SelectedLocationSummaryContent(
                locationName: sidebarViewModel.selectedLocationName.isEmpty
                    ? L10n.tr("場所が選択されていません")
                    : sidebarViewModel.selectedLocationName,
                coordinate: sidebarViewModel.selectedCoordinate,
                titleFont: .caption,
                coordinateFont: .caption,
                showsAccentIcon: false
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer()
            Button {
                sidebarViewModel.toggleCurrentLocationFavorite()
            } label: {
                Image(
                    systemName: sidebarViewModel.isCurrentLocationFavorited
                        ? "star.fill" : "star"
                )
                .foregroundStyle(
                    sidebarViewModel.isCurrentLocationFavorited ? .yellow : .secondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                sidebarViewModel.isCurrentLocationFavorited ? L10n.tr("お気に入りから削除") : L10n.tr("お気に入りに追加")
            )
            if showLightPollution {
                if sidebarViewModel.isLightPollutionLoading {
                    ProgressView().controlSize(.mini)
                } else if let bortle = sidebarViewModel.lightPollutionBortleClass {
                    Text(L10n.format("ボルトル%d級", Int(bortle.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if sidebarViewModel.hasLightPollutionFetchFailed {
                    Button("再試行") {
                        sidebarViewModel.retryLightPollution()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var locationErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { sidebarViewModel.locationError != nil },
            set: { isPresented in
                if !isPresented {
                    sidebarViewModel.clearLocationError()
                }
            }
        )
    }

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        isSearchFocused = false
        sidebarViewModel.selectCoordinate(coordinate)
    }

    private func clearSearchInteraction() {
        sidebarViewModel.clearSearch()
    }

    private func selectSearchResult(_ item: MKMapItem) {
        sidebarViewModel.selectSearchResult(item, searchTextBehavior: .clear)
        isSearchFocused = false
    }

    private func selectFavorite(_ favorite: FavoriteLocation) {
        sidebarViewModel.selectFavorite(favorite)
        isSearchFocused = false
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        sidebarViewModel.prepareForLocationSettingsRecovery()
        openURL(settingsURL)
    }

    private var usesCompactMapLayout: Bool {
        isSearchFocused || isShowingSearchPresentation
    }

    private var isShowingSearchPresentation: Bool {
        if case .hidden = sidebarViewModel.searchPresentation {
            return false
        }
        return true
    }

    private var mapAreaMinHeight: CGFloat {
        // 検索中や検索結果表示中は地図を少し縮めて、入力領域を優先する。
        usesCompactMapLayout
            ? IOSDesignTokens.Location.compactMapHeight
            : IOSDesignTokens.Location.defaultMapHeight
    }
}

/// 検索結果の表示状態ごとに View を切り替える。
private struct iOSLocationSearchResultsSection<ResultsContent: View>: View {
    let presentation: SidebarViewModel.SearchPresentation
    let searchResultsContent: ([MKMapItem]) -> ResultsContent
    let onRetry: () -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .loading(let previousResults):
            if previousResults.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("検索中…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .iOSMaterialPanel()
            } else {
                searchResultsContent(previousResults)
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(Spacing.xs)
                    }
                    .opacity(0.75)
            }
        case .results(let results):
            searchResultsContent(results)
        case .empty(let query):
            ContentUnavailableView.search(text: query)
                .padding(.vertical, Spacing.xs)
        case .error(let query, let message):
            ContentUnavailableView {
                Label("場所を検索できませんでした", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text(L10n.format("\"%@\" の検索に失敗しました。%@", query, message))
            } actions: {
                Button("再試行", action: onRetry)
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// 検索バーの入力・クリア操作をまとめる。
private struct LocationSearchField: View {
    @Binding var searchText: String
    let isSearching: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("場所を検索", text: $searchText)
                .textFieldStyle(.plain)
                .focused(isSearchFocused)
                .accessibilityLabel(L10n.tr("場所を検索"))

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, Spacing.xs)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("検索語を消去"))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .iOSMaterialPanel()
    }
}

/// お気に入り一覧を表示する。
private struct iOSFavoritesSection: View {
    @ObservedObject var viewModel: SidebarViewModel
    let onSelect: (FavoriteLocation) -> Void

    private var needsScroll: Bool {
        // 表示件数が多いときだけ ScrollView を有効にして、短い一覧の高さを無駄に伸ばさない。
        viewModel.favorites.count > IOSDesignTokens.Location.favoritesVisibleCount
    }

    private var favoritesListHeight: CGFloat {
        // 高さを固定して、行数変化で下部バー全体が大きく揺れないようにする。
        let rowHeight = IOSDesignTokens.Location.estimatedFavoriteRowHeight
        let contentHeight = CGFloat(viewModel.favorites.count) * rowHeight
        return min(contentHeight, IOSDesignTokens.Location.favoritesMaxHeight)
    }

    var body: some View {
        if !viewModel.favorites.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("お気に入り", systemImage: "star.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.favorites) { favorite in
                            Button { onSelect(favorite) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(favorite.name)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(
                                            L10n.format(
                                                "%.4f, %.4f",
                                                favorite.latitude,
                                                favorite.longitude
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                L10n.format("お気に入りの場所: %@", favorite.name)
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.removeFavorite(favorite)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }

                            if favorite.id != viewModel.favorites.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .scrollDisabled(!needsScroll)
                .frame(height: favoritesListHeight)
                .iOSMaterialPanel()
            }
            .padding(.bottom, Spacing.sm)
        }
    }
}

#Preview("Location - Loading") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .loading))
}

#Preview("Location - Empty") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .empty))
}

#Preview("Location - Content") {
    iOSLocationView(sidebarViewModel: IOSPreviewFactory.sidebarViewModel(for: .content))
}

private extension iOSLocationView {
    // 検索語の更新と search presentation の同期をまとめる。
    var searchTextBinding: Binding<String> {
        Binding(
            get: { sidebarViewModel.searchText },
            set: { sidebarViewModel.updateSearchText($0) }
        )
    }
}
