import SwiftUI

struct SettingsView: View {
    @AppStorage("windSpeedUnit") private var windSpeedUnit: String = WindSpeedUnit.kmh.rawValue
    #if os(macOS)
    @AppStorage(StarDisplayDensity.defaultsKey) private var starDisplayDensity: String = StarDisplayDensity.defaultValue.rawValue
    #endif

    var body: some View {
        formContent
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var formContent: some View {
        Form {
            Section("天気表示") {
                Picker("風速単位", selection: $windSpeedUnit) {
                    ForEach(WindSpeedUnit.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
            }

            #if os(iOS)
            Section("画面ごとの調整") {
                LabeledContent("星の表示数") {
                    Text("「星空」タブで変更")
                        .foregroundStyle(.secondary)
                }

                Text("表示する恒星の量は、「星空」タブ右上の表示メニューから変更できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("情報") {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Label("データソースとアプリ情報", systemImage: "info.circle")
                }
            }
            #else
            Section("星空マップ") {
                Picker("星の表示数", selection: $starDisplayDensity) {
                    ForEach(StarDisplayDensity.allCases) { density in
                        Text(density.settingsLabel).tag(density.rawValue)
                    }
                }

                Text("表示する恒星の等級上限を切り替えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsAboutSections()
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 420, alignment: .top)
        .padding(.vertical, Spacing.sm)
        #endif
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        Form {
            SettingsAboutSections()
        }
        .formStyle(.grouped)
        .navigationTitle("アプリ情報")
    }
}

private struct SettingsAboutSections: View {
    var body: some View {
        Section("データソースとクレジット") {
            VStack(alignment: .leading, spacing: 8) {
                AttributionRow(
                    title: "天気予報",
                    detail: "MET Norway / Norwegian Meteorological Institute",
                    license: "CC BY 4.0"
                )
                AttributionRow(
                    title: "光害マップ",
                    detail: "Falchi et al. 2016 – World Atlas of Artificial Night Sky Brightness (GFZ Data Services)",
                    license: "CC BY 4.0"
                )
                AttributionRow(
                    title: "地形データ",
                    detail: "NASA Shuttle Radar Topography Mission (SRTM)",
                    license: "Public Domain"
                )
                AttributionRow(
                    title: "星カタログ",
                    detail: "Yale Bright Star Catalogue (BSC5) / CDS VizieR",
                    license: "Public Domain"
                )
            }
            .padding(.vertical, 4)
        }

        Section("データ運用") {
            DataSourceStatusRow(
                title: "天気予報",
                detail: "MET Norway API を実行時に取得します。",
                note: "ネットワーク接続が必要です。"
            )
            DataSourceStatusRow(
                title: "光害・地形データ",
                detail: "バンドル済みデータを優先して利用します。",
                note: "未配置の場合は一部表示・計算が簡略化されます。"
            )
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
}

private struct DataSourceStatusRow: View {
    let title: String
    let detail: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AttributionRow: View {
    let title: String
    let detail: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(license)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    SettingsView()
}
