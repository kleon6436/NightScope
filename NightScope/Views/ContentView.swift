import SwiftUI

struct ContentView: View {
    @StateObject private var rootStore: AppRootStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @MainActor
    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        _rootStore = StateObject(wrappedValue: AppRootStore(dependencies: dependencies))
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { rootStore.selectedDate },
            set: { rootStore.detailViewModel.selectedDate = $0 }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: rootStore.sidebarViewModel,
                selectedDate: selectedDateBinding,
                starMapViewModel: rootStore.starMapViewModel
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
            DetailView(
                viewModel: rootStore.detailViewModel,
                starMapViewModel: rootStore.starMapViewModel,
                observationModePreference: rootStore.observationModePreference
            )
        }
        .frame(minWidth: LayoutMacOS.windowMinWidth, minHeight: LayoutMacOS.windowMinHeight)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: columnVisibility) {
            if columnVisibility != .all {
                columnVisibility = .all
            }
        }
        .onAppear {
            rootStore.appController.onStart()
        }
        .focusedValue(\.selectedDate, selectedDateBinding)
        .focusedValue(\.observationTimeZone, rootStore.detailViewModel.selectedTimeZone)
        .focusedValue(\.refreshAction, {
            rootStore.appController.refreshExternalDataInBackground()
        })
        .focusedValue(\.focusSearchAction, {
            rootStore.appController.locationController.searchFocusTrigger += 1
        })
        .focusedValue(\.currentLocationAction, {
            rootStore.appController.locationController.requestCurrentLocation()
        })
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
