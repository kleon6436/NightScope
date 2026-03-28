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
                DispatchQueue.main.async {
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
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
