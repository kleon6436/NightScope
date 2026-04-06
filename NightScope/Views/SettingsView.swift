import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appController: AppController
    @AppStorage("windSpeedUnit") private var windSpeedUnit: String = WindSpeedUnit.kmh.rawValue

    var body: some View {
        Form {
            Section("天気表示") {
                Picker("風速単位", selection: $windSpeedUnit) {
                    ForEach(WindSpeedUnit.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
            }

            Section("星空アシスタント") {
                MLXModelDownloadView(
                    mlxBackend: appController.llmService.mlxBackend,
                    onModelSelected: { spec in
                        Task { @MainActor in
                            await appController.llmService.mlxBackend.selectAndLoad(model: spec)
                        }
                    },
                    onModelDeleted: { spec in
                        await appController.llmService.mlxBackend.deleteModel(spec: spec)
                    }
                )
                .padding(.top, Spacing.xs)
            }

            Section("アプリ情報") {
                LabeledContent("バージョン") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("ビルド") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, alignment: .top)
        .padding(.vertical, Spacing.sm)
        .navigationTitle("設定")
        .onAppear {
            DispatchQueue.main.async {
                guard let settingsWindow = NSApp.keyWindow,
                      let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 != settingsWindow }) else { return }
                let mainFrame = mainWindow.frame
                let size = settingsWindow.frame.size
                settingsWindow.setFrameOrigin(NSPoint(
                    x: mainFrame.midX - size.width / 2,
                    y: mainFrame.midY - size.height / 2
                ))
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppController())
}
