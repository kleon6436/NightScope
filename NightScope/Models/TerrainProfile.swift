import Foundation

/// 観測地周辺の地平線プロファイル。
/// 72 要素 (5° 刻み, 0°〜355°) の仰角配列を保持し、任意方位の地平仰角を線形補間で返す。
struct TerrainProfile {
    private enum Constants {
        static let sampleCount = 72
        static let degreesPerSample = 5.0
    }

    /// horizonAngles[i] = 方位 i×5° における地形遮蔽仰角 (度)
    /// 正値 = 山稜が空を遮る高さ、負値 = 地平線より低い
    let horizonAngles: [Double]

    /// 5° 刻み 72 点のサンプル配列だけを受け付ける。
    init(horizonAngles: [Double]) {
        precondition(
            horizonAngles.count == Constants.sampleCount,
            "TerrainProfile requires exactly \(Constants.sampleCount) horizon samples."
        )
        self.horizonAngles = horizonAngles
    }

    /// 任意方位 (度) の地平仰角を線形補間で返す。
    func horizonAngle(forAzimuth azDeg: Double) -> Double {
        let normalized = ((azDeg.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let idx = normalized / Constants.degreesPerSample
        let lo  = Int(idx) % Constants.sampleCount
        let hi  = (lo + 1) % Constants.sampleCount
        let t   = idx - floor(idx)
        return horizonAngles[lo] * (1 - t) + horizonAngles[hi] * t
    }
}
