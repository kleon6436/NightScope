import SwiftUI

struct ContentView: View {
    @StateObject private var appController = AppController()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                locationController: appController.locationController,
                lightPollutionService: appController.lightPollutionService,
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
            DetailView(appController: appController)
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
            appController.onStart()
        }
        .onChange(of: appController.selectedDate) {
            appController.recalculate()
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
