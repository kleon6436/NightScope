import Foundation
import OSLog

// MARK: - Data Types

/// 星座線の両端点 (J2000.0 赤道座標)
struct ConstellationSegment: Decodable {
    let ra1: Double   // 赤経 (度)
    let dec1: Double  // 赤緯 (度)
    let ra2: Double
    let dec2: Double

    init(ra1: Double, dec1: Double, ra2: Double, dec2: Double) {
        self.ra1 = ra1
        self.dec1 = dec1
        self.ra2 = ra2
        self.dec2 = dec2
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        ra1 = try container.decode(Double.self)
        dec1 = try container.decode(Double.self)
        ra2 = try container.decode(Double.self)
        dec2 = try container.decode(Double.self)
    }
}

/// 星座エントリ (日本語名 + 英語名 + 中心座標 + 星座線セグメント群)
struct ConstellationEntry {
    let japaneseName: String
    let englishName: String
    let centerRA: Double   // 星座名ラベルの表示位置
    let centerDec: Double
    let segments: [ConstellationSegment]

    var localizedName: String {
        let localized = L10n.tr(japaneseName)
        guard localized == japaneseName else { return localized }
        guard Locale.preferredLanguages.first?.hasPrefix("ja") != true else { return japaneseName }
        return englishName.isEmpty ? japaneseName : englishName
    }
}

// MARK: - Constellation Catalog

enum ConstellationData {
    private struct ResourceEntry: Decodable {
        let japaneseName: String
        let englishName: String
        let centerRA: Double
        let centerDec: Double
        let segments: [ConstellationSegment]
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NightScope",
        category: "ConstellationData"
    )

    static let constellations: [ConstellationEntry] = loadConstellations()

    private static func loadConstellations() -> [ConstellationEntry] {
        guard let resourceURL = Bundle.main.url(forResource: "constellations_iau", withExtension: "json") else {
            assertionFailure("constellations_iau.json がバンドルされていません")
            logger.error("Missing constellations_iau.json resource")
            return []
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            let decoded = try JSONDecoder().decode([ResourceEntry].self, from: data)
            return decoded.map {
                ConstellationEntry(
                    japaneseName: $0.japaneseName,
                    englishName: $0.englishName,
                    centerRA: $0.centerRA,
                    centerDec: $0.centerDec,
                    segments: $0.segments
                )
            }
        } catch {
            assertionFailure("constellations_iau.json の読み込みに失敗しました: \(error)")
            logger.error("Failed to decode constellations_iau.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
