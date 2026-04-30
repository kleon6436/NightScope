import Foundation
import SwiftUI

enum SensorSize: String, CaseIterable, Identifiable {
    case fullFrame = "フルサイズ (35mm)"
    case apscNikonSony = "APS-C (Nikon / Sony / Fuji)"
    case apscCanon = "APS-C (Canon)"
    case mft = "マイクロフォーサーズ"
    case oneInch = "1インチ"
    case custom = "カスタム"

    var id: String { rawValue }

    /// センサー幅 (mm)。custom の場合は 0。
    var sensorWidthMm: Double {
        switch self {
        case .fullFrame:
            return 36.0
        case .apscNikonSony:
            return 23.5
        case .apscCanon:
            return 22.3
        case .mft:
            return 17.3
        case .oneInch:
            return 13.2
        case .custom:
            return 0
        }
    }

    /// 幅/高さ アスペクト比（ピクセルピッチ計算に使用）
    var aspectRatio: Double {
        self == .mft ? (4.0 / 3.0) : (3.0 / 2.0)
    }
}

@MainActor
final class AstroPhotoCalculatorViewModel: ObservableObject {
    private enum Keys {
        static let focalLength = "astroPhoto.focalLength"
        static let aperture = "astroPhoto.aperture"
        static let sensorSize = "astroPhoto.sensorSize"
        static let megapixels = "astroPhoto.megapixels"
        static let customPixelPitch = "astroPhoto.customPixelPitch"
        static let isStacking = "astroPhoto.isStacking"
        static let targetFrameCount = "astroPhoto.targetFrameCount"
    }

    @Published var focalLength: Double = 50 {
        didSet { UserDefaults.standard.set(focalLength, forKey: Keys.focalLength) }
    }
    @Published var aperture: Double = 2.8 {
        didSet { UserDefaults.standard.set(aperture, forKey: Keys.aperture) }
    }
    @Published var sensorSize: SensorSize = .apscNikonSony {
        didSet { UserDefaults.standard.set(sensorSize.rawValue, forKey: Keys.sensorSize) }
    }
    @Published var megapixels: Double = 24 {
        didSet { UserDefaults.standard.set(megapixels, forKey: Keys.megapixels) }
    }
    @Published var customPixelPitch: Double = 3.76 {
        didSet { UserDefaults.standard.set(customPixelPitch, forKey: Keys.customPixelPitch) }
    }
    @Published var isStacking: Bool = true {
        didSet { UserDefaults.standard.set(isStacking, forKey: Keys.isStacking) }
    }
    @Published var targetFrameCount: Int = 30 {
        didSet { UserDefaults.standard.set(targetFrameCount, forKey: Keys.targetFrameCount) }
    }
    @Published var bortleClass: Int {
        didSet {
            let clamped = Self.clampBortleClass(bortleClass)
            if clamped != bortleClass {
                bortleClass = clamped
            }
        }
    }

    init(bortleClass: Double?) {
        let ud = UserDefaults.standard
        self.focalLength = ud.object(forKey: Keys.focalLength) as? Double ?? 50
        self.aperture = ud.object(forKey: Keys.aperture) as? Double ?? 2.8
        let sensorRaw = ud.string(forKey: Keys.sensorSize) ?? SensorSize.apscNikonSony.rawValue
        self.sensorSize = SensorSize(rawValue: sensorRaw) ?? .apscNikonSony
        self.megapixels = ud.object(forKey: Keys.megapixels) as? Double ?? 24
        self.customPixelPitch = ud.object(forKey: Keys.customPixelPitch) as? Double ?? 3.76
        self.isStacking = ud.object(forKey: Keys.isStacking) as? Bool ?? true
        self.targetFrameCount = ud.object(forKey: Keys.targetFrameCount) as? Int ?? 30
        self.bortleClass = Self.clampBortleClass(Self.roundedBortleClass(bortleClass) ?? 5)
    }

    var effectivePixelPitch: Double {
        if sensorSize == .custom {
            return max(0, customPixelPitch)
        }

        let sensorWidthMm = sensorSize.sensorWidthMm
        let pixelCount = megapixels * 1_000_000 * sensorSize.aspectRatio
        guard sensorWidthMm > 0, pixelCount > 0 else {
            return 0
        }

        let value = sensorWidthMm * 1000 / sqrt(pixelCount)
        return max(0, value)
    }

    var settings: AstroPhotoSettings? {
        guard focalLength > 0, aperture > 0, effectivePixelPitch > 0 else {
            return nil
        }

        return AstroPhotoCalculator.calculate(
            focalLength: focalLength,
            aperture: aperture,
            pixelPitch: effectivePixelPitch,
            bortleClass: bortleClass,
            targetFrameCount: targetFrameCount,
            stacking: isStacking
        )
    }

    private static func roundedBortleClass(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int(value.rounded())
    }

    private static func clampBortleClass(_ value: Int) -> Int {
        min(max(value, 1), 9)
    }
}
