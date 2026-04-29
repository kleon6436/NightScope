import Foundation

/// 星図で表示する恒星数の密度プリセット。
enum StarDisplayDensity: String, CaseIterable, Identifiable {
    case maximum
    case large
    case medium
    case small

    /// UserDefaults に保存するキー。
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

    /// この密度で表示対象に含める限界等級。
    var maxMagnitude: Double {
        switch self {
        case .maximum: 7.5
        case .large: 6.8
        case .medium: 6.0
        case .small: 5.0
        }
    }

    static let defaultValue: StarDisplayDensity = .maximum

    /// 保存済み設定を読み込み、未設定時は既定値を返す。
    static func load(from defaults: UserDefaults = .standard) -> StarDisplayDensity {
        StarDisplayDensity(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? defaultValue
    }
}
