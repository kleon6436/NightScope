import SwiftUI

@main
struct NightScopeiOSApp: App {
    @StateObject private var weatherAttributionService = WeatherAttributionService()

    var body: some Scene {
        WindowGroup {
            iOSRootView()
                .environmentObject(weatherAttributionService)
        }
    }
}
