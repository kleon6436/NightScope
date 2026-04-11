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
        case .maximum: "最大"
        case .large: "大"
        case .medium: "中"
        case .small: "小"
        }
    }

    var magnitudeLabel: String {
        switch self {
        case .maximum: "7.5等級まで"
        case .large: "6.8等級まで"
        case .medium: "6.0等級まで"
        case .small: "5.0等級まで"
        }
    }

    var settingsLabel: String {
        "\(title)（\(magnitudeLabel)）"
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
