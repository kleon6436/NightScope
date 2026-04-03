import SwiftUI

struct ContentView: View {
    @StateObject private var appController: AppController
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var detailViewModel: DetailViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        let appController = AppController()
        _appController = StateObject(wrappedValue: appController)
        _sidebarViewModel = StateObject(
            wrappedValue: SidebarViewModel(
                locationController: appController.locationController,
                lightPollutionService: appController.lightPollutionService
            )
        )
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(appController: appController))
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
            DetailView(viewModel: detailViewModel)
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
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
