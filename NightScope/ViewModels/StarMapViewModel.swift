import Foundation
import CoreLocation
import Combine
import SwiftUI

@MainActor
struct StarMapSettingsDependency {
    let currentSettings: () -> StarMapDisplaySettings
    let changes: AnyPublisher<StarMapDisplaySettings, Never>

    static let live = StarMapSettingsDependency(
        currentSettings: {
            StarMapDisplaySettings.load()
        },
        changes: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in StarMapDisplaySettings.load() }
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

enum StarMapTerrainFetchState: Equatable {
    case idle
    case loading
    case available
    case unavailable

    var statusText: String {
        switch self {
        case .idle:
            L10n.tr("地形: 待機中")
        case .loading:
            L10n.tr("地形: 読込中")
        case .available:
            L10n.tr("地形: 有効")
        case .unavailable:
            L10n.tr("地形: 未取得")
        }
    }

    var systemImageName: String {
        switch self {
        case .idle, .loading:
            "hourglass"
        case .available:
            "mountain.2"
        case .unavailable:
            "exclamationmark.triangle"
        }
    }
}

enum StarMapScreenOrientation: Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    var isLandscape: Bool {
        switch self {
        case .landscapeLeft, .landscapeRight:
            true
        case .portrait, .portraitUpsideDown:
            false
        }
    }

    var screenUpDeviceVector: (x: Double, y: Double, z: Double) {
        switch self {
        case .portrait:
            (x: 0, y: 1, z: 0)
        case .portraitUpsideDown:
            (x: 0, y: -1, z: 0)
        case .landscapeLeft:
            (x: -1, y: 0, z: 0)
        case .landscapeRight:
            (x: 1, y: 0, z: 0)
        }
    }
}

struct StarMapCameraFieldOfView: Equatable, Sendable {
    let diagonalDegrees: Double
    let sensorWidth: Int32
    let sensorHeight: Int32

    private var sensorAspectRatio: Double? {
        guard sensorWidth > 0, sensorHeight > 0 else { return nil }
        return Double(sensorWidth) / Double(sensorHeight)
    }

    private var landscapeHorizontalDegrees: Double? {
        degreesForAxis(multiplier: sensorAspectRatio)
    }

    private var landscapeVerticalDegrees: Double? {
        guard let sensorAspectRatio else { return nil }
        return degreesForAxis(multiplier: 1.0 / sensorAspectRatio)
    }

    func visibleHorizontalDegrees(
        viewportSize: CGSize,
        screenOrientation: StarMapScreenOrientation
    ) -> Double? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        guard let sensorAspectRatio,
              let landscapeHorizontalDegrees,
              let landscapeVerticalDegrees else {
            return nil
        }

        let viewportAspectRatio = viewportSize.width / viewportSize.height
        let contentAspectRatio = screenOrientation.isLandscape
            ? sensorAspectRatio
            : 1.0 / sensorAspectRatio
        let contentHorizontalDegrees = screenOrientation.isLandscape
            ? landscapeHorizontalDegrees
            : landscapeVerticalDegrees
        let contentVerticalDegrees = screenOrientation.isLandscape
            ? landscapeVerticalDegrees
            : landscapeHorizontalDegrees

        if viewportAspectRatio >= contentAspectRatio {
            return contentHorizontalDegrees
        }

        let visibleHalfHorizontalRadians = atan(
            tan(contentVerticalDegrees * .pi / 360) * viewportAspectRatio
        )
        return visibleHalfHorizontalRadians * 360 / .pi
    }

    private func degreesForAxis(multiplier: Double?) -> Double? {
        guard let multiplier else { return nil }
        let halfDiagonalRadians = diagonalDegrees * .pi / 360
        let base = tan(halfDiagonalRadians) / sqrt(multiplier * multiplier + 1)
        return atan(multiplier * base) * 360 / .pi
    }
}

struct StarMapCameraSessionState: Equatable, Sendable {
    let isGyroMode: Bool
    let isBackgroundEnabled: Bool
    let isAuthorized: Bool
    let hasCameraHardware: Bool
    let isSceneActive: Bool

    var shouldKeepPreviewAttached: Bool {
        isGyroMode && isAuthorized && hasCameraHardware
    }

    var isCameraBackgroundVisible: Bool {
        isGyroMode && isBackgroundEnabled && isAuthorized && hasCameraHardware
    }

    var shouldRunSession: Bool {
        isSceneActive && isCameraBackgroundVisible
    }
}

enum StarMapCameraPreviewRotation {
    static func fallbackAngle(for screenOrientation: StarMapScreenOrientation) -> CGFloat {
        switch screenOrientation {
        case .portrait:
            90
        case .portraitUpsideDown:
            270
        case .landscapeLeft:
            180
        case .landscapeRight:
            0
        }
    }
}

struct StarMapCameraSessionActivationState: Sendable {
    private(set) var generation: UInt = 0
    private(set) var isActive = false

    @discardableResult
    mutating func update(isActive: Bool) -> UInt {
        generation &+= 1
        self.isActive = isActive
        return generation
    }

    func matches(generation: UInt, isActive: Bool) -> Bool {
        self.generation == generation && self.isActive == isActive
    }
}

struct StarMapMotionMatrix {
    let m11: Double
    let m12: Double
    let m13: Double
    let m21: Double
    let m22: Double
    let m23: Double
    let m31: Double
    let m32: Double
    let m33: Double

    func referenceVector(forDeviceVectorX x: Double, y: Double, z: Double) -> (east: Double, north: Double, up: Double) {
        // Core Motion の xTrueNorth / xMagneticNorth 系は基準座標が north-west-up なので、
        // 画面描画で使う east-north-up に変換してから扱う。
        let north = (m11 * x) + (m21 * y) + (m31 * z)
        let west = (m12 * x) + (m22 * y) + (m32 * z)

        return (
            east: -west,
            north: north,
            up: (m13 * x) + (m23 * y) + (m33 * z)
        )
    }

    func referenceVector(forDeviceVector vector: (x: Double, y: Double, z: Double)) -> (east: Double, north: Double, up: Double) {
        referenceVector(forDeviceVectorX: vector.x, y: vector.y, z: vector.z)
    }
}

struct StarMapMotionPose: Equatable {
    let azimuth: Double
    let altitude: Double
    let roll: Double

    init(azimuth: Double, altitude: Double, roll: Double = 0) {
        self.azimuth = Self.normalizedAzimuth(azimuth)
        self.altitude = Self.clampedAltitude(altitude)
        self.roll = Self.normalizedRoll(roll)
    }

    static func make(
        rotationMatrix: StarMapMotionMatrix,
        screenOrientation: StarMapScreenOrientation = .portrait
    ) -> Self {
        let lookingVector = rotationMatrix.referenceVector(forDeviceVectorX: 0, y: 0, z: -1)
        let screenUpVector = rotationMatrix.referenceVector(forDeviceVector: screenOrientation.screenUpDeviceVector)
        let azimuth = normalizedAzimuth(atan2(lookingVector.east, lookingVector.north) * 180 / .pi)
        let altitude = atan2(
            lookingVector.up,
            hypot(lookingVector.east, lookingVector.north)
        ) * 180 / .pi
        let azimuthRadians = azimuth * .pi / 180
        let forward = normalizedVector(lookingVector)
        let right = (
            east: cos(azimuthRadians),
            north: -sin(azimuthRadians),
            up: 0.0
        )
        let defaultUp = normalizedVector(cross(right, forward))
        let projectedScreenUp = normalizedVector(projectedOntoPlane(screenUpVector, normal: forward))
        let roll = atan2(
            dot(projectedScreenUp, right),
            dot(projectedScreenUp, defaultUp)
        ) * 180 / .pi

        return Self(azimuth: azimuth, altitude: altitude, roll: roll)
    }

    static func smoothed(previous: Self?, next: Self) -> Self {
        guard let previous else { return next }

        let azimuthDelta = wrappedAzimuthDelta(from: previous.azimuth, to: next.azimuth)
        let altitudeDelta = next.altitude - previous.altitude
        let rollDelta = wrappedSignedAngleDelta(from: previous.roll, to: next.roll)
        let azimuthFactor = smoothingFactor(for: abs(azimuthDelta), threshold: 12, base: 0.18, boosted: 0.34)
        let altitudeFactor = smoothingFactor(for: abs(altitudeDelta), threshold: 10, base: 0.18, boosted: 0.30)
        let rollFactor = smoothingFactor(for: abs(rollDelta), threshold: 15, base: 0.20, boosted: 0.36)

        return Self(
            azimuth: previous.azimuth + (azimuthDelta * azimuthFactor),
            altitude: previous.altitude + (altitudeDelta * altitudeFactor),
            roll: previous.roll + (rollDelta * rollFactor)
        )
    }

    static func normalizedAzimuth(_ azimuth: Double) -> Double {
        let normalized = azimuth.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    static func normalizedRoll(_ roll: Double) -> Double {
        let normalized = normalizedAzimuth(roll)
        return normalized > 180 ? normalized - 360 : normalized
    }

    private static func clampedAltitude(_ altitude: Double) -> Double {
        clamp(altitude, min: -10, max: 90)
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func smoothingFactor(
        for deltaMagnitude: Double,
        threshold: Double,
        base: Double,
        boosted: Double
    ) -> Double {
        deltaMagnitude >= threshold ? boosted : base
    }

    private static func wrappedAzimuthDelta(from source: Double, to target: Double) -> Double {
        let rawDelta = normalizedAzimuth(target) - normalizedAzimuth(source)

        if rawDelta > 180 {
            return rawDelta - 360
        }
        if rawDelta < -180 {
            return rawDelta + 360
        }

        return rawDelta
    }

    private static func wrappedSignedAngleDelta(from source: Double, to target: Double) -> Double {
        normalizedRoll(target - source)
    }

    private static func normalizedVector(
        _ vector: (east: Double, north: Double, up: Double)
    ) -> (east: Double, north: Double, up: Double) {
        let length = sqrt(vector.east * vector.east + vector.north * vector.north + vector.up * vector.up)
        guard length > 1e-10 else {
            return (east: 0, north: 0, up: 1)
        }
        return (
            east: vector.east / length,
            north: vector.north / length,
            up: vector.up / length
        )
    }

    private static func projectedOntoPlane(
        _ vector: (east: Double, north: Double, up: Double),
        normal: (east: Double, north: Double, up: Double)
    ) -> (east: Double, north: Double, up: Double) {
        let projection = dot(vector, normal)
        return (
            east: vector.east - normal.east * projection,
            north: vector.north - normal.north * projection,
            up: vector.up - normal.up * projection
        )
    }

    private static func cross(
        _ lhs: (east: Double, north: Double, up: Double),
        _ rhs: (east: Double, north: Double, up: Double)
    ) -> (east: Double, north: Double, up: Double) {
        (
            east: lhs.north * rhs.up - lhs.up * rhs.north,
            north: lhs.up * rhs.east - lhs.east * rhs.up,
            up: lhs.east * rhs.north - lhs.north * rhs.east
        )
    }

    private static func dot(
        _ lhs: (east: Double, north: Double, up: Double),
        _ rhs: (east: Double, north: Double, up: Double)
    ) -> Double {
        lhs.east * rhs.east + lhs.north * rhs.north + lhs.up * rhs.up
    }
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
    @Published private(set) var terrainFetchState: StarMapTerrainFetchState = .idle
    @Published private(set) var showsConstellationLines: Bool = StarMapDisplaySettings.defaultValue.showsConstellationLines
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

    /// 夜間開始時刻 (分, 0-1439) — 日没 (太陽高度 0°) 基準
    @Published private(set) var nightStartMinutes: Double = 1080  // デフォルト 18:00
    /// 夜間の長さ (分)
    @Published private(set) var nightDurationMinutes: Double = 600 // デフォルト 10時間

    // MARK: - View direction (full-sky planisphere rotation or gyro center)

    /// 画面中心が向く方位角 (度, 0=北, 時計回り)。パノラマモードでは中央の方位
    @Published var viewAzimuth: Double = 0   // 初期値=北向き

    /// 画面中心の仰角 (度, 0=地平線, 90=天頂)。ジャイロモードで使用
    @Published var viewAltitude: Double = 45

    /// 画面のロール角 (度)。ジャイロモード時のみ投影へ反映する
    @Published var viewRoll: Double = 0

    /// ジャイロモードの有効/無効 (iPhone のみ true にする)
    @Published var isGyroMode: Bool = false

    /// 水平視野角 (度): 30°〜150°, デフォルト 60°
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
    private var hasPreparedInitialPresentation = false
    private var lastTimeSliderCommitTime: TimeInterval = 0
    private var pendingTimeSliderDate: Date?
    private var timeSliderCommitTask: Task<Void, Never>?
    private var displayDateUpdateMode: DisplayDateUpdateMode = .standard
    private var starMapDisplaySettings: StarMapDisplaySettings
    private var starDisplayDensity: StarDisplayDensity

    // MARK: - Init

    init(
        appController: AppController,
        settingsDependency: StarMapSettingsDependency? = nil,
        terrainDependency: StarMapTerrainDependency? = nil,
        computationDependency: StarMapComputationDependency? = nil
    ) {
        let resolvedSettingsDependency = settingsDependency ?? .live
        let initialDisplaySettings = resolvedSettingsDependency.currentSettings()
        self.appController = appController
        self.settingsDependency = resolvedSettingsDependency
        self.terrainDependency = terrainDependency ?? .live
        self.computationDependency = computationDependency ?? .live
        self.starMapDisplaySettings = initialDisplaySettings
        self.starDisplayDensity = initialDisplaySettings.density
        self.showsConstellationLines = initialDisplaySettings.showsConstellationLines
        setupBindings()
        updateNightRange(referenceDate: displayDate)
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

    private struct ObservationContext {
        let selectedDate: Date
        let location: CLLocationCoordinate2D
        let timeZone: TimeZone
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

    private var selectedLocation: CLLocationCoordinate2D {
        appController.locationController.selectedLocation
    }

    private var selectedTimeZone: TimeZone {
        appController.locationController.selectedTimeZone
    }

    private var observationContext: ObservationContext {
        ObservationContext(
            selectedDate: appController.selectedDate,
            location: selectedLocation,
            timeZone: selectedTimeZone
        )
    }

    private func setupBindings() {
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

        settingsDependency.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.applyStarMapDisplaySettings(settings)
            }
            .store(in: &cancellables)

        appController.$selectedDate
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSelectedDateChanged()
            }
            .store(in: &cancellables)
    }

    private func makeUpdateContext() -> UpdateContext {
        let context = observationContext
        let date = displayDate
        let julianDate = MilkyWayCalculator.julianDate(from: date)

        return UpdateContext(
            latitude: context.location.latitude,
            longitude: context.location.longitude,
            julianDate: julianDate,
            localSiderealTime: MilkyWayCalculator.localSiderealTime(
                jd: julianDate,
                longitude: context.location.longitude
            ),
            activeMeteorShowers: MeteorShowerCatalog.active(
                on: date,
                timeZone: context.timeZone
            )
        )
    }

    /// 表示する恒星密度を切り替え、必要な再計算を要求します。
    func setStarDisplayDensity(_ density: StarDisplayDensity) {
        applyStarMapDisplaySettings(
            StarMapDisplaySettings(
                density: density,
                showsConstellationLines: starMapDisplaySettings.showsConstellationLines
            )
        )
    }

    /// 星座線表示を切り替えます。
    func setShowsConstellationLines(_ showsConstellationLines: Bool) {
        applyStarMapDisplaySettings(
            StarMapDisplaySettings(
                density: starMapDisplaySettings.density,
                showsConstellationLines: showsConstellationLines
            )
        )
    }

    var displaySettings: StarMapDisplaySettings {
        starMapDisplaySettings
    }

    private func applyStarMapDisplaySettings(_ settings: StarMapDisplaySettings) {
        guard settings != starMapDisplaySettings else { return }

        let densityChanged = settings.density != starMapDisplaySettings.density
        let constellationLinesChanged =
            settings.showsConstellationLines != starMapDisplaySettings.showsConstellationLines

        starMapDisplaySettings = settings
        starDisplayDensity = settings.density

        if constellationLinesChanged {
            showsConstellationLines = settings.showsConstellationLines
        }

        if densityChanged {
            update()
        }
    }

    private func scheduleTerrainFetchIfNeeded(for context: UpdateContext) {
        guard context.terrainCacheKey != lastTerrainKey else { return }
        lastTerrainKey = context.terrainCacheKey
        terrainProfile = nil
        terrainFetchState = .loading
        fetchTerrain(
            latitude: context.latitude,
            longitude: context.longitude,
            terrainKey: context.terrainCacheKey
        )
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

    private func fetchTerrain(latitude: Double, longitude: Double, terrainKey: String) {
        terrainFetchTask?.cancel()
        terrainFetchTask = Task { [weak self] in
            guard let self else { return }
            let profile = await terrainDependency.fetchProfile(latitude, longitude)
            guard !Task.isCancelled else { return }
            guard terrainKey == lastTerrainKey else { return }
            terrainProfile = profile
            terrainFetchState = profile == nil ? .unavailable : .available
        }
    }

    // MARK: - Meteor Showers

    /// 現在の表示日時でアクティブな流星群
    var activeMeteorShowers: [MeteorShower] {
        MeteorShowerCatalog.active(
            on: displayDate,
            timeZone: selectedTimeZone
        )
    }

    /// 次の流星群とピークまでの日数
    var nextMeteorShower: (shower: MeteorShower, daysUntilPeak: Int)? {
        MeteorShowerCatalog.next(
            after: displayDate,
            timeZone: selectedTimeZone
        )
    }

    /// 現在の表示が属する観測日の開始時刻です。
    var observationDate: Date {
        ObservationTimeZone.startOfDay(
            for: appController.selectedDate,
            timeZone: selectedTimeZone
        )
    }

    /// 太陽が地平線下 (夜間) か
    var isNight: Bool { sunAltitude < 0 }

    /// 天文薄明 (太陽高度 < -18°) 以上の暗さか
    var isAstronomicalDark: Bool { sunAltitude < -18 }

    /// 現在の観測日と時刻にリセット
    func resetToNow(referenceDate: Date = Date()) {
        appController.selectObservationDate(referenceDate, timeZone: selectedTimeZone)
        syncWithSelectedDate(referenceDate: referenceDate)
    }

    /// 表示中の夜時刻をできるだけ保ったまま観測日を切り替えます。
    func setObservationDate(_ date: Date) {
        let timeZone = selectedTimeZone
        let normalizedDate = ObservationTimeZone.startOfDay(for: date, timeZone: timeZone)
        guard !ObservationTimeZone.isDate(
            appController.selectedDate,
            inSameDayAs: normalizedDate,
            timeZone: timeZone
        ) else {
            return
        }
        appController.selectObservationDate(normalizedDate, timeZone: timeZone)
        syncWithSelectedDate(referenceDate: displayDate)
    }

    /// 星空マップ表示に入る直前に、初期表示位置の再適用を要求する。
    func prepareForStarMapPresentation() {
        guard !hasPreparedInitialPresentation else { return }
        hasPreparedInitialPresentation = true
        shouldApplyInitialPose = true
    }

    /// 星空マップの初回表示に必要な初期化を一度だけ実行する。
    func activatePresentationIfNeeded(referenceDate: Date = Date()) {
        guard !hasPreparedInitialPresentation else { return }
        prepareForStarMapPresentation()
        syncWithSelectedDate(referenceDate: referenceDate)
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
        viewRoll = 0
        shouldApplyInitialPose = false
    }

    /// 北向きへ戻す。
    func resetToNorth() {
        viewAzimuth = 0
        viewAltitude = StarMapLayout.resetAltitude
        viewRoll = 0
    }

    /// 初期ポーズフラグをクリアする（心射図法デフォルトでは適用しない）。
    func clearInitialPoseFlag() {
        shouldApplyInitialPose = false
    }

    /// 選択日へ現在の時刻を反映し、昼間なら当日夕方側の夜へ寄せて表示日時を決める。
    func syncWithSelectedDate(referenceDate: Date = Date()) {
        let context = observationContext
        updateNightRange(referenceDate: referenceDate)
        if let date = resolvedPresentationDate(
            for: context.selectedDate,
            referenceDate: referenceDate,
            location: context.location,
            timeZone: context.timeZone
        ) {
            displayDate = date
        }
    }

    /// 夜間スライダーの値を表示日時へ反映します。
    func setTimeSliderMinutes(_ minutes: Double) {
        let clampedMinutes = max(0, min(timeSliderMaximumMinutes, minutes.rounded()))
        guard abs(timeSliderMinutes - clampedMinutes) > 0.5 else { return }
        timeSliderMinutes = clampedMinutes

        guard let updatedDate = makeDisplayDate(forTimeSliderMinutes: clampedMinutes) else {
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

    /// 夜間スライダーに対応する表示用時刻文字列です。
    var displayTimeString: String {
        let realMinutes = StarMapDateLogic.nightOffsetToRealMinutes(
            timeSliderMinutes,
            nightStartMinutes: nightStartMinutes
        )
        return StarMapPresentation.timeString(from: realMinutes)
    }

    var timeSliderMaximumMinutes: Double {
        StarMapDateLogic.maxSelectableNightOffset(nightDurationMinutes: nightDurationMinutes)
    }

    private func syncTimeSliderWithDisplayDate() {
        let context = observationContext
        let realMinutes = StarMapDateLogic.clockMinutes(
            for: displayDate,
            timeZone: context.timeZone
        )
        let offset = StarMapDateLogic.realMinutesToNightOffset(
            realMinutes,
            nightStartMinutes: nightStartMinutes,
            nightDurationMinutes: nightDurationMinutes
        )
        guard abs(timeSliderMinutes - offset) > 0.5 else { return }
        timeSliderMinutes = offset
    }

    /// スライダー編集中の更新頻度へ切り替えます。
    func beginTimeSliderInteraction() {
        guard !isTimeSliderScrubbing else { return }
        isTimeSliderScrubbing = true
    }

    /// 保留中の日時反映をコミットして通常更新へ戻します。
    func endTimeSliderInteraction() {
        guard isTimeSliderScrubbing else { return }
        isTimeSliderScrubbing = false
        cancelTimeSliderCommitTask()
        commitPendingTimeSliderDate()
    }

    func finalizeTransientInteractionState() {
        if isTimeSliderScrubbing {
            endTimeSliderInteraction()
        } else {
            commitPendingTimeSliderDate()
        }
    }

    private func schedulePendingTimeSliderDateCommit() {
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastTimeSliderCommitTime
        if elapsed >= Self.timeSliderCommitInterval {
            commitPendingTimeSliderDate()
            return
        }

        cancelTimeSliderCommitTask()
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
        cancelTimeSliderCommitTask()
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
        resyncAfterSelectionChange()
    }

    private func handleSelectedLocationChanged() {
        resyncAfterSelectionChange()
    }

    private func handleSelectedDateChanged() {
        discardPendingTimeSliderDate()
        let timeZone = selectedTimeZone
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

    private func discardPendingTimeSliderDate() {
        pendingTimeSliderDate = nil
        cancelTimeSliderCommitTask()
    }

    private func cancelTimeSliderCommitTask() {
        timeSliderCommitTask?.cancel()
        timeSliderCommitTask = nil
    }

    private func resyncAfterSelectionChange() {
        discardPendingTimeSliderDate()
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
    private func updateNightRange(referenceDate: Date) {
        let context = observationContext
        let fallback = StarMapDateLogic.NightRange(
            startMinutes: nightStartMinutes,
            durationMinutes: nightDurationMinutes
        )
        let range = StarMapDateLogic.nightRange(
            for: context.selectedDate,
            location: context.location,
            timeZone: context.timeZone,
            referenceDate: referenceDate,
            fallback: fallback
        )
        nightStartMinutes = range.startMinutes
        nightDurationMinutes = range.durationMinutes
    }

    /// 夜間スライダーのオフセットを、現在の観測日に属する実際の表示日時へ変換します。
    private func makeDisplayDate(forTimeSliderMinutes minutes: Double) -> Date? {
        let context = observationContext
        let realMinutes = StarMapDateLogic.nightOffsetToRealMinutes(
            minutes,
            nightStartMinutes: nightStartMinutes
        )
        return StarMapDateLogic.date(
            bySettingClockMinutes: realMinutes,
            onObservationDate: context.selectedDate,
            timeZone: context.timeZone,
            nightStartMinutes: nightStartMinutes
        )
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
        TerrainService.cacheKey(latitude: latitude, longitude: longitude)
    }
}

extension StarPosition: Identifiable {
    /// 赤経・赤緯の組み合わせで一意に識別する
    public var id: String { "\(star.ra)-\(star.dec)" }
}
