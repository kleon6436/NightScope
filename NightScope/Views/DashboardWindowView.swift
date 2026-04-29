#if os(macOS)
import SwiftUI
import AppKit

/// 複数地点ダッシュボードの macOS ウィンドウ本体。
struct DashboardWindowView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var mapSnapshotCache = MapSnapshotCache()
    @State private var isShowingLocationPicker = false
    @State private var isShowingSearchSheet = false
    @State private var dismissedErrorMessage: String?
    @State private var dismissedSwap: DashboardViewModel.SwappedSelection?
    @AccessibilityFocusState private var isSwapUndoFocused: Bool
    @ScaledMetric(relativeTo: .body) private var adaptiveGridMinimumWidth: CGFloat = 360

    let dependencies: DashboardSceneDependencies

    init(dependencies: DashboardSceneDependencies) {
        self.dependencies = dependencies
        let dashboardComparisonController = ComparisonController(
            favoriteStore: dependencies.appController.favoriteStore,
            weatherService: dependencies.appController.weatherService,
            lightPollutionService: dependencies.appController.lightPollutionService,
            calculationService: dependencies.appController.calculationService
        )
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
                comparisonController: dashboardComparisonController,
                favoriteStore: dependencies.appController.favoriteStore
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    swapBanner
                    errorBanner

                    stateContent
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
                .padding([.horizontal, .bottom], Spacing.md)
        }
        .frame(minWidth: 880, minHeight: 600)
        .navigationTitle(L10n.tr("複数地点ダッシュボード"))
        .onAppear {
            Task {
                await viewModel.refresh()
            }
        }
        .onChange(of: viewModel.lastError) { _, newValue in
            if newValue == nil {
                dismissedErrorMessage = nil
            }
        }
        .onChange(of: viewModel.lastSwap) { _, newValue in
            if newValue == nil {
                dismissedSwap = nil
                isSwapUndoFocused = false
            } else {
                dismissedSwap = nil
                isSwapUndoFocused = true
            }
        }
        .sheet(isPresented: $isShowingLocationPicker, onDismiss: {
            Task { await viewModel.refresh() }
        }) {
            DashboardLocationPickerSheet(
                viewModel: viewModel,
                isPresented: $isShowingLocationPicker
            )
        }
        .sheet(isPresented: $isShowingSearchSheet, onDismiss: {
            viewModel.clearSearch()
        }) {
            DashboardSearchSheet(viewModel: viewModel)
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(L10n.tr("並び順"))
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.sortKey },
                set: { newValue in
                    DispatchQueue.main.async {
                        viewModel.sortKey = newValue
                    }
                }
            )) {
                ForEach(DashboardViewModel.SortKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer(minLength: Spacing.md)

            Button {
                isShowingSearchSheet = true
            } label: {
                Label(L10n.tr("地点を検索"), systemImage: "magnifyingglass")
            }

            Button {
                isShowingLocationPicker = true
            } label: {
                Label(
                    L10n.format(
                        "地点を選択 (%d/%d)",
                        viewModel.selectedIDs.count,
                        DashboardViewModel.maxSelection
                    ),
                    systemImage: "checklist"
                )
            }
            .disabled(viewModel.availableFavorites.isEmpty)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(L10n.tr("データを更新"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isRefreshing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.availableFavorites.isEmpty {
            ContentUnavailableView(
                L10n.tr("お気に入り地点がありません"),
                systemImage: "star",
                description: Text(L10n.tr("メインウィンドウのサイドバーから追加してください"))
            )
        } else if viewModel.selectedIDs.isEmpty {
            ContentUnavailableView {
                Text(L10n.tr("地点が選択されていません"))
            } description: {
                Text(L10n.tr("地点を選択して比較します"))
            } actions: {
                Button(L10n.tr("地点を選択")) {
                    isShowingLocationPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: adaptiveGridMinimumWidth), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(viewModel.sortedSelectedLocations()) { location in
                    let isSkeleton = viewModel.isInitialLoad && viewModel.isRefreshing
                    DashboardLocationCard(
                        viewModel: viewModel,
                        location: location,
                        dates: viewModel.matrix.dates,
                        mapSnapshotCache: mapSnapshotCache,
                        onSelect: handleCellSelection(locationID:date:),
                        onDelete: { viewModel.removeFavorite($0) }
                    )
                    .redacted(reason: isSkeleton ? .placeholder : [])
                    .allowsHitTesting(!isSkeleton)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            WeatherAttributionBadge()
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.lastError, error != dismissedErrorMessage {
            DashboardErrorBanner(
                message: error,
                onRetry: {
                    dismissedErrorMessage = nil
                    Task { await viewModel.refresh() }
                },
                onDismiss: {
                    dismissedErrorMessage = error
                }
            )
        }
    }

    @ViewBuilder
    private var swapBanner: some View {
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
                .accessibilityFocused($isSwapUndoFocused)

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
            .accessibilityLabel(
                L10n.format("%@ を外して %@ を追加しました", swap.removedName, swap.addedName)
            )
        }
    }

    private func handleCellSelection(locationID: UUID, date: Date) {
        guard let location = viewModel.matrix.locations.first(where: { $0.id == locationID }) else { return }
        dependencies.dashboardCommandBridge.selectFromDashboard(
            DashboardSelection(location: location, date: date)
        )
    }
}

private struct DashboardErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Status.warning)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .lineLimit(2)
            Spacer()
            Button(L10n.tr("再試行"), action: onRetry)
                .buttonStyle(.borderedProminent)
            Button(L10n.tr("閉じる"), action: onDismiss)
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
}

#endif
