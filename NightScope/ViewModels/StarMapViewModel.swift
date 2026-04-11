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
            handleDisplayDateChange(from: oldValue, to: displayDate)
        }
    }

    @Published private(set) var timeSliderMinutes: Double = 0
    @Published private(set) var isTimeSliderScrubbing: Bool = false

    /// 夜間開始時刻 (分, 0-1439) — 市民薄明 (太陽高度 -6°) 基準
    @Published private(set) var nightStartMinutes: Double = 1080  // デフォルト 18:00
    /// 夜間の長さ (分)
    @Published private(set) var nightDurationMinutes: Double = 600 // デフォルト 10時間

    // MARK: - View direction (full-sky planisphere rotation or gyro center)

    /// 画面中心が向く方位角 (度, 0=北, 時計回り)。パノラマモードでは中央の方位
    @Published var viewAzimuth: Double = 0   // 初期値=北向き

    /// 画面中心の仰角 (度, 0=地平線, 90=天頂)。ジャイロモードで使用
    @Published var viewAltitude: Double = 45

    /// ジャイロモードの有効/無効 (iPhone のみ true にする)
    @Published var isGyroMode: Bool = false

    /// 水平視野角 (度): 30°〜150°, デフォルト 90°
    @Published var fov: Double = StarMapLayout.defaultFOV

    /// 星空マップ描画領域の最新サイズ
    @Published private(set) var panoramaViewportSize: CGSize = .zero

    /// 星空マップシートが表示中か（サイドバーの視野オーバーレイ連動用）
    @Published var isStarMapOpen: Bool = false

    /// 現在の視野方向（サイドバーマップオーバーレイ用）
    var viewingDirection: ViewingDirection {
        ViewingDirection(azimuth: viewAzimuth, fov: fov, isActive: isStarMapOpen)
    }

    // MARK: - Dependencies

    private let appController: AppController
    private var cancellables: Set<AnyCancellable> = []
    private var shouldApplyInitialPanoramaPose = true
    private var lastTimeSliderCommitTime: TimeInterval = 0
    private var pendingTimeSliderDate: Date?
    private var timeSliderCommitTask: Task<Void, Never>?
    private var displayDateUpdateMode: DisplayDateUpdateMode = .standard

    // MARK: - Init

    init(appController: AppController) {
        self.appController = appController
        // 場所が変わったら再計算
        appController.locationController.anyChangePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateNightRange()
                self?.update()
            }
            .store(in: &cancellables)
        updateNightRange()
        syncTimeSliderWithDisplayDate()
        update()
    }

    deinit {
        updateTask?.cancel()
        trailingTask?.cancel()
        timeSliderCommitTask?.cancel()
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
    /// 通常時の計算更新インターバル: 30fps
    private static let minUpdateInterval: TimeInterval = 1.0 / 30
    /// スライダー編集中の計算更新インターバル: 20fps
    private static let minScrubbingUpdateInterval: TimeInterval = 1.0 / 20
    /// スライダー編集中の日時コミット間隔: 20fps
    private static let timeSliderCommitInterval: TimeInterval = 1.0 / 20

    private struct UpdateContext {
        let latitude: Double
        let longitude: Double
        let julianDate: Double
        let localSiderealTime: Double
        let activeMeteorShowers: [MeteorShower]

        var terrainCacheKey: String {
            StarMapViewModel.terrainCacheKey(latitude: latitude, longitude: longitude)
        }
    }

    private enum DisplayDateUpdateMode {
        case standard
        case preserveNightRangeAndSlider

        var skipsNightRange: Bool {
            self == .preserveNightRangeAndSlider
        }

        var skipsTimeSliderSync: Bool {
            self == .preserveNightRangeAndSlider
        }
    }

    func update() {
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastPositionUpdateTime
        let minUpdateInterval = currentMinUpdateInterval

        if elapsed < minUpdateInterval {
            // 前回から時間が短い → trailing-edge debounce でインターバル後に最終値を計算
            trailingTask?.cancel()
            let remaining = minUpdateInterval - elapsed
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

        let context = makeUpdateContext()
        scheduleTerrainFetchIfNeeded(for: context)

        // 前の計算タスクをキャンセルして新しいタスクを開始
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }

            // 重い計算をバックグラウンドスレッドで実行
            let snapshot = await Task.detached(priority: .userInitiated) {
                StarMapViewModel._compute(
                    lat: context.latitude,
                    lon: context.longitude,
                    jd: context.julianDate,
                    lst: context.localSiderealTime,
                    activeMeteorShowers: context.activeMeteorShowers
                )
            }.value

            guard !Task.isCancelled else { return }
            apply(snapshot)
        }
    }

    private func makeUpdateContext() -> UpdateContext {
        let location = appController.locationController.selectedLocation
        let date = displayDate
        let julianDate = MilkyWayCalculator.julianDate(from: date)

        return UpdateContext(
            latitude: location.latitude,
            longitude: location.longitude,
            julianDate: julianDate,
            localSiderealTime: MilkyWayCalculator.localSiderealTime(
                jd: julianDate,
                longitude: location.longitude
            ),
            activeMeteorShowers: MeteorShowerCatalog.active(on: date)
        )
    }

    private func scheduleTerrainFetchIfNeeded(for context: UpdateContext) {
        guard context.terrainCacheKey != lastTerrainKey else { return }
        lastTerrainKey = context.terrainCacheKey
        fetchTerrain(latitude: context.latitude, longitude: context.longitude)
    }

    private func apply(_ snapshot: _Snapshot) {
        latitude = snapshot.lat
        currentLST = snapshot.lst
        starPositions = snapshot.starPositions
        sunAltitude = snapshot.sunAltitude
        moonAltitude = snapshot.moonAltitude
        moonAzimuth = snapshot.moonAzimuth
        moonPhase = snapshot.moonPhase
        galacticCenterAltitude = snapshot.galacticCenterAltitude
        galacticCenterAzimuth = snapshot.galacticCenterAzimuth
        constellationLines = snapshot.constellationLines
        constellationLabels = snapshot.constellationLabels
        planetPositions = snapshot.planetPositions
        meteorShowerRadiants = snapshot.meteorShowerRadiants
        milkyWayBandPoints = snapshot.milkyWayBandPoints
    }

    // MARK: - Background Computation

    /// B-V 色指数テーブルをキャッシュ。`StarCatalog.stars` と同じ順序・サイズで、
    /// 初回アクセス時に 1 度だけ計算される (Swift static property は thread-safe)。
    private nonisolated static let _cachedStarColors: [Color] = {
        StarCatalog.stars.map { _starColorForBV($0.colorIndex) }
    }()

    /// バックグラウンドスレッドで安全に実行できる純粋計算。
    /// MainActor の状態を一切参照しない nonisolated な static メソッド。
    private nonisolated static func _compute(
        lat: Double,
        lon: Double,
        jd: Double,
        lst: Double,
        activeMeteorShowers: [MeteorShower]
    ) -> _Snapshot {
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
        let (sunAlt, _) = MilkyWayCalculator.altAzFast(ra: sun.ra, dec: sun.dec,
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
        let bandPoints = _computeMilkyWayBandPoints(cosLat: cosLat, sinLat: sinLat, lst: lst)

        return _Snapshot(lat: lat, lst: lst,
                         starPositions: stars,
                         sunAltitude: sunAlt,
                         moonAltitude: moonAlt, moonAzimuth: moonAz, moonPhase: moon.phase,
                         galacticCenterAltitude: gcAlt, galacticCenterAzimuth: gcAz,
                         constellationLines: constLines, constellationLabels: constLabels,
                         planetPositions: planets, meteorShowerRadiants: meteorRadiants,
                         milkyWayBandPoints: bandPoints)
    }

    /// 天の川バンドの alt/az/halfH を計算して返す (描画には含まない純データ)。
    private nonisolated static func _computeMilkyWayBandPoints(
        cosLat: Double,
        sinLat: Double,
        lst: Double
    ) -> [MilkyWayBandPoint] {
        var result = [MilkyWayBandPoint]()
        let step: Double = 5
        for li in stride(from: 0.0, to: 360.0, by: step) {
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

    /// 星空マップ表示に入る直前に、初期表示位置の再適用を要求する。
    func prepareForStarMapPresentation() {
        shouldApplyInitialPanoramaPose = true
    }

    /// 星空マップ描画領域の最新サイズを記録する。
    func updatePanoramaViewport(size: CGSize) {
        panoramaViewportSize = size
    }

    /// 初回表示時に、地平線が下端付近に来るような仰角を適用する。
    func applyInitialPanoramaPoseIfNeeded() {
        guard shouldApplyInitialPanoramaPose else { return }
        setPanoramaPose(azimuth: 0)
        shouldApplyInitialPanoramaPose = false
    }

    /// 北向きへ戻す。
    func resetToNorth() {
        #if os(iOS)
        viewAzimuth = 0
        viewAltitude = 45
        #else
        setPanoramaPose(azimuth: 0)
        #endif
    }

    /// iOS 用: 初期パノラマポーズフラグをクリアする（心射図法デフォルトでは適用しない）。
    func clearInitialPanoramaPoseFlag() {
        shouldApplyInitialPanoramaPose = false
    }

    /// 選択日へ現在の時刻を反映し、昼間なら当日夕方側の夜へ寄せて表示日時を決める。
    func syncWithSelectedDate(referenceDate: Date = Date()) {
        let selected = appController.selectedDate
        let location = appController.locationController.selectedLocation
        if let date = resolvedPresentationDate(
            for: selected,
            referenceDate: referenceDate,
            location: location
        ) {
            displayDate = date
        }
    }

    func setTimeSliderMinutes(_ minutes: Double) {
        let clampedMinutes = max(0, min(nightDurationMinutes, minutes.rounded()))
        guard abs(timeSliderMinutes - clampedMinutes) > 0.5 else { return }
        timeSliderMinutes = clampedMinutes

        let realMinutes = nightOffsetToRealMinutes(clampedMinutes)
        guard let updatedDate = Self.date(bySettingClockMinutes: realMinutes, on: displayDate) else {
            return
        }

        if isTimeSliderScrubbing {
            pendingTimeSliderDate = updatedDate
            schedulePendingTimeSliderDateCommit()
        } else {
            setDisplayDate(
                updatedDate,
                skipNightRange: true,
                skipTimeSliderSync: true
            )
        }
    }

    var displayTimeString: String {
        let realMinutes = nightOffsetToRealMinutes(timeSliderMinutes)
        return StarMapPresentation.timeString(from: realMinutes)
    }

    private func syncTimeSliderWithDisplayDate() {
        let realMinutes = Self.clockMinutes(for: displayDate)
        let offset = realMinutesToNightOffset(realMinutes)
        guard abs(timeSliderMinutes - offset) > 0.5 else { return }
        timeSliderMinutes = offset
    }

    func beginTimeSliderInteraction() {
        guard !isTimeSliderScrubbing else { return }
        isTimeSliderScrubbing = true
    }

    func endTimeSliderInteraction() {
        guard isTimeSliderScrubbing else { return }
        isTimeSliderScrubbing = false
        timeSliderCommitTask?.cancel()
        timeSliderCommitTask = nil
        commitPendingTimeSliderDate()
    }

    private func schedulePendingTimeSliderDateCommit() {
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastTimeSliderCommitTime
        if elapsed >= Self.timeSliderCommitInterval {
            commitPendingTimeSliderDate()
            return
        }

        timeSliderCommitTask?.cancel()
        let remaining = Self.timeSliderCommitInterval - elapsed
        timeSliderCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.commitPendingTimeSliderDate()
            }
        }
    }

    private func commitPendingTimeSliderDate() {
        guard let date = pendingTimeSliderDate else { return }
        pendingTimeSliderDate = nil
        timeSliderCommitTask?.cancel()
        timeSliderCommitTask = nil
        lastTimeSliderCommitTime = Date.timeIntervalSinceReferenceDate
        setDisplayDate(
            date,
            skipNightRange: true,
            skipTimeSliderSync: true
        )
    }

    private var currentMinUpdateInterval: TimeInterval {
        isTimeSliderScrubbing ? Self.minScrubbingUpdateInterval : Self.minUpdateInterval
    }

    private func setDisplayDate(
        _ date: Date,
        skipNightRange: Bool = false,
        skipTimeSliderSync: Bool = false
    ) {
        displayDateUpdateMode =
            (skipNightRange || skipTimeSliderSync) ? .preserveNightRangeAndSlider : .standard
        displayDate = date
    }

    private func handleDisplayDateChange(from oldDate: Date, to newDate: Date) {
        let updateMode = displayDateUpdateMode
        displayDateUpdateMode = .standard

        let shouldSkipNightRange = updateMode.skipsNightRange || Self.isSameCalendarDay(oldDate, newDate)
        let shouldSkipTimeSliderSync = updateMode.skipsTimeSliderSync

        if !shouldSkipNightRange {
            updateNightRange()
        }

        if !shouldSkipTimeSliderSync {
            syncTimeSliderWithDisplayDate()
        }

        update()
    }

    /// 夜間オフセット (0〜nightDuration) を実際の時刻 (0〜1439) に変換
    private func nightOffsetToRealMinutes(_ offset: Double) -> Double {
        let real = nightStartMinutes + offset
        return real.truncatingRemainder(dividingBy: 1440)
    }

    /// 実際の時刻 (0〜1439) を夜間オフセット (0〜nightDuration) に変換
    private func realMinutesToNightOffset(_ realMinutes: Double) -> Double {
        var offset = realMinutes - nightStartMinutes
        if offset < 0 { offset += 1440 }
        return max(0, min(nightDurationMinutes, offset))
    }

    /// 夜間範囲を現在の日付・場所で再計算
    private func updateNightRange() {
        let location = appController.locationController.selectedLocation
        if let twilight = MilkyWayCalculator.findCivilTwilightMinutes(
            date: displayDate,
            location: location
        ) {
            nightStartMinutes = twilight.eveningMinutes
            var duration = twilight.morningMinutes - twilight.eveningMinutes
            if duration < 0 { duration += 1440 }
            nightDurationMinutes = max(60, duration) // 最低1時間
        }
        // twilight が nil (白夜/極夜) の場合はデフォルト値のまま
    }

    private func setPanoramaPose(azimuth: Double) {
        viewAzimuth = azimuth
        viewAltitude = StarMapLayout.preferredPanoramaAltitude(
            size: panoramaViewportSize,
            fov: fov
        )
    }

    private static func clockMinutes(for date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func isSameCalendarDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    private func resolvedPresentationDate(
        for selectedDate: Date,
        referenceDate: Date,
        location: CLLocationCoordinate2D
    ) -> Date? {
        guard let candidate = Self.date(byApplyingTimeOf: referenceDate, to: selectedDate) else {
            return nil
        }

        guard let twilight = MilkyWayCalculator.findCivilTwilightMinutes(
            date: selectedDate,
            location: location
        ) else {
            return candidate
        }

        let candidateMinutes = Self.clockMinutes(for: candidate)
        if Self.isWithinNightRange(
            candidateMinutes,
            eveningMinutes: twilight.eveningMinutes,
            morningMinutes: twilight.morningMinutes
        ) {
            return candidate
        }

        return Self.date(bySettingClockMinutes: twilight.eveningMinutes, on: selectedDate)
    }

    private static func isWithinNightRange(
        _ clockMinutes: Double,
        eveningMinutes: Double,
        morningMinutes: Double
    ) -> Bool {
        if eveningMinutes <= morningMinutes {
            return clockMinutes >= eveningMinutes && clockMinutes < morningMinutes
        }

        return clockMinutes >= eveningMinutes || clockMinutes < morningMinutes
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

    private static func date(bySettingClockMinutes minutes: Double, on date: Date) -> Date? {
        let normalizedMinutes = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return Calendar.current.date(
            bySettingHour: normalizedMinutes / 60,
            minute: normalizedMinutes % 60,
            second: 0,
            of: date
        )
    }

    nonisolated static func terrainCacheKey(latitude: Double, longitude: Double) -> String {
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
