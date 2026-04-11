import SwiftUI

struct ContentView: View {
    @StateObject private var appController: AppController
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var detailViewModel: DetailViewModel
    @StateObject private var starMapViewModel: StarMapViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @MainActor
    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        _appController = StateObject(wrappedValue: dependencies.appController)
        _sidebarViewModel = StateObject(wrappedValue: dependencies.sidebarViewModel)
        _detailViewModel = StateObject(wrappedValue: dependencies.detailViewModel)
        _starMapViewModel = StateObject(wrappedValue: dependencies.starMapViewModel)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: sidebarViewModel,
                selectedDate: $detailViewModel.selectedDate,
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
        .focusedValue(\.selectedDate, $detailViewModel.selectedDate)
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
