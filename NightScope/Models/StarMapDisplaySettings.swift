import Foundation

struct StarMapDisplaySettings: Equatable {
    static let showsConstellationLinesDefaultsKey = "starMapShowsConstellationLines"

    let density: StarDisplayDensity
    let showsConstellationLines: Bool

    static let defaultValue = StarMapDisplaySettings(
        density: .defaultValue,
        showsConstellationLines: true
    )

    static func load(from defaults: UserDefaults = .standard) -> StarMapDisplaySettings {
        StarMapDisplaySettings(
            density: StarDisplayDensity.load(from: defaults),
            showsConstellationLines: defaults.object(forKey: showsConstellationLinesDefaultsKey) as? Bool
                ?? defaultValue.showsConstellationLines
        )
    }
}
