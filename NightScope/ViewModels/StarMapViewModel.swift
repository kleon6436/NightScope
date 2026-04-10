import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - Star Color Helper

/// B-V 色指数をスペクトル色にマッピングする。
/// バックグラウンドスレッドから呼び出せるよう nonisolated な自由関数として定義。
func _starColorForBV(_ bvIndex: Double?) -> Color {
    guard let bv = bvIndex else { return .white }
    let table: [(bv: Double, r: Double, g: Double, b: Double)] = [
        (-0.40, 0.55, 0.65, 1.00),
        (-0.20, 0.70, 0.80, 1.00),
        ( 0.00, 0.90, 0.92, 1.00),
        ( 0.15, 1.00, 1.00, 1.00),
        ( 0.40, 1.00, 0.96, 0.85),
        ( 0.65, 1.00, 0.88, 0.65),
        ( 1.00, 1.00, 0.75, 0.45),
        ( 1.40, 1.00, 0.58, 0.30),
        ( 2.00, 1.00, 0.40, 0.20),
    ]
    if bv <= table.first!.bv { return Color(red: table.first!.r, green: table.first!.g, blue: table.first!.b) }
    if bv >= table.last!.bv  { return Color(red: table.last!.r,  green: table.last!.g,  blue: table.last!.b) }
    for i in 1..<table.count {
        let prev = table[i - 1], next = table[i]
        if bv <= next.bv {
            let t = (bv - prev.bv) / (next.bv - prev.bv)
            return Color(red:   prev.r + t * (next.r - prev.r),
                         green: prev.g + t * (next.g - prev.g),
                         blue:  prev.b + t * (next.b - prev.b))
        }
    }
    return .white
}

// MARK: - Computed Star Position

struct StarPosition {
    let star: Star
    let altitude: Double          // 度 (-90〜90)
    let azimuth: Double           // 度 (0=北, 90=東, 180=南, 270=西)
    let precomputedColor: Color   // B-V 色指数から事前に計算したスペクトル色
}

// MARK: - Milky Way Band Point (キャッシュ用)

/// lat/LST から事前計算した天の川バンド中心点。
/// hScale・az0 を掛けるだけで画面座標に変換できる。
struct MilkyWayBandPoint: Sendable {
    let az: Double      // 方位角 (度)
    let alt: Double     // 高度 (度)
    let halfH: Double   // バンド半幅 (度)
    let li: Double      // 銀経 (色計算用)
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
    @Published private(set) var planetPositions: [PlanetPosition] = []
    @Published private(set) var meteorShowerRadiants: [(shower: MeteorShower, altitude: Double, azimuth: Double)] = []
    @Published private(set) var terrainProfile: TerrainProfile? = nil
    /// 天の川バンドのキャッシュ (lat/LST が変わったときのみ再計算)
    @Published private(set) var milkyWayBandPoints: [MilkyWayBandPoint] = []

    // MARK: - Observation datetime (independent of AppController.selectedDate)

    @Published var displayDate: Date = Date() {
        didSet {
            syncTimeSliderWithDisplayDate()
            update()
        }
    }

    @Published private(set) var timeSliderMinutes: Double = 0

    // MARK: - View direction (full-sky planisphere rotation or gyro center)

    /// 画面中心が向く方位角 (度, 0=北, 時計回り)。パノラマモードでは中央の方位
    @Published var viewAzimuth: Double = 0   // 初期値=北向き

    /// 画面中心の仰角 (度, 0=地平線, 90=天頂)。ジャイロモードで使用
    @Published var viewAltitude: Double = 45

    /// ジャイロモードの有効/無効 (iPhone のみ true にする)
    @Published var isGyroMode: Bool = false

    /// 水平視野角 (度): 30°〜150°, デフォルト 90°
    @Published var fov: Double = StarMapLayout.defaultFOV

    /// 星空マップシートが表示中か（サイドバーの視野オーバーレイ連動用）
    @Published var isStarMapOpen: Bool = false

    /// 現在の視野方向（サイドバーマップオーバーレイ用）
    var viewingDirection: ViewingDirection {
        ViewingDirection(azimuth: viewAzimuth, fov: fov, isActive: isStarMapOpen)
    }

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
        syncTimeSliderWithDisplayDate()
        update()
    }

    deinit {
        updateTask?.cancel()
        trailingTask?.cancel()
        terrainFetchTask?.cancel()
    }

    // MARK: - Calculation

    /// 現在の観測地緯度 (度)
    private(set) var latitude: Double = 35.0
    /// 現在の地方恒星時 (度)
    private(set) var currentLST: Double = 0.0

    /// 進行中の計算タスク (新しい update() 呼び出しでキャンセルする)
    private var updateTask: Task<Void, Never>?
    /// trailing-edge debounce 用タスク
    private var trailingTask: Task<Void, Never>?
    /// 前回の計算開始タイムスタンプ (全 update() 呼び出しで共通スロットルに使用)
    private var lastPositionUpdateTime: TimeInterval = 0
    /// 計算更新インターバル: 30fps
    private static let minUpdateInterval: TimeInterval = 1.0 / 30

    func update() {
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastPositionUpdateTime

        if elapsed < Self.minUpdateInterval {
            // 前回から時間が短い → trailing-edge debounce でインターバル後に最終値を計算
            trailingTask?.cancel()
            let remaining = Self.minUpdateInterval - elapsed
            trailingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?._executeUpdate() }
            }
            return
        }
        _executeUpdate()
    }

    private func _executeUpdate() {
        lastPositionUpdateTime = Date.timeIntervalSinceReferenceDate
        trailingTask?.cancel()
        trailingTask = nil

        // MainActor 上でパラメータを読み取り、バックグラウンドへ渡す
        let location = appController.locationController.selectedLocation
        let lat = location.latitude
        let lon = location.longitude
        let date = displayDate
        let jd = MilkyWayCalculator.julianDate(from: date)
        let lst = MilkyWayCalculator.localSiderealTime(jd: jd, longitude: lon)
        let activeMeteorShowerList = MeteorShowerCatalog.active(on: date)

        // 地形プロファイル（座標変化時のみ再取得）
        let newKey = Self.terrainCacheKey(latitude: lat, longitude: lon)
        if newKey != lastTerrainKey {
            lastTerrainKey = newKey
            fetchTerrain(latitude: lat, longitude: lon)
        }

        // 前の計算タスクをキャンセルして新しいタスクを開始
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }

            // 重い計算をバックグラウンドスレッドで実行
            let snapshot = await Task.detached(priority: .userInitiated) {
                StarMapViewModel._compute(lat: lat, lon: lon, jd: jd, lst: lst,
                                          date: date,
                                          activeMeteorShowers: activeMeteorShowerList)
            }.value

            guard !Task.isCancelled else { return }

            // 結果をまとめて MainActor に反映
            self.latitude   = snapshot.lat
            self.currentLST = snapshot.lst
            self.starPositions             = snapshot.starPositions
            self.sunAltitude               = snapshot.sunAltitude
            self.sunAzimuth                = snapshot.sunAzimuth
            self.moonAltitude              = snapshot.moonAltitude
            self.moonAzimuth               = snapshot.moonAzimuth
            self.moonPhase                 = snapshot.moonPhase
            self.galacticCenterAltitude    = snapshot.galacticCenterAltitude
            self.galacticCenterAzimuth     = snapshot.galacticCenterAzimuth
            self.constellationLines        = snapshot.constellationLines
            self.constellationLabels       = snapshot.constellationLabels
            self.planetPositions           = snapshot.planetPositions
            self.meteorShowerRadiants      = snapshot.meteorShowerRadiants
            self.milkyWayBandPoints        = snapshot.milkyWayBandPoints
        }
    }

    // MARK: - Background Computation

    /// B-V 色指数テーブルをキャッシュ。`StarCatalog.stars` と同じ順序・サイズで、
    /// 初回アクセス時に 1 度だけ計算される (Swift static property は thread-safe)。
    private nonisolated static let _cachedStarColors: [Color] = {
        StarCatalog.stars.map { _starColorForBV($0.colorIndex) }
    }()

    /// バックグラウンドスレッドで安全に実行できる純粋計算。
    /// MainActor の状態を一切参照しない nonisolated な static メソッド。
    private nonisolated static func _compute(lat: Double, lon: Double, jd: Double, lst: Double,
                                  date: Date,
                                  activeMeteorShowers: [MeteorShower]) -> _Snapshot {
        // lat の sin/cos を 1 度だけ計算して全天体で共有 (Fix 3)
        let latRad = lat * .pi / 180.0
        let cosLat = cos(latRad)
        let sinLat = sin(latRad)

        // 恒星: altAzFast で lat sin/cos を共有、色キャッシュを参照、地平線下をフィルタ (Fix 1, 3, 5)
        let cachedColors = _cachedStarColors
        let catalog = StarCatalog.stars
        var stars = [StarPosition]()
        stars.reserveCapacity(catalog.count / 2)
        for i in catalog.indices {
            let star = catalog[i]
            let (alt, az) = MilkyWayCalculator.altAzFast(ra: star.ra, dec: star.dec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)
            guard alt > -3 else { continue }  // 地平線以下はスキップ
            stars.append(StarPosition(star: star, altitude: alt, azimuth: az,
                                      precomputedColor: cachedColors[i]))
        }

        // 太陽
        let sun = MilkyWayCalculator.sunRaDec(jd: jd)
        let (sunAlt, sunAz) = MilkyWayCalculator.altAzFast(ra: sun.ra, dec: sun.dec,
                                                            cosLat: cosLat, sinLat: sinLat,
                                                            lst: lst)

        // 月
        let moon = MilkyWayCalculator.moonRaDec(jd: jd)
        let (moonAlt, moonAz) = MilkyWayCalculator.altAzFast(ra: moon.ra, dec: moon.dec,
                                                              cosLat: cosLat, sinLat: sinLat,
                                                              lst: lst)

        // 銀河系中心
        let (gcAlt, gcAz) = MilkyWayCalculator.altAzFast(ra: MilkyWayCalculator.gcRA,
                                                          dec: MilkyWayCalculator.gcDec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)

        // 星座線 (altAzFast で lat sin/cos を共有)
        let constLines: [ConstellationLineAltAz] = ConstellationData.constellations.flatMap { entry in
            entry.segments.compactMap { seg -> ConstellationLineAltAz? in
                let (a1, z1) = MilkyWayCalculator.altAzFast(ra: seg.ra1, dec: seg.dec1,
                                                             cosLat: cosLat, sinLat: sinLat,
                                                             lst: lst)
                let (a2, z2) = MilkyWayCalculator.altAzFast(ra: seg.ra2, dec: seg.dec2,
                                                             cosLat: cosLat, sinLat: sinLat,
                                                             lst: lst)
                guard a1 > -15 || a2 > -15 else { return nil }
                return ConstellationLineAltAz(startAlt: a1, startAz: z1, endAlt: a2, endAz: z2)
            }
        }

        // 星座名ラベル
        let constLabels: [ConstellationLabelAltAz] = ConstellationData.constellations.compactMap { entry in
            let (alt, az) = MilkyWayCalculator.altAzFast(ra: entry.centerRA, dec: entry.centerDec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)
            guard alt > -5 else { return nil }
            return ConstellationLabelAltAz(alt: alt, az: az, name: entry.japaneseName)
        }

        // 惑星
        let planets = MilkyWayCalculator.planetPositions(jd: jd, latitude: lat, lst: lst)

        // 流星群放射点
        let meteorRadiants = activeMeteorShowers.map { shower -> (shower: MeteorShower, altitude: Double, azimuth: Double) in
            let (alt, az) = MilkyWayCalculator.altAzFast(ra: shower.radiantRA, dec: shower.radiantDec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)
            return (shower: shower, altitude: alt, azimuth: az)
        }

        // 天の川バンド (事前計算してキャッシュ)
        let bandPoints = _computeMilkyWayBandPoints(cosLat: cosLat, sinLat: sinLat, lat: lat, lst: lst)

        return _Snapshot(lat: lat, lst: lst,
                         starPositions: stars,
                         sunAltitude: sunAlt, sunAzimuth: sunAz,
                         moonAltitude: moonAlt, moonAzimuth: moonAz, moonPhase: moon.phase,
                         galacticCenterAltitude: gcAlt, galacticCenterAzimuth: gcAz,
                         constellationLines: constLines, constellationLabels: constLabels,
                         planetPositions: planets, meteorShowerRadiants: meteorRadiants,
                         milkyWayBandPoints: bandPoints)
    }

    /// 天の川バンドの alt/az/halfH を計算して返す (描画には含まない純データ)。
    private nonisolated static func _computeMilkyWayBandPoints(cosLat: Double, sinLat: Double,
                                                               lat: Double, lst: Double) -> [MilkyWayBandPoint] {
        var result = [MilkyWayBandPoint]()
        let step: Double = 5
        for li in stride(from: 0.0, through: 360.0, by: step) {
            let eq0 = MilkyWayCalculator.galacticToEquatorial(l: li, b: 0)
            let (alt0, az0) = MilkyWayCalculator.altAzFast(ra: eq0.ra, dec: eq0.dec,
                                                            cosLat: cosLat, sinLat: sinLat,
                                                            lst: lst)
            guard alt0 > -5 else { continue }

            let bWidth: Double = li > 270 || li < 90 ? 12 : 8
            let eq1 = MilkyWayCalculator.galacticToEquatorial(l: li, b:  bWidth)
            let eq2 = MilkyWayCalculator.galacticToEquatorial(l: li, b: -bWidth)
            let (alt1, _) = MilkyWayCalculator.altAzFast(ra: eq1.ra, dec: eq1.dec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)
            let (alt2, _) = MilkyWayCalculator.altAzFast(ra: eq2.ra, dec: eq2.dec,
                                                          cosLat: cosLat, sinLat: sinLat,
                                                          lst: lst)
            let halfHDeg = max(3.0, abs(alt1 - alt2) / 2)
            result.append(MilkyWayBandPoint(az: az0, alt: alt0, halfH: halfHDeg, li: li))
        }
        return result
    }

    // MARK: - Snapshot (バックグラウンド計算結果)

    private struct _Snapshot: Sendable {
        let lat: Double
        let lst: Double
        let starPositions: [StarPosition]
        let sunAltitude: Double
        let sunAzimuth: Double
        let moonAltitude: Double
        let moonAzimuth: Double
        let moonPhase: Double
        let galacticCenterAltitude: Double
        let galacticCenterAzimuth: Double
        let constellationLines: [ConstellationLineAltAz]
        let constellationLabels: [ConstellationLabelAltAz]
        let planetPositions: [PlanetPosition]
        let meteorShowerRadiants: [(shower: MeteorShower, altitude: Double, azimuth: Double)]
        let milkyWayBandPoints: [MilkyWayBandPoint]
    }

    private var lastTerrainKey: String = ""
    private var terrainFetchTask: Task<Void, Never>? = nil

    private func fetchTerrain(latitude: Double, longitude: Double) {
        terrainFetchTask?.cancel()
        terrainFetchTask = Task { [weak self] in
            let profile = await TerrainService.shared.fetchProfile(
                latitude: latitude, longitude: longitude)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.terrainProfile = profile }
        }
    }

    // MARK: - Meteor Showers

    /// 現在の表示日時でアクティブな流星群
    var activeMeteorShowers: [MeteorShower] {
        MeteorShowerCatalog.active(on: displayDate)
    }

    /// 次の流星群とピークまでの日数
    var nextMeteorShower: (shower: MeteorShower, daysUntilPeak: Int)? {
        MeteorShowerCatalog.next(after: displayDate)
    }

    /// 太陽が地平線下 (夜間) か
    var isNight: Bool { sunAltitude < 0 }

    /// 天文薄明 (太陽高度 < -18°) 以上の暗さか
    var isAstronomicalDark: Bool { sunAltitude < -18 }

    /// 現在時刻にリセット
    func resetToNow(referenceDate: Date = Date()) {
        displayDate = referenceDate
    }

    /// 選択日付に現在の時刻を合成して、星空マップの表示日時へ反映する。
    func syncWithSelectedDate(referenceDate: Date = Date()) {
        let selected = appController.selectedDate
        if let date = Self.date(byApplyingTimeOf: referenceDate, to: selected) {
            displayDate = date
        }
    }

    func setTimeSliderMinutes(_ minutes: Double) {
        let clampedMinutes = max(0, min(StarMapLayout.minutesInDay, minutes.rounded()))
        guard abs(timeSliderMinutes - clampedMinutes) > 0.5 else { return }
        timeSliderMinutes = clampedMinutes

        let hour = Int(clampedMinutes) / 60
        let minute = Int(clampedMinutes) % 60
        let calendar = Calendar.current
        if let updatedDate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: displayDate
        ) {
            displayDate = updatedDate
        }
    }

    var displayTimeString: String {
        StarMapPresentation.timeString(from: timeSliderMinutes)
    }

    /// 北向き (方位0°, 仰角30°) にリセット
    func resetToNorth() {
        viewAzimuth = 0
        viewAltitude = StarMapLayout.resetAltitude
    }

    private func syncTimeSliderWithDisplayDate() {
        let minutes = Self.sliderMinutes(for: displayDate)
        guard abs(timeSliderMinutes - minutes) > 0.5 else { return }
        timeSliderMinutes = minutes
    }

    private static func sliderMinutes(for date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func date(byApplyingTimeOf referenceDate: Date, to date: Date) -> Date? {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: referenceDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        )
    }

    static func terrainCacheKey(latitude: Double, longitude: Double) -> String {
        let roundedLatitude = (latitude * 100).rounded() / 100
        let roundedLongitude = (longitude * 100).rounded() / 100
        return "\(roundedLatitude),\(roundedLongitude)"
    }
}

// MARK: - StarPosition + Identifiable

extension StarPosition: Identifiable {
    /// 赤経・赤緯の組み合わせで一意に識別する
    public var id: String { "\(star.ra)-\(star.dec)" }
}
