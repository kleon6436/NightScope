import Foundation

/// 観測目的に応じた星空指数の重み付けモード。
enum ObservationMode: String, CaseIterable, Identifiable, Sendable {
    case general
    case milkyWay
    case meteors
    case moon
    case planetary
    case photography

    var id: String { rawValue }
    var titleKey: String { "observation.mode.\(rawValue).title" }
    var shortTitleKey: String { "observation.mode.\(rawValue).short" }
    var descriptionKey: String { "observation.mode.\(rawValue).description" }

    var iconSystemName: String {
        switch self {
        case .general: return "star.leadinghalf.filled"
        case .milkyWay: return "sparkles"
        case .meteors: return "moon.stars"
        case .moon: return "moon.fill"
        case .planetary: return "globe.americas.fill"
        case .photography: return "camera"
        }
    }

    /// 各評価軸の寄与率をモードごとに切り替える。
    var weights: ObservationModeWeights {
        switch self {
        case .general:
            ObservationModeWeights(constellation: 1.0, weather: 1.0, lightPollution: 1.0, milkyWay: 0.0)
        case .milkyWay:
            ObservationModeWeights(constellation: 0.9, weather: 0.9, lightPollution: 1.25, milkyWay: 1.15)
        case .meteors:
            ObservationModeWeights(constellation: 0.5, weather: 1.4, lightPollution: 0.7, milkyWay: 0.2)
        case .moon:
            ObservationModeWeights(constellation: 0.15, weather: 1.15, lightPollution: 0.35, milkyWay: 0.0)
        case .planetary:
            ObservationModeWeights(constellation: 0.25, weather: 1.5, lightPollution: 0.2, milkyWay: 0.0)
        case .photography:
            ObservationModeWeights(constellation: 0.7, weather: 1.2, lightPollution: 1.0, milkyWay: 0.8)
        }
    }
}

/// 観測モードごとの評価軸ウェイト。
struct ObservationModeWeights: Sendable {
    let constellation: Double
    let weather: Double
    let lightPollution: Double
    let milkyWay: Double
}

/// UserDefaults と同期する観測モードの保存用ラッパー。
final class ObservationModePreference: ObservableObject {
    static let storageKey = "observation.mode"

    @Published var mode: ObservationMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: key)
        }
    }

    private let userDefaults: UserDefaults
    private let key: String

    /// 保存済み値を復元し、旧キーも互換維持のため補正する。
    init(userDefaults: UserDefaults = .standard, key: String = "observation.mode") {
        self.userDefaults = userDefaults
        self.key = key

        let storedValue = userDefaults.string(forKey: key) ?? ""
        let restoredMode = ObservationMode.restoredMode(from: storedValue)
        self.mode = restoredMode

        if !storedValue.isEmpty, restoredMode.rawValue != storedValue {
            userDefaults.set(restoredMode.rawValue, forKey: key)
        }
    }
}

private extension ObservationMode {
    /// 旧バージョンの保存値を現在のモードへ寄せて復元する。
    static func restoredMode(from rawValue: String) -> ObservationMode {
        if let mode = ObservationMode(rawValue: rawValue) {
            return mode
        }

        switch rawValue {
        case "deepSky":
            return .milkyWay
        case "lunarPlanetary":
            return .moon
        default:
            return .general
        }
    }
}
