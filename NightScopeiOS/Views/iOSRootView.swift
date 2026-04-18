import SwiftUI
import UIKit

struct iOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var rootStore: AppRootStore
    @State private var selectedTab = 0
    @State private var hasHandledCurrentActiveState = false

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
        }
        .onAppear {
            handleActiveSceneIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                hasHandledCurrentActiveState = false
                return
            }
            handleActiveSceneIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            guard scenePhase == .active else { return }
            rootStore.appController.handleSceneDidBecomeActive(refreshExternalData: false)
        }
    }

    private func handleActiveSceneIfNeeded() {
        guard scenePhase == .active else { return }
        guard !hasHandledCurrentActiveState else { return }
        hasHandledCurrentActiveState = true
        rootStore.appController.handleSceneDidBecomeActive()
    }
}

#Preview {
    iOSRootView()
}
