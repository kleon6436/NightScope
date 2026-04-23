import SwiftUI

struct StarMapDisplaySettingsSection: View {
    @AppStorage(StarDisplayDensity.defaultsKey)
    private var starDisplayDensityRaw: String = StarDisplayDensity.defaultValue.rawValue
    @AppStorage(StarMapDisplaySettings.showsConstellationLinesDefaultsKey)
    private var showsConstellationLines: Bool = StarMapDisplaySettings.defaultValue.showsConstellationLines
    @AppStorage(StarMapDisplaySettings.showsConstellationLabelsDefaultsKey)
    private var showsConstellationLabels: Bool = StarMapDisplaySettings.defaultValue.showsConstellationLabels
    @AppStorage(StarMapDisplaySettings.showsPlanetsDefaultsKey)
    private var showsPlanets: Bool = StarMapDisplaySettings.defaultValue.showsPlanets
    @AppStorage(StarMapDisplaySettings.showsMeteorShowersDefaultsKey)
    private var showsMeteorShowers: Bool = StarMapDisplaySettings.defaultValue.showsMeteorShowers
    @AppStorage(StarMapDisplaySettings.showsMilkyWayDefaultsKey)
    private var showsMilkyWay: Bool = StarMapDisplaySettings.defaultValue.showsMilkyWay

    var body: some View {
        Section(L10n.tr("星空マップ")) {
            Picker(L10n.tr("星の表示数"), selection: starDisplayDensityBinding) {
                ForEach(StarDisplayDensity.allCases) { density in
                    Text(density.settingsLabel).tag(density)
                }
            }

            Toggle(L10n.tr("星座線"), isOn: $showsConstellationLines)
            Toggle(L10n.tr("星座名ラベル"), isOn: $showsConstellationLabels)
            Toggle(L10n.tr("惑星"), isOn: $showsPlanets)
            Toggle(L10n.tr("流星群放射点"), isOn: $showsMeteorShowers)
            Toggle(L10n.tr("天の川"), isOn: $showsMilkyWay)

            Text(L10n.tr("表示する恒星の量や星図レイヤーを調整します。変更は星空マップへすぐ反映されます。"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("観測ヒートバーの色の意味"))
                    .font(.footnote.weight(.semibold))

                ForEach(ObservationHeatBarView.legendItems) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.color)
                            .frame(width: 18, height: 10)
                            .accessibilityHidden(true)

                        Text(item.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.tr("青から赤に近づくほど太陽や月の影響で観測条件が厳しくなります。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
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
