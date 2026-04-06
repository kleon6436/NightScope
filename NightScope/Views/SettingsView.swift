import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appController: AppController
    @AppStorage("windSpeedUnit") private var windSpeedUnit: String = WindSpeedUnit.kmh.rawValue
    @AppStorage("llm_backend") private var llmBackendRaw: String = LLMBackendKind.appleIntelligence.rawValue

    private var selectedBackend: LLMBackendKind {
        LLMBackendKind(rawValue: llmBackendRaw) ?? .appleIntelligence
    }

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
                Picker("AI バックエンド", selection: $llmBackendRaw) {
                    ForEach(LLMBackendKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }

                if selectedBackend == .mlx {
                    MLXModelDownloadView(
                        mlxBackend: appController.llmService.mlxBackend,
                        onModelSelected: { spec in
                            Task { @MainActor in
                                await appController.llmService.mlxBackend.selectAndLoad(model: spec)
                            }
                        }
                    )
                    .padding(.top, Spacing.xs)
                }
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
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppController())
}
