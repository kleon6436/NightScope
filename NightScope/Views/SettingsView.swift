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
                    Label("データソースとクレジット", systemImage: "info.circle")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("天気予報")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    WeatherAttributionBadge(style: .full)
                }
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

            Group {
                Text(verbatim: "Falchi attribution: Contains modified World Atlas of Artificial Night Sky Brightness data © Falchi et al. 2016, GFZ Data Services (DOI: 10.5880/GFZ.1.4.2016.001), licensed under CC BY 4.0.")
                Text(verbatim: "Copernicus attribution: Contains modified Copernicus DEM GLO-30 data © European Union, processed by ESA/DLR, licensed under CC BY 4.0.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Group {
                Link(destination: SettingsAboutLinks.falchiDOI) {
                    Text(verbatim: "Falchi DOI")
                }
                Link(destination: SettingsAboutLinks.ccBy40) {
                    Text(verbatim: "CC BY 4.0 ライセンス")
                }
                Link(destination: SettingsAboutLinks.copernicusLicense) {
                    Text(verbatim: "Copernicus DEM ライセンス")
                }
                Link(destination: SettingsAboutLinks.d3CelestialLicense) {
                    Text(verbatim: "d3-celestial LICENSE")
                }
            }
            .font(.caption2)

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

private enum SettingsAboutLinks {
    static let falchiDOI = URL(string: "https://doi.org/10.5880/GFZ.1.4.2016.001")!
    static let ccBy40 = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let copernicusLicense = URL(string: "https://land.copernicus.eu/en/data/data-access/guest-license")!
    static let d3CelestialLicense = URL(string: "https://github.com/ofrohn/d3-celestial/blob/master/LICENSE")!
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
