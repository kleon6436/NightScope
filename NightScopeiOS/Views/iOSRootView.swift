import SwiftUI
import UIKit

/// iOS 版の主要画面を TabView でまとめるルート View。
struct iOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var rootStore: AppRootStore
    @State private var selectedTab = 0
    @State private var hasHandledCurrentActiveState = false

    /// AppRootStore を外部から差し替えられるようにする。
    @MainActor
    init(dependencies: AppRootDependencies? = nil) {
        let dependencies = dependencies ?? .makeDefault()
        _rootStore = StateObject(wrappedValue: AppRootStore(dependencies: dependencies))
    }

    var body: some View {
        // 主要な画面遷移はタブに集約し、各画面の責務を分ける。
        TabView(selection: $selectedTab) {
            iOSTodayView(
                detailViewModel: rootStore.detailViewModel,
                observationModePreference: rootStore.observationModePreference
            )
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

            AstroPhotoCalculatorView(
                bortleClass: rootStore.detailViewModel.lightPollutionService.bortleClass,
                isSheet: false
            )
            .tabItem {
                Label("撮影計算", systemImage: "camera.aperture")
            }
            .tag(3)

            iOSStarMapView(viewModel: rootStore.starMapViewModel)
                .tabItem {
                    Label("星空", systemImage: "sparkles")
                }
                .tag(4)
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
            // 日付境界の変化はシーン復帰とは別経路で反映する。
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
