import Foundation

enum StarDisplayDensity: String, CaseIterable, Identifiable {
    case maximum
    case large
    case medium
    case small

    static let defaultsKey = "starDisplayDensity"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maximum: L10n.tr("最大")
        case .large: L10n.tr("大")
        case .medium: L10n.tr("中")
        case .small: L10n.tr("小")
        }
    }

    var magnitudeLabel: String {
        L10n.format("%.1f等級まで", maxMagnitude)
    }

    var settingsLabel: String {
        L10n.format("%@（%@）", title, magnitudeLabel)
    }

    var maxMagnitude: Double {
        switch self {
        case .maximum: 7.5
        case .large: 6.8
        case .medium: 6.0
        case .small: 5.0
        }
    }

    static let defaultValue: StarDisplayDensity = .maximum

    static func load(from defaults: UserDefaults = .standard) -> StarDisplayDensity {
        StarDisplayDensity(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? defaultValue
    }
}
