import SwiftUI

struct iOSRootView: View {
    @StateObject private var rootStore: AppRootStore
    @State private var selectedTab = 0

    @MainActor
    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        _rootStore = StateObject(wrappedValue: AppRootStore(dependencies: dependencies))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            iOSTodayView(detailViewModel: rootStore.detailViewModel)
                .tabItem {
                    Label("空模様", systemImage: "moon.stars")
                }
                .tag(0)

            iOSForecastView(detailViewModel: rootStore.detailViewModel, selectedTab: $selectedTab)
                .tabItem {
                    Label("予報", systemImage: "calendar")
                }
                .tag(1)

            iOSLocationView(sidebarViewModel: rootStore.sidebarViewModel)
                .tabItem {
                    Label("場所", systemImage: "mappin.circle")
                }
                .tag(2)

            iOSStarMapView(viewModel: rootStore.starMapViewModel)
                .tabItem {
                    Label("星空", systemImage: "sparkles")
                }
                .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
                .tag(4)
        }
        .onAppear {
            rootStore.appController.onStart()
        }
    }
}

#Preview {
    iOSRootView()
}
