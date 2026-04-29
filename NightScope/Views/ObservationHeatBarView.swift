import SwiftUI

/// 太陽と月の影響度を時間軸で示す観測ヒートバー。
struct ObservationHeatBarView: View {
    struct LegendItem: Equatable, Identifiable {
        let label: String
        let color: Color

        var id: String { label }
    }

    let observationConditionTimeline: [StarMapObservationConditionSample]
    let sliderFraction: Double
    let currentMoonAltitude: Double
    let currentMoonPhase: Double
    let currentSunAltitude: Double
    let currentTimeText: String

    var body: some View {
        if !observationConditionTimeline.isEmpty {
            GeometryReader { proxy in
                // スライダー位置をバー幅へ正規化し、現在時刻の位置を重ねる。
                let indicatorX = max(0, min(1, sliderFraction)) * proxy.size.width

                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(observationConditionTimeline.indices, id: \.self) { index in
                            Rectangle()
                                .fill(segmentColor(for: observationConditionTimeline[index]))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .clipShape(Capsule())

                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)

                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: proxy.size.height + 4)
                        .offset(x: min(max(indicatorX - 1.5, 0), max(proxy.size.width - 3, 0)))
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.tr("観測ヒートバー"))
            .accessibilityValue(
                L10n.format(
                    "%@。現在時刻 %@。%@",
                    qualityText(
                        for: currentMoonAltitude,
                        moonPhase: currentMoonPhase,
                        sunAltitude: currentSunAltitude
                    ),
                    currentTimeText,
                    conditionStateText(
                        moonAltitude: currentMoonAltitude,
                        moonPhase: currentMoonPhase,
                        sunAltitude: currentSunAltitude
                    )
                )
            )
            .accessibilityHint(L10n.tr("色で太陽や月の影響を含む観測条件の強さを示します"))
        }
    }

    private func segmentColor(for sample: StarMapObservationConditionSample) -> Color {
        Self.color(
            for: impactScore(
                moonAltitude: sample.moonAltitude,
                moonPhase: sample.moonPhase,
                sunAltitude: sample.sunAltitude
            )
        )
    }

    private func qualityText(for moonAltitude: Double, moonPhase: Double, sunAltitude: Double) -> String {
        Self.qualityLabel(
            moonAltitude: moonAltitude,
            moonPhase: moonPhase,
            sunAltitude: sunAltitude
        )
    }

    private func impactScore(moonAltitude: Double, moonPhase: Double, sunAltitude: Double) -> Double {
        Self.combinedImpactScore(
            moonAltitude: moonAltitude,
            moonPhase: moonPhase,
            sunAltitude: sunAltitude
        )
    }

    static func combinedImpactScore(moonAltitude: Double, moonPhase: Double, sunAltitude: Double) -> Double {
        let sunImpact = sunImpactScore(for: sunAltitude)
        let moonImpact = moonImpactScore(moonAltitude: moonAltitude, moonPhase: moonPhase)
        return 1 - ((1 - sunImpact) * (1 - moonImpact))
    }

    static func sunImpactScore(for sunAltitude: Double) -> Double {
        switch sunAltitude {
        case 0...:
            1.0
        case -6..<0:
            0.92
        case -12..<(-6):
            0.74
        case -18..<(-12):
            0.45
        default:
            0
        }
    }

    static func moonImpactScore(moonAltitude: Double, moonPhase: Double) -> Double {
        guard moonAltitude > 0 else { return 0 }
        let illumination = moonIllumination(for: moonPhase)
        let altitudeFactor = min(1.0, max(0.85, moonAltitude / 25.0))
        let baseImpact: Double

        switch illumination {
        case 0.60...:
            baseImpact = 0.95
        case 0.30...:
            baseImpact = 0.80
        case 0.15...:
            baseImpact = 0.38
        case 0.05...:
            baseImpact = 0.20
        default:
            baseImpact = 0
        }

        return min(1, baseImpact * altitudeFactor)
    }

    static func qualityLabel(moonAltitude: Double, moonPhase: Double, sunAltitude: Double) -> String {
        label(for: combinedImpactScore(
            moonAltitude: moonAltitude,
            moonPhase: moonPhase,
            sunAltitude: sunAltitude
        ))
    }

    static func conditionStateText(
        moonAltitude: Double,
        moonPhase: Double,
        sunAltitude: Double
    ) -> String {
        if let twilightText = twilightStateText(for: sunAltitude) {
            return twilightText
        }
        return moonStateText(moonAltitude: moonAltitude, moonPhase: moonPhase)
    }

    private func conditionStateText(moonAltitude: Double, moonPhase: Double, sunAltitude: Double) -> String {
        Self.conditionStateText(
            moonAltitude: moonAltitude,
            moonPhase: moonPhase,
            sunAltitude: sunAltitude
        )
    }

    private static func twilightStateText(for sunAltitude: Double) -> String? {
        switch sunAltitude {
        case 0...:
            L10n.tr("太陽が地平線上です")
        case -6..<0:
            L10n.tr("市民薄明中です")
        case -12..<(-6):
            L10n.tr("航海薄明中です")
        case -18..<(-12):
            L10n.tr("天文薄明中です")
        default:
            nil
        }
    }

    private static func moonStateText(moonAltitude: Double, moonPhase: Double) -> String {
        if moonAltitude <= 0 {
            return L10n.tr("月は地平線の下です")
        }
        switch moonIllumination(for: moonPhase) {
        case 0.60...:
            return L10n.tr("月明かりの影響が強い")
        case 0.30...:
            return L10n.tr("月明かりに注意")
        case 0.15...:
            return L10n.tr("月明かりの影響あり")
        case 0.05...:
            return L10n.tr("月明かりの影響が小さい")
        default:
            break
        }
        return L10n.format("月の高度は %.0f° です", moonAltitude)
    }

    private static func moonIllumination(for moonPhase: Double) -> Double {
        (1.0 - cos(moonPhase * 2.0 * .pi)) / 2.0
    }

    static var legendItems: [LegendItem] {
        [
            LegendItem(label: label(for: 0.0), color: color(for: 0.0)),
            LegendItem(label: label(for: 0.2), color: color(for: 0.2)),
            LegendItem(label: label(for: 0.5), color: color(for: 0.5)),
            LegendItem(label: label(for: 0.8), color: color(for: 0.8))
        ]
    }

    private static func color(for impactScore: Double) -> Color {
        switch impactScore {
        case ..<0.12:
            Color.blue.opacity(0.75)
        case ..<0.35:
            Color.green.opacity(0.8)
        case ..<0.65:
            Color.orange.opacity(0.82)
        default:
            Color.red.opacity(0.82)
        }
    }

    private static func label(for impactScore: Double) -> String {
        switch impactScore {
        case ..<0.12:
            L10n.tr("観測条件が良い")
        case ..<0.35:
            L10n.tr("観測条件はまずまず")
        case ..<0.65:
            L10n.tr("観測条件に注意")
        default:
            L10n.tr("観測条件は厳しい")
        }
    }
}
