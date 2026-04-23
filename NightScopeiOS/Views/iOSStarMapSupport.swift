import SwiftUI
@preconcurrency import AVFoundation
import CoreMedia
import CoreMotion
import UIKit

struct iOSStarMapControlState {
    let displaySettings: StarMapDisplaySettings
    let canEnableGyroMode: Bool
    let isGyroMode: Bool
    let isCameraBackgroundVisible: Bool
    let canToggleCameraBackground: Bool
    let cameraButtonHelpText: String
    let cameraButtonHintText: String
    let displayedCameraNotice: CameraNotice?
}

struct iOSStarMapHeaderOverlay: View {
    let controlState: iOSStarMapControlState
    let onOpenDisplaySettings: () -> Void
    let onToggleCameraBackground: () -> Void
    let onToggleGyroMode: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            iOSTabHeaderView(
                title: "星空",
                titleColor: .white,
                subtitleColor: .white.opacity(0.75),
                horizontalPadding: Spacing.xs
            ) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                    Text("星空を表示")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } trailing: {
                HStack(spacing: Spacing.xs / 2) {
                    displaySettingsButton
                    cameraBackgroundButton
                    gyroToggleButton
                }
            }

            if let notice = controlState.displayedCameraNotice {
                iOSStarMapNoticeCard(notice: notice, onOpenSettings: onOpenSettings)
            }
        }
    }

    private var displaySettingsButton: some View {
        Button(action: onOpenDisplaySettings) {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .help(L10n.tr("星空の表示設定を開く"))
        .accessibilityLabel(L10n.tr("星空の表示設定"))
        .accessibilityValue(
            L10n.format(
                "星の表示数 %@、星座線 %@、星座名 %@、惑星 %@、流星群 %@、天の川 %@",
                controlState.displaySettings.density.title,
                controlState.displaySettings.showsConstellationLines ? L10n.tr("オン") : L10n.tr("オフ"),
                controlState.displaySettings.showsConstellationLabels ? L10n.tr("オン") : L10n.tr("オフ"),
                controlState.displaySettings.showsPlanets ? L10n.tr("オン") : L10n.tr("オフ"),
                controlState.displaySettings.showsMeteorShowers ? L10n.tr("オン") : L10n.tr("オフ"),
                controlState.displaySettings.showsMilkyWay ? L10n.tr("オン") : L10n.tr("オフ")
            )
        )
        .accessibilityHint(L10n.tr("星の表示数や星図レイヤーの表示を変更します"))
    }

    private var cameraBackgroundButton: some View {
        Button(action: onToggleCameraBackground) {
            toggleIcon(
                systemName: controlState.isCameraBackgroundVisible ? "camera.fill" : "camera",
                isActive: controlState.isCameraBackgroundVisible
            )
        }
        .buttonStyle(.glass)
        .help(controlState.cameraButtonHelpText)
        .accessibilityLabel(
            controlState.isCameraBackgroundVisible
                ? L10n.tr("カメラ背景をオフにする")
                : L10n.tr("カメラ背景をオンにする")
        )
        .accessibilityValue(controlState.isCameraBackgroundVisible ? L10n.tr("オン") : L10n.tr("オフ"))
        .accessibilityHint(controlState.cameraButtonHintText)
        .disabled(!controlState.canToggleCameraBackground)
    }

    private var gyroToggleButton: some View {
        Button(action: onToggleGyroMode) {
            toggleIcon(
                systemName: controlState.isGyroMode ? "gyroscope" : "hand.draw",
                isActive: controlState.isGyroMode
            )
        }
        .buttonStyle(.glass)
        .help(controlState.isGyroMode ? L10n.tr("タッチ操作に切替") : L10n.tr("ジャイロ操作に切替"))
        .accessibilityLabel(
            controlState.isGyroMode
                ? L10n.tr("タッチ操作に切り替える")
                : L10n.tr("ジャイロ操作に切り替える")
        )
        .disabled(!controlState.canEnableGyroMode)
    }

    @ViewBuilder
    private func toggleIcon(systemName: String, isActive: Bool) -> some View {
        let icon = Image(systemName: systemName)
            .font(.headline)
            .frame(width: 44, height: 44)

        if reduceMotion {
            icon
        } else {
            icon.symbolEffect(.bounce, value: isActive)
        }
    }
}

struct iOSStarMapDisplaySettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                StarMapDisplaySettingsSection()
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.tr("星空の表示設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完了")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct iOSStarMapNoticeCard: View {
    let notice: CameraNotice
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(notice.title, systemImage: notice.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            if notice.showsSettingsButton {
                Button(L10n.tr("設定を開く"), action: onOpenSettings)
                    .buttonStyle(.glass)
                    .accessibilityHint(L10n.tr("NightScope の設定画面を開きます"))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .iOSMaterialPanel(
            material: .ultraThinMaterial,
            cornerRadius: Layout.cardCornerRadius,
            showsBorder: false
        )
    }
}

struct CameraNotice: Equatable {
    let symbolName: String
    let title: String
    let message: String
    let showsSettingsButton: Bool

    static let cameraUnavailable = CameraNotice(
        symbolName: "camera.slash",
        title: L10n.tr("カメラ背景を利用できません"),
        message: L10n.tr("この環境では背面カメラを利用できないため、星空マップの通常背景を表示しています。"),
        showsSettingsButton: false
    )

    static let cameraRestricted = CameraNotice(
        symbolName: "hand.raised.fill",
        title: L10n.tr("カメラの使用が制限されています"),
        message: L10n.tr("スクリーンタイムやデバイス設定の制限により、この機能は利用できません。"),
        showsSettingsButton: false
    )

    static let cameraPermissionDenied = CameraNotice(
        symbolName: "camera.badge.ellipsis",
        title: L10n.tr("カメラのアクセスが必要です"),
        message: L10n.tr("ジャイロモード中に実景と星図を重ねるには、設定から NightScope のカメラアクセスを許可してください。"),
        showsSettingsButton: true
    )

    static func cameraUnexpectedFailure(_ message: String) -> CameraNotice {
        CameraNotice(
            symbolName: "exclamationmark.triangle.fill",
            title: L10n.tr("カメラを開始できませんでした"),
            message: message,
            showsSettingsButton: false
        )
    }
}

@MainActor
final class StarMapMotionController: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastPose: StarMapMotionPose?
    private var screenOrientation: StarMapScreenOrientation = .portrait

    var canEnableGyroMode: Bool {
        motionManager.isDeviceMotionAvailable && preferredReferenceFrame != nil
    }

    private var preferredReferenceFrame: CMAttitudeReferenceFrame? {
        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()

        if availableFrames.contains(.xTrueNorthZVertical) {
            return .xTrueNorthZVertical
        }
        if availableFrames.contains(.xMagneticNorthZVertical) {
            return .xMagneticNorthZVertical
        }

        return nil
    }

    func start(
        onPoseUpdate: @escaping (StarMapMotionPose) -> Void,
        onFailure: @escaping () -> Void
    ) {
        guard let referenceFrame = preferredReferenceFrame, motionManager.isDeviceMotionAvailable else {
            onFailure()
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }

        lastPose = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 45
        motionManager.startDeviceMotionUpdates(
            using: referenceFrame,
            to: .main
        ) { [weak self] motion, error in
            guard let self else { return }

            if error != nil {
                self.stop()
                onFailure()
                return
            }

            guard let motion else { return }

            let rawPose = StarMapMotionPose.make(
                rotationMatrix: StarMapMotionMatrix(rotationMatrix: motion.attitude.rotationMatrix),
                screenOrientation: self.screenOrientation
            )
            let smoothedPose = StarMapMotionPose.smoothed(previous: self.lastPose, next: rawPose)
            self.lastPose = smoothedPose
            onPoseUpdate(smoothedPose)
        }
    }

    func updateScreenOrientation(_ screenOrientation: StarMapScreenOrientation) {
        self.screenOrientation = screenOrientation
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        lastPose = nil
    }
}

@MainActor
final class StarMapCameraController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var hasCameraHardware: Bool
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var cameraFieldOfView: StarMapCameraFieldOfView?

    let session = AVCaptureSession()
    var previewDevice: AVCaptureDevice? { Self.currentBackCameraDevice() }

    private let sessionQueue = DispatchQueue(label: "NightScope.StarMapCameraSession")
    private let activationStateQueue = DispatchQueue(
        label: "NightScope.StarMapCameraSessionActivation"
    )
    nonisolated(unsafe) private var activationState = StarMapCameraSessionActivationState()
    private var hasConfiguredSession = false
    private var isConfiguringSession = false

    override init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraHardware = Self.currentBackCameraDevice() != nil
        cameraFieldOfView = Self.currentCameraFieldOfView()
        super.init()
        observeSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraHardware = Self.currentBackCameraDevice() != nil
        cameraFieldOfView = Self.currentCameraFieldOfView()
    }

    func requestAccess() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = currentStatus

        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func setSessionActive(_ isActive: Bool) {
        let shouldActivateSession = isActive
            && hasCameraHardware
            && authorizationStatus == .authorized
        let activationGeneration = updateActivationState(
            isActive: shouldActivateSession
        )

        if shouldActivateSession {
            ensureSessionConfigured()
        } else {
            stopSessionIfNeeded(for: activationGeneration)
        }
    }

    private func ensureSessionConfigured() {
        if hasConfiguredSession {
            requestSessionStartIfNeeded()
            return
        }
        guard !isConfiguringSession else { return }
        isConfiguringSession = true

        let session = session
        sessionQueue.async {
            guard let device = Self.currentBackCameraDevice() else {
                Task { @MainActor in
                    self.hasCameraHardware = false
                    self.hasConfiguredSession = false
                    self.isConfiguringSession = false
                    self.cameraFieldOfView = nil
                    self.lastErrorMessage = L10n.tr("背面カメラを利用できないため、カメラ背景を開始できません。")
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .high

                if session.inputs.isEmpty {
                    guard session.canAddInput(input) else {
                        Task { @MainActor in
                            self.hasConfiguredSession = false
                            self.isConfiguringSession = false
                            self.lastErrorMessage = L10n.tr("カメラ入力を追加できませんでした。")
                        }
                        return
                    }

                    session.addInput(input)
                }

                let cameraFieldOfView = Self.makeCameraFieldOfView(for: device)

                Task { @MainActor in
                    self.hasConfiguredSession = true
                    self.isConfiguringSession = false
                    self.cameraFieldOfView = cameraFieldOfView
                    self.requestSessionStartIfNeeded()
                }
            } catch {
                Task { @MainActor in
                    self.hasConfiguredSession = false
                    self.isConfiguringSession = false
                    self.cameraFieldOfView = nil
                    self.lastErrorMessage = L10n.tr("カメラの初期化に失敗しました。")
                }
            }
        }
    }

    nonisolated private static func currentBackCameraDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    nonisolated private static func currentCameraFieldOfView() -> StarMapCameraFieldOfView? {
        guard let device = currentBackCameraDevice() else { return nil }
        return makeCameraFieldOfView(for: device)
    }

    nonisolated private static func makeCameraFieldOfView(for device: AVCaptureDevice) -> StarMapCameraFieldOfView {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return StarMapCameraFieldOfView(
            diagonalDegrees: Double(device.activeFormat.videoFieldOfView),
            sensorWidth: dimensions.width,
            sensorHeight: dimensions.height
        )
    }

    private func requestSessionStartIfNeeded() {
        guard let activationGeneration = currentActivationGenerationIfActive() else { return }
        startSessionIfNeeded(for: activationGeneration)
    }

    private func startSessionIfNeeded(for activationGeneration: UInt) {
        let session = session
        sessionQueue.async {
            guard self.matchesActivationState(
                generation: activationGeneration,
                isActive: true
            ) else { return }
            guard !session.isRunning else { return }
            Task { @MainActor in
                self.lastErrorMessage = nil
            }
            session.startRunning()
        }
    }

    private func stopSessionIfNeeded(for activationGeneration: UInt) {
        let session = session
        sessionQueue.async {
            guard self.matchesActivationState(
                generation: activationGeneration,
                isActive: false
            ) else { return }
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func updateActivationState(isActive: Bool) -> UInt {
        activationStateQueue.sync {
            activationState.update(isActive: isActive)
        }
    }

    private func currentActivationGenerationIfActive() -> UInt? {
        activationStateQueue.sync {
            guard activationState.isActive else { return nil }
            return activationState.generation
        }
    }

    nonisolated private func matchesActivationState(generation: UInt, isActive: Bool) -> Bool {
        activationStateQueue.sync {
            activationState.matches(generation: generation, isActive: isActive)
        }
    }

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleSessionRuntimeErrorNotification(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEndedNotification),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    @objc nonisolated private func handleSessionRuntimeErrorNotification(_ notification: Notification) {
        let errorCode = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
        Task { @MainActor [weak self, errorCode] in
            self?.handleSessionRuntimeError(errorCode: errorCode)
        }
    }

    @objc nonisolated private func handleSessionInterruptionEndedNotification() {
        Task { @MainActor [weak self] in
            self?.handleSessionInterruptionEnded()
        }
    }

    private func handleSessionRuntimeError(errorCode: AVError.Code?) {
        hasConfiguredSession = false

        guard let errorCode else {
            guard currentActivationGenerationIfActive() != nil else { return }
            lastErrorMessage = L10n.tr("カメラの実行中にエラーが発生しました。")
            return
        }

        if errorCode == .mediaServicesWereReset {
            lastErrorMessage = nil
            guard currentActivationGenerationIfActive() != nil else { return }
            ensureSessionConfigured()
            return
        }

        guard currentActivationGenerationIfActive() != nil else { return }
        lastErrorMessage = L10n.tr("カメラの実行中にエラーが発生しました。")
    }

    private func handleSessionInterruptionEnded() {
        guard currentActivationGenerationIfActive() != nil else { return }
        ensureSessionConfigured()
    }
}

struct StarMapCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let screenOrientation: StarMapScreenOrientation
    let videoDevice: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.configure(
            session: session,
            screenOrientation: screenOrientation,
            videoDevice: videoDevice
        )
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.configure(
            session: session,
            screenOrientation: screenOrientation,
            videoDevice: videoDevice
        )
    }

    final class PreviewView: UIView {
        private var screenOrientation: StarMapScreenOrientation = .portrait
        private var videoDevice: AVCaptureDevice?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObserver: NSKeyValueObservation?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func configure(
            session: AVCaptureSession,
            screenOrientation: StarMapScreenOrientation,
            videoDevice: AVCaptureDevice?
        ) {
            previewLayer.videoGravity = .resizeAspectFill
            if previewLayer.session !== session {
                previewLayer.session = session
            }
            self.screenOrientation = screenOrientation
            updateRotationCoordinatorIfNeeded(videoDevice: videoDevice)
            updatePreviewRotation()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            rebuildRotationCoordinator()
            updatePreviewRotation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePreviewRotation()
        }

        private func updateRotationCoordinatorIfNeeded(videoDevice: AVCaptureDevice?) {
            guard self.videoDevice?.uniqueID != videoDevice?.uniqueID || rotationCoordinator == nil else {
                return
            }

            self.videoDevice = videoDevice
            rebuildRotationCoordinator()
        }

        private func rebuildRotationCoordinator() {
            rotationObserver = nil
            rotationCoordinator = nil

            guard let videoDevice else { return }

            let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: videoDevice,
                previewLayer: previewLayer
            )
            self.rotationCoordinator = rotationCoordinator
            rotationObserver = rotationCoordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePreviewRotation()
                }
            }
        }

        private func updatePreviewRotation() {
            guard let connection = previewLayer.connection else { return }
            let rotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview
                ?? StarMapCameraPreviewRotation.fallbackAngle(for: screenOrientation)
            guard connection.isVideoRotationAngleSupported(rotationAngle) else { return }
            connection.videoRotationAngle = rotationAngle
        }
    }
}

extension UIInterfaceOrientation {
    var starMapScreenOrientation: StarMapScreenOrientation {
        switch self {
        case .portrait:
            .portrait
        case .portraitUpsideDown:
            .portraitUpsideDown
        case .landscapeLeft:
            .landscapeLeft
        case .landscapeRight:
            .landscapeRight
        default:
            .portrait
        }
    }
}

private extension StarMapMotionMatrix {
    init(rotationMatrix: CMRotationMatrix) {
        self.init(
            m11: rotationMatrix.m11,
            m12: rotationMatrix.m12,
            m13: rotationMatrix.m13,
            m21: rotationMatrix.m21,
            m22: rotationMatrix.m22,
            m23: rotationMatrix.m23,
            m31: rotationMatrix.m31,
            m32: rotationMatrix.m32,
            m33: rotationMatrix.m33
        )
    }
}
