import Foundation
import CoreLocation
import Combine
import SwiftUI

@MainActor
struct StarMapSettingsDependency {
    let currentDensity: () -> StarDisplayDensity
    let changes: AnyPublisher<StarDisplayDensity, Never>

    static let live = StarMapSettingsDependency(
        currentDensity: {
            StarDisplayDensity.load()
        },
        changes: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in StarDisplayDensity.load() }
            .removeDuplicates()
            .eraseToAnyPublisher()
    )
}

struct StarMapTerrainDependency: Sendable {
    let fetchProfile: @Sendable (_ latitude: Double, _ longitude: Double) async -> TerrainProfile?

    static let live = StarMapTerrainDependency(
        fetchProfile: { latitude, longitude in
            await TerrainService.shared.fetchProfile(latitude: latitude, longitude: longitude)
        }
    )
}

struct StarMapComputationDependency: Sendable {
    let computeSnapshot: @Sendable (
        _ latitude: Double,
        _ longitude: Double,
        _ julianDate: Double,
        _ localSiderealTime: Double,
        _ activeMeteorShowers: [MeteorShower],
        _ density: StarDisplayDensity
    ) async -> StarMapComputation.Snapshot

    static let live = StarMapComputationDependency(
        computeSnapshot: { latitude, longitude, julianDate, localSiderealTime, activeMeteorShowers, density in
            await Task.detached(priority: .userInitiated) {
                StarMapComputation.compute(
                    latitude: latitude,
                    longitude: longitude,
                    julianDate: julianDate,
                    localSiderealTime: localSiderealTime,
                    activeMeteorShowers: activeMeteorShowers,
                    starDisplayDensity: density
                )
            }.value
        }
    )
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
    @Published private(set) var canvasSize: CGSize = .zero

    /// 星空マップシートが表示中か（サイドバーの視野オーバーレイ連動用）
    @Published var isStarMapOpen: Bool = false

    /// 現在の視野方向（サイドバーマップオーバーレイ用）
    var viewingDirection: ViewingDirection {
        ViewingDirection(azimuth: viewAzimuth, fov: fov, isActive: isStarMapOpen)
    }

    // MARK: - Dependencies

    private let appController: AppController
    private let settingsDependency: StarMapSettingsDependency
    private let terrainDependency: StarMapTerrainDependency
    private let computationDependency: StarMapComputationDependency
    private var cancellables: Set<AnyCancellable> = []
    private var shouldApplyInitialPose = true
    private var lastTimeSliderCommitTime: TimeInterval = 0
    private var pendingTimeSliderDate: Date?
    private var timeSliderCommitTask: Task<Void, Never>?
    private var displayDateUpdateMode: DisplayDateUpdateMode = .standard
    private var starDisplayDensity: StarDisplayDensity

    // MARK: - Init

    init(
        appController: AppController,
        settingsDependency: StarMapSettingsDependency? = nil,
        terrainDependency: StarMapTerrainDependency? = nil,
        computationDependency: StarMapComputationDependency? = nil
    ) {
        self.appController = appController
        self.settingsDependency = settingsDependency ?? .live
        self.terrainDependency = terrainDependency ?? .live
        self.computationDependency = computationDependency ?? .live
        self.starDisplayDensity = self.settingsDependency.currentDensity()
        // 場所が変わったら再計算
        appController.locationController.selectedLocationPublisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSelectedLocationChanged()
            }
            .store(in: &cancellables)
        appController.locationController.selectedTimeZonePublisher
            .dropFirst()
            .removeDuplicates { $0.identifier == $1.identifier }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSelectedTimeZoneChanged()
            }
            .store(in: &cancellables)
        self.settingsDependency.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] density in
                self?.applyStarDisplayDensity(density)
            }
            .store(in: &cancellables)
        appController.$selectedDate
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSelectedDateChanged()
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
                self?._executeUpdate()
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
        let density = starDisplayDensity
        updateTask = Task { [weak self] in
            guard let self else { return }

            let snapshot = await computationDependency.computeSnapshot(
                context.latitude,
                context.longitude,
                context.julianDate,
                context.localSiderealTime,
                context.activeMeteorShowers,
                density
            )

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
            activeMeteorShowers: MeteorShowerCatalog.active(
                on: date,
                timeZone: appController.locationController.selectedTimeZone
            )
        )
    }

    func setStarDisplayDensity(_ density: StarDisplayDensity) {
        applyStarDisplayDensity(density)
    }

    private func applyStarDisplayDensity(_ density: StarDisplayDensity) {
        guard density != starDisplayDensity else { return }
        starDisplayDensity = density
        update()
    }

    private func scheduleTerrainFetchIfNeeded(for context: UpdateContext) {
        guard context.terrainCacheKey != lastTerrainKey else { return }
        lastTerrainKey = context.terrainCacheKey
        fetchTerrain(latitude: context.latitude, longitude: context.longitude)
    }

    private func apply(_ snapshot: StarMapComputation.Snapshot) {
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

    private var lastTerrainKey: String = ""
    private var terrainFetchTask: Task<Void, Never>? = nil

    private func fetchTerrain(latitude: Double, longitude: Double) {
        terrainFetchTask?.cancel()
        terrainFetchTask = Task { [weak self] in
            guard let self else { return }
            let profile = await terrainDependency.fetchProfile(latitude, longitude)
            guard !Task.isCancelled else { return }
            terrainProfile = profile
        }
    }

    // MARK: - Meteor Showers

    /// 現在の表示日時でアクティブな流星群
    var activeMeteorShowers: [MeteorShower] {
        MeteorShowerCatalog.active(
            on: displayDate,
            timeZone: appController.locationController.selectedTimeZone
        )
    }

    /// 次の流星群とピークまでの日数
    var nextMeteorShower: (shower: MeteorShower, daysUntilPeak: Int)? {
        MeteorShowerCatalog.next(
            after: displayDate,
            timeZone: appController.locationController.selectedTimeZone
        )
    }

    var observationDate: Date {
        ObservationTimeZone.startOfDay(
            for: appController.selectedDate,
            timeZone: appController.locationController.selectedTimeZone
        )
    }

    /// 太陽が地平線下 (夜間) か
    var isNight: Bool { sunAltitude < 0 }

    /// 天文薄明 (太陽高度 < -18°) 以上の暗さか
    var isAstronomicalDark: Bool { sunAltitude < -18 }

    /// 現在時刻にリセット
    func resetToNow(referenceDate: Date = Date()) {
        syncWithSelectedDate(referenceDate: referenceDate)
    }

    func setObservationDate(_ date: Date) {
        let timeZone = appController.locationController.selectedTimeZone
        let normalizedDate = ObservationTimeZone.startOfDay(for: date, timeZone: timeZone)
        guard !ObservationTimeZone.isDate(
            appController.selectedDate,
            inSameDayAs: normalizedDate,
            timeZone: timeZone
        ) else {
            return
        }
        appController.selectedDate = normalizedDate
        syncWithSelectedDate(referenceDate: displayDate)
    }

    /// 星空マップ表示に入る直前に、初期表示位置の再適用を要求する。
    func prepareForStarMapPresentation() {
        shouldApplyInitialPose = true
    }

    /// 星空マップ描画領域の最新サイズを記録する。
    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    /// 初回表示時に、デフォルト視点（北向き 仰角45°）を適用する。
    func applyInitialPoseIfNeeded() {
        guard shouldApplyInitialPose else { return }
        viewAzimuth = 0
        viewAltitude = StarMapLayout.resetAltitude
        shouldApplyInitialPose = false
    }

    /// 北向きへ戻す。
    func resetToNorth() {
        viewAzimuth = 0
        viewAltitude = StarMapLayout.resetAltitude
    }

    /// 初期ポーズフラグをクリアする（心射図法デフォルトでは適用しない）。
    func clearInitialPoseFlag() {
        shouldApplyInitialPose = false
    }

    /// 選択日へ現在の時刻を反映し、昼間なら当日夕方側の夜へ寄せて表示日時を決める。
    func syncWithSelectedDate(referenceDate: Date = Date()) {
        let selected = appController.selectedDate
        let location = appController.locationController.selectedLocation
        let timeZone = appController.locationController.selectedTimeZone
        updateNightRange()
        if let date = resolvedPresentationDate(
            for: selected,
            referenceDate: referenceDate,
            location: location,
            timeZone: timeZone
        ) {
            displayDate = date
        }
    }

    func setTimeSliderMinutes(_ minutes: Double) {
        let clampedMinutes = max(0, min(nightDurationMinutes, minutes.rounded()))
        guard abs(timeSliderMinutes - clampedMinutes) > 0.5 else { return }
        timeSliderMinutes = clampedMinutes

        let realMinutes = StarMapDateLogic.nightOffsetToRealMinutes(
            clampedMinutes,
            nightStartMinutes: nightStartMinutes
        )
        guard let updatedDate = StarMapDateLogic.date(
            bySettingClockMinutes: realMinutes,
            onObservationDate: appController.selectedDate,
            timeZone: appController.locationController.selectedTimeZone,
            nightStartMinutes: nightStartMinutes
        ) else {
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
        let realMinutes = StarMapDateLogic.nightOffsetToRealMinutes(
            timeSliderMinutes,
            nightStartMinutes: nightStartMinutes
        )
        return StarMapPresentation.timeString(from: realMinutes)
    }

    private func syncTimeSliderWithDisplayDate() {
        let realMinutes = StarMapDateLogic.clockMinutes(
            for: displayDate,
            timeZone: appController.locationController.selectedTimeZone
        )
        let offset = StarMapDateLogic.realMinutesToNightOffset(
            realMinutes,
            nightStartMinutes: nightStartMinutes,
            nightDurationMinutes: nightDurationMinutes
        )
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
            self?.commitPendingTimeSliderDate()
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

    private func handleSelectedTimeZoneChanged() {
        syncWithSelectedDate(referenceDate: displayDate)
    }

    private func handleSelectedLocationChanged() {
        syncWithSelectedDate(referenceDate: displayDate)
    }

    private func handleSelectedDateChanged() {
        let timeZone = appController.locationController.selectedTimeZone
        let currentObservationDate = StarMapDateLogic.observationDate(
            for: displayDate,
            timeZone: timeZone,
            nightStartMinutes: nightStartMinutes
        )
        guard !ObservationTimeZone.isDate(
            currentObservationDate,
            inSameDayAs: appController.selectedDate,
            timeZone: timeZone
        ) else {
            return
        }
        syncWithSelectedDate(referenceDate: displayDate)
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

        let shouldSkipTimeSliderSync = updateMode.skipsTimeSliderSync

        if !shouldSkipTimeSliderSync {
            syncTimeSliderWithDisplayDate()
        }

        update()
    }

    /// 夜間範囲を現在の日付・場所で再計算
    private func updateNightRange() {
        let location = appController.locationController.selectedLocation
        let observationDate = appController.selectedDate
        let fallback = StarMapDateLogic.NightRange(
            startMinutes: nightStartMinutes,
            durationMinutes: nightDurationMinutes
        )
        let range = StarMapDateLogic.nightRange(
            for: observationDate,
            location: location,
            timeZone: appController.locationController.selectedTimeZone,
            fallback: fallback
        )
        nightStartMinutes = range.startMinutes
        nightDurationMinutes = range.durationMinutes
    }

    private func resolvedPresentationDate(
        for selectedDate: Date,
        referenceDate: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        StarMapDateLogic.resolvedPresentationDate(
            for: selectedDate,
            referenceDate: referenceDate,
            location: location,
            timeZone: timeZone
        )
    }

    nonisolated static func terrainCacheKey(latitude: Double, longitude: Double) -> String {
        let roundedLatitude = (latitude * 100).rounded() / 100
        let roundedLongitude = (longitude * 100).rounded() / 100
        return "\(roundedLatitude),\(roundedLongitude)"
    }
}

extension StarPosition: Identifiable {
    /// 赤経・赤緯の組み合わせで一意に識別する
    public var id: String { "\(star.ra)-\(star.dec)" }
}
