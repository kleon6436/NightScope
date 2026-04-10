import SwiftUI

struct ContentView: View {
    @StateObject private var appController: AppController
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var detailViewModel: DetailViewModel
    @StateObject private var starMapViewModel: StarMapViewModel
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
        _starMapViewModel = StateObject(wrappedValue: StarMapViewModel(appController: appController))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: sidebarViewModel,
                selectedDate: $appController.selectedDate,
                viewingDirection: starMapViewModel.viewingDirection
            )
            .navigationSplitViewColumnWidth(
                min: LayoutMacOS.sidebarMinWidth,
                ideal: LayoutMacOS.sidebarIdealWidth,
                max: LayoutMacOS.sidebarMaxWidth
            )
            .navigationTitle("NightScope")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear.frame(width: 1)
                }
            }
        } detail: {
            DetailView(viewModel: detailViewModel, starMapViewModel: starMapViewModel)
        }
        .frame(minWidth: LayoutMacOS.windowMinWidth, minHeight: LayoutMacOS.windowMinHeight)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: columnVisibility) {
            if columnVisibility != .all {
                columnVisibility = .all
            }
        }
        .onAppear {
            appController.onStart()
        }
        .onChange(of: appController.selectedDate) {
            appController.recalculate()
        }
        .focusedValue(\.selectedDate, $appController.selectedDate)
        .focusedValue(\.refreshAction, {
            appController.refreshExternalDataInBackground()
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
