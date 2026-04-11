import SwiftUI

struct iOSRootView: View {
    @StateObject private var appController: AppController
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var detailViewModel: DetailViewModel
    @StateObject private var starMapViewModel: StarMapViewModel
    @State private var selectedTab = 0

    @MainActor
    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        _appController = StateObject(wrappedValue: dependencies.appController)
        _sidebarViewModel = StateObject(wrappedValue: dependencies.sidebarViewModel)
        _detailViewModel = StateObject(wrappedValue: dependencies.detailViewModel)
        _starMapViewModel = StateObject(wrappedValue: dependencies.starMapViewModel)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            iOSTodayView(detailViewModel: detailViewModel)
                .tabItem {
                    Label("空模様", systemImage: "moon.stars")
                }
                .tag(0)

            iOSForecastView(detailViewModel: detailViewModel, selectedTab: $selectedTab)
                .tabItem {
                    Label("予報", systemImage: "calendar")
                }
                .tag(1)

            iOSLocationView(sidebarViewModel: sidebarViewModel)
                .tabItem {
                    Label("場所", systemImage: "mappin.circle")
                }
                .tag(2)

            iOSStarMapView(viewModel: starMapViewModel)
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
            appController.onStart()
        }
    }
}

#Preview {
    iOSRootView()
}
