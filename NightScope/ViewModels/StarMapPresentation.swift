import Foundation
import CoreLocation
import Combine
import SwiftUI

/// BV 色指数から恒星の見た目の色を近似する。
func _starColorForBV(_ bvIndex: Double?) -> Color {
    guard let bv = bvIndex else { return .white }
    let table: [(bv: Double, r: Double, g: Double, b: Double)] = [
        (-0.40, 0.55, 0.65, 1.00),
        (-0.20, 0.70, 0.80, 1.00),
        (0.00, 0.90, 0.92, 1.00),
        (0.15, 1.00, 1.00, 1.00),
        (0.40, 1.00, 0.96, 0.85),
        (0.65, 1.00, 0.88, 0.65),
        (1.00, 1.00, 0.75, 0.45),
        (1.40, 1.00, 0.58, 0.30),
        (2.00, 1.00, 0.40, 0.20),
    ]
    guard let first = table.first, let last = table.last else { return .white }
    if bv <= first.bv { return Color(red: first.r, green: first.g, blue: first.b) }
    if bv >= last.bv { return Color(red: last.r, green: last.g, blue: last.b) }
    for i in 1..<table.count {
        let prev = table[i - 1], next = table[i]
        if bv <= next.bv {
            let t = (bv - prev.bv) / (next.bv - prev.bv)
            return Color(
                red: prev.r + t * (next.r - prev.r),
                green: prev.g + t * (next.g - prev.g),
                blue: prev.b + t * (next.b - prev.b)
            )
        }
    }
    return .white
}

/// 描画対象の恒星 1 件分の座標と色を保持する。
struct StarPosition {
    let star: Star
    let altitude: Double
    let azimuth: Double
    let precomputedColor: Color
}

/// 銀河面の帯を描くためのサンプル点。
struct MilkyWayBandPoint: Sendable {
    let az: Double
    let alt: Double
    let halfH: Double
    let li: Double
}

/// 星座線の 2 点を水平座標系へ変換した結果。
struct ConstellationLineAltAz {
    let startAlt: Double
    let startAz: Double
    let endAlt: Double
    let endAz: Double
}

/// 星座ラベルを配置する水平座標系の位置。
struct ConstellationLabelAltAz {
    let alt: Double
    let az: Double
    let name: String
}
