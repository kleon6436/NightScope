import Foundation

struct StarMapDisplaySettings: Equatable {
    static let showsConstellationLinesDefaultsKey = "starMapShowsConstellationLines"
    static let showsConstellationLabelsDefaultsKey = "starMapShowsConstellationLabels"
    static let showsPlanetsDefaultsKey = "starMapShowsPlanets"
    static let showsMeteorShowersDefaultsKey = "starMapShowsMeteorShowers"
    static let showsMilkyWayDefaultsKey = "starMapShowsMilkyWay"

    let density: StarDisplayDensity
    let showsConstellationLines: Bool
    let showsConstellationLabels: Bool
    let showsPlanets: Bool
    let showsMeteorShowers: Bool
    let showsMilkyWay: Bool

    init(
        density: StarDisplayDensity,
        showsConstellationLines: Bool = true,
        showsConstellationLabels: Bool = true,
        showsPlanets: Bool = true,
        showsMeteorShowers: Bool = true,
        showsMilkyWay: Bool = true
    ) {
        self.density = density
        self.showsConstellationLines = showsConstellationLines
        self.showsConstellationLabels = showsConstellationLabels
        self.showsPlanets = showsPlanets
        self.showsMeteorShowers = showsMeteorShowers
        self.showsMilkyWay = showsMilkyWay
    }

    static let defaultValue = StarMapDisplaySettings(
        density: .defaultValue
    )

    static func load(from defaults: UserDefaults = .standard) -> StarMapDisplaySettings {
        StarMapDisplaySettings(
            density: StarDisplayDensity.load(from: defaults),
            showsConstellationLines: defaults.object(forKey: showsConstellationLinesDefaultsKey) as? Bool
                ?? defaultValue.showsConstellationLines,
            showsConstellationLabels: defaults.object(forKey: showsConstellationLabelsDefaultsKey) as? Bool
                ?? defaultValue.showsConstellationLabels,
            showsPlanets: defaults.object(forKey: showsPlanetsDefaultsKey) as? Bool
                ?? defaultValue.showsPlanets,
            showsMeteorShowers: defaults.object(forKey: showsMeteorShowersDefaultsKey) as? Bool
                ?? defaultValue.showsMeteorShowers,
            showsMilkyWay: defaults.object(forKey: showsMilkyWayDefaultsKey) as? Bool
                ?? defaultValue.showsMilkyWay
        )
    }
}
