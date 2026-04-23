import SwiftUI

struct SettingsView: View {
    @AppStorage("windSpeedUnit") private var windSpeedUnit: String = WindSpeedUnit.kmh.rawValue

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

            StarMapDisplaySettingsSection()

            #if os(iOS)
            Section("情報") {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Label("データソースとアプリ情報", systemImage: "info.circle")
                }
            }
            #else
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
                    detail: "Apple Weather",
                    license: "Apple Weather Terms of Service"
                )
                AttributionRow(
                    title: "光害マップ",
                    detail: "Falchi et al. 2016 – World Atlas of Artificial Night Sky Brightness (GFZ Data Services)",
                    license: "CC BY 4.0"
                )
                AttributionRow(
                    title: "地形データ",
                    detail: "Copernicus DEM GLO-30 © DLR/ESA",
                    license: "CC BY 4.0"
                )
                AttributionRow(
                    title: "星カタログ",
                    detail: "Yale Bright Star Catalogue (BSC5) / CDS VizieR",
                    license: "Public Domain"
                )
                AttributionRow(
                    title: "星座線データ",
                    detail: "d3-celestial constellation data / Olaf Frohn",
                    license: "BSD 3-Clause"
                )
            }
            .padding(.vertical, 4)

            Text(verbatim: "d3-celestial BSD 3-Clause notice: Copyright (c) Olaf Frohn. Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, license conditions, and disclaimer are retained. Provided \"as is\" without warranties.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        Section("データ運用") {
            DataSourceStatusRow(
                title: "天気予報",
                detail: "Apple WeatherKit を使用します。",
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
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let note: LocalizedStringKey

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
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let license: LocalizedStringKey

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
