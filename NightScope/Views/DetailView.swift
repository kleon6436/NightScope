import SwiftUI

struct DetailView: View {
    @ObservedObject var appController: AppController

    var body: some View {
        Group {
            if appController.isCalculating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("計算中...")
                        .foregroundColor(.secondary)
                }
            } else if let summary = appController.nightSummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(summary: summary)
                        Divider()
                        ViewingWindowsSection(summary: summary)
                        Divider()
                        UpcomingNightsGrid(appController: appController)
                    }
                    .padding(24)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            if let error = appController.weatherService.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.body)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appController.weatherService.errorMessage)
    }

    // MARK: - Header

    private func headerSection(summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(appController.locationController.locationName)
                    .font(.largeTitle.bold())
                Text(summary.date, style: .date)
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let index = appController.starGazingIndex {
                Divider()
                Text("星空観測情報")
                    .font(.title3.bold())
                StarGazingIndexCard(index: index, lightPollutionService: appController.lightPollutionService)
            }

            GlassEffectContainer {
                HStack(alignment: .top, spacing: 6) {
                    MoonPhaseCard(summary: summary)
                    DarkTimeCard(summary: summary)
                    NightWeatherCard(
                        weather: appController.weatherService.summary(for: appController.selectedDate),
                        isLoading: appController.weatherService.isLoading
                    )
                }
            }
        }
    }
}
