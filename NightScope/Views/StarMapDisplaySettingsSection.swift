import SwiftUI

struct StarMapDisplaySettingsSection: View {
    @AppStorage(StarDisplayDensity.defaultsKey)
    private var starDisplayDensityRaw: String = StarDisplayDensity.defaultValue.rawValue
    @AppStorage(StarMapDisplaySettings.showsConstellationLinesDefaultsKey)
    private var showsConstellationLines: Bool = StarMapDisplaySettings.defaultValue.showsConstellationLines

    var body: some View {
        Section(L10n.tr("星空マップ")) {
            Picker(L10n.tr("星の表示数"), selection: starDisplayDensityBinding) {
                ForEach(StarDisplayDensity.allCases) { density in
                    Text(density.settingsLabel).tag(density)
                }
            }

            Toggle(L10n.tr("星座線"), isOn: $showsConstellationLines)

            Text(L10n.tr("表示する恒星の量や星座線の表示を調整します。変更は星空マップへすぐ反映されます。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var starDisplayDensityBinding: Binding<StarDisplayDensity> {
        Binding(
            get: {
                StarDisplayDensity(rawValue: starDisplayDensityRaw) ?? .defaultValue
            },
            set: { density in
                starDisplayDensityRaw = density.rawValue
            }
        )
    }
}
