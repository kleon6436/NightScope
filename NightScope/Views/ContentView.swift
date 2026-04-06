import SwiftUI

struct ContentView: View {
    @ObservedObject private var appController: AppController
    @StateObject private var terminationCoordinator = AppTerminationCoordinator.shared
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var detailViewModel: DetailViewModel
    @StateObject private var assistantViewModel: AssistantViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(appController: AppController) {
        self.appController = appController
        _sidebarViewModel = StateObject(
            wrappedValue: SidebarViewModel(
                locationController: appController.locationController,
                lightPollutionService: appController.lightPollutionService
            )
        )
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(appController: appController))
        _assistantViewModel = StateObject(
            wrappedValue: AssistantViewModel(
                llmService: appController.llmService,
                appController: appController
            )
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: sidebarViewModel,
                selectedDate: $appController.selectedDate
            )
            .navigationSplitViewColumnWidth(
                min: Layout.sidebarMinWidth,
                ideal: Layout.sidebarIdealWidth,
                max: Layout.sidebarMaxWidth
            )
            .navigationTitle("NightScope")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear.frame(width: 1)
                }
            }
        } detail: {
            DetailView(viewModel: detailViewModel, assistantViewModel: assistantViewModel)
        }
        .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: columnVisibility) {
            if columnVisibility != .all {
                Task { @MainActor in
                    columnVisibility = .all
                }
            }
        }
        .onAppear {
            Task { @MainActor in appController.onStart() }
        }
        .onChange(of: appController.selectedDate) {
            Task { @MainActor in appController.recalculate() }
        }
        .focusedValue(\.selectedDate, $appController.selectedDate)
        .focusedValue(\.refreshAction, {
            Task {
                await appController.refreshWeather()
                await appController.refreshLightPollution()
            }
        })
        .focusedValue(\.focusSearchAction, {
            appController.locationController.searchFocusTrigger += 1
        })
        .focusedValue(\.currentLocationAction, {
            appController.locationController.requestCurrentLocation()
        })
        .overlay {
            if terminationCoordinator.isPreparingForTermination {
                terminationOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: terminationCoordinator.isPreparingForTermination)
    }

    private var terminationOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .progressViewStyle(.circular)

                Text("推論を安全に停止しています…")
                    .font(.headline)

                Text("完了後にアプリを終了します")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
        }
        .transition(.opacity)
    }
}

#Preview {
    ContentView(appController: AppController())
        .frame(width: 900, height: 700)
}
