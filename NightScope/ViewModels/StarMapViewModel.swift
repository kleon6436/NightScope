import Foundation
import CoreLocation
import Combine

// MARK: - Computed Star Position

struct StarPosition {
    let star: Star
    let altitude: Double   // 度 (-90〜90)
    let azimuth: Double    // 度 (0=北, 90=東, 180=南, 270=西)
}

// MARK: - Constellation overlay types

struct ConstellationLineAltAz {
    let startAlt: Double
    let startAz: Double
    let endAlt: Double
    let endAz: Double
}

struct ConstellationLabelAltAz {
    let alt: Double
    let az: Double
    let name: String
}

// MARK: - ViewModel

@MainActor
final class StarMapViewModel: ObservableObject {

    // MARK: - Celestial object positions

    @Published private(set) var starPositions: [StarPosition] = []
    @Published private(set) var sunAltitude: Double = 0
    @Published private(set) var sunAzimuth: Double = 0
    @Published private(set) var moonAltitude: Double = 0
    @Published private(set) var moonAzimuth: Double = 0
    @Published private(set) var moonPhase: Double = 0      // 0=新月, 0.5=満月, 1=新月
    @Published private(set) var galacticCenterAltitude: Double = 0
    @Published private(set) var galacticCenterAzimuth: Double = 0
    @Published private(set) var constellationLines: [ConstellationLineAltAz] = []
    @Published private(set) var constellationLabels: [ConstellationLabelAltAz] = []

    // MARK: - Observation datetime (independent of AppController.selectedDate)

    @Published var displayDate: Date = Date() {
        didSet { update() }
    }

    // MARK: - View direction (full-sky planisphere rotation or gyro center)

    /// 画面中心が向く方位角 (度, 0=北, 時計回り)。パノラマモードでは中央の方位
    @Published var viewAzimuth: Double = 0   // 初期値=北向き

    /// 画面中心の仰角 (度, 0=地平線, 90=天頂)。ジャイロモードで使用
    @Published var viewAltitude: Double = 45

    /// ジャイロモードの有効/無効 (iPhone のみ true にする)
    @Published var isGyroMode: Bool = false

    /// 水平視野角 (度): 30°〜150°, デフォルト 90°
    @Published var fov: Double = 90

    // MARK: - Dependencies

    private let appController: AppController
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(appController: AppController) {
        self.appController = appController
        // 場所が変わったら再計算
        appController.locationController.anyChangePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)
        update()
    }

    // MARK: - Calculation

    func update() {
        let location = appController.locationController.selectedLocation
        let lat = location.latitude
        let lon = location.longitude
        let jd = MilkyWayCalculator.julianDate(from: displayDate)
        let lst = MilkyWayCalculator.localSiderealTime(jd: jd, longitude: lon)

        // 恒星の位置
        starPositions = StarCatalog.stars.map { star in
            let alt = MilkyWayCalculator.altitude(ra: star.ra, dec: star.dec, latitude: lat, lst: lst)
            let az  = MilkyWayCalculator.azimuth(ra: star.ra, dec: star.dec, latitude: lat, lst: lst)
            return StarPosition(star: star, altitude: alt, azimuth: az)
        }

        // 太陽
        let sun = MilkyWayCalculator.sunRaDec(jd: jd)
        sunAltitude = MilkyWayCalculator.altitude(ra: sun.ra, dec: sun.dec, latitude: lat, lst: lst)
        sunAzimuth  = MilkyWayCalculator.azimuth(ra: sun.ra, dec: sun.dec, latitude: lat, lst: lst)

        // 月
        let moon = MilkyWayCalculator.moonRaDec(jd: jd)
        moonAltitude = MilkyWayCalculator.altitude(ra: moon.ra, dec: moon.dec, latitude: lat, lst: lst)
        moonAzimuth  = MilkyWayCalculator.azimuth(ra: moon.ra, dec: moon.dec, latitude: lat, lst: lst)
        moonPhase    = moon.phase

        // 銀河系中心
        galacticCenterAltitude = MilkyWayCalculator.altitude(
            ra: MilkyWayCalculator.gcRA, dec: MilkyWayCalculator.gcDec, latitude: lat, lst: lst)
        galacticCenterAzimuth  = MilkyWayCalculator.azimuth(
            ra: MilkyWayCalculator.gcRA, dec: MilkyWayCalculator.gcDec, latitude: lat, lst: lst)

        // 星座線
        constellationLines = ConstellationData.constellations.flatMap { entry in
            entry.segments.compactMap { seg in
                let a1 = MilkyWayCalculator.altitude(ra: seg.ra1, dec: seg.dec1, latitude: lat, lst: lst)
                let a2 = MilkyWayCalculator.altitude(ra: seg.ra2, dec: seg.dec2, latitude: lat, lst: lst)
                guard a1 > -15 || a2 > -15 else { return nil }
                let z1 = MilkyWayCalculator.azimuth(ra: seg.ra1, dec: seg.dec1, latitude: lat, lst: lst)
                let z2 = MilkyWayCalculator.azimuth(ra: seg.ra2, dec: seg.dec2, latitude: lat, lst: lst)
                return ConstellationLineAltAz(startAlt: a1, startAz: z1, endAlt: a2, endAz: z2)
            }
        }

        // 星座名ラベル
        constellationLabels = ConstellationData.constellations.compactMap { entry in
            let alt = MilkyWayCalculator.altitude(ra: entry.centerRA, dec: entry.centerDec, latitude: lat, lst: lst)
            guard alt > -5 else { return nil }
            let az  = MilkyWayCalculator.azimuth(ra: entry.centerRA, dec: entry.centerDec, latitude: lat, lst: lst)
            return ConstellationLabelAltAz(alt: alt, az: az, name: entry.japaneseName)
        }
    }

    // MARK: - Helpers

    /// 太陽が地平線下 (夜間) か
    var isNight: Bool { sunAltitude < 0 }

    /// 天文薄明 (太陽高度 < -18°) 以上の暗さか
    var isAstronomicalDark: Bool { sunAltitude < -18 }

    /// 現在時刻にリセット
    func resetToNow() {
        displayDate = Date()
    }

    /// 北向き (方位0°, 仰角30°) にリセット
    func resetToNorth() {
        viewAzimuth = 0
        viewAltitude = 30
    }
}

// MARK: - StarPosition + Identifiable

extension StarPosition: Identifiable {
    /// 赤経・赤緯の組み合わせで一意に識別する
    public var id: String { "\(star.ra)-\(star.dec)" }
}
