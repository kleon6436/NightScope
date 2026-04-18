import SwiftUI
@preconcurrency import AVFoundation
import CoreMedia
import CoreMotion
import UIKit

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel
    @AppStorage(StarDisplayDensity.defaultsKey) private var starDisplayDensityRaw = StarDisplayDensity.defaultValue.rawValue

    @StateObject private var motionController = StarMapMotionController()
    @StateObject private var cameraController = StarMapCameraController()
    @State private var isCameraBackgroundEnabled = false
    @State private var cameraNotice: CameraNotice?
    @State private var cameraPermissionRequestID = 0
    @State private var bottomControlPanelHeight: CGFloat = 0
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                backgroundLayer

                StarMapCanvasView(
                    viewModel: viewModel,
                    showsCardinalOverlay: true,
                    cardinalOverlayBottomInset: cardinalOverlayBottomInset,
                    backgroundColor: controlState.isCameraBackgroundVisible ? .clear : StarMapPalette.canvasBackground,
                    fovOverride: cameraAlignedHorizontalFOV
                )
                    .ignoresSafeArea(edges: .top)

                topOverlaySection
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)
                bottomControlPanel
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        bottomControlPanelHeight = newHeight
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.prepareForStarMapPresentation()
            viewModel.syncWithSelectedDate()
            updateInterfaceOrientation()
            cameraController.refreshAuthorizationStatus()
            handleGyroChange()
            syncCameraSession()
        }
        .onDisappear {
            invalidatePendingCameraPermissionRequest()
            stopMotion()
            cameraController.setSessionActive(false)
        }
        .onChange(of: viewModel.isGyroMode) { handleGyroChange() }
        .onChange(of: isCameraBackgroundEnabled) { syncCameraSession() }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateInterfaceOrientation()
        }
        .onChange(of: cameraController.authorizationStatus) { _, newStatus in
            handleCameraAuthorizationChange(newStatus)
        }
        .onChange(of: cameraController.lastErrorMessage) { _, newMessage in
            handleCameraErrorChange(newMessage)
        }
    }

    private var backgroundLayer: some View {
        Group {
            if controlState.isCameraBackgroundVisible {
                ZStack {
                    StarMapCameraPreviewView(
                        session: cameraController.session,
                        interfaceOrientation: interfaceOrientation
                    )
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.52),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Color.black.opacity(0.14)
                }
                .transition(.opacity)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    private var topOverlaySection: some View {
        iOSStarMapHeaderOverlay(
            starDisplayDensityRaw: $starDisplayDensityRaw,
            controlState: controlState,
            onToggleCameraBackground: toggleCameraBackground,
            onToggleGyroMode: toggleGyroMode,
            onOpenSettings: openAppSettings
        )
    }

    // MARK: - Bottom Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: Spacing.xs) {
            dateControlRow
            timeSliderRow
            locationLabel
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .iOSMaterialPanel(
            material: .ultraThinMaterial,
            cornerRadius: Layout.cardCornerRadius,
            style: .continuous,
            showsBorder: false
        )
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, bottomControlBottomPadding)
    }

    private var bottomControlBottomPadding: CGFloat {
        Spacing.sm
    }

    private var cardinalOverlayBottomInset: CGFloat {
        max(
            StarMapLayout.cardinalLabelBottomInset,
            bottomControlPanelHeight + bottomControlBottomPadding
        )
    }

    private var dateControlRow: some View {
        HStack {
            Label("観測日", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker("", selection: observationDateBinding, displayedComponents: [.date])
            .labelsHidden()
            .datePickerStyle(.compact)
            .colorScheme(.dark)
            .fixedSize()

            Spacer()

            Button("現在") {
                viewModel.resetToNow()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .padding(.vertical, Spacing.xs)
    }

    private var timeSliderRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "moon.stars")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: timeSliderBinding,
                in: 0...viewModel.timeSliderMaximumMinutes,
                step: 1,
                onEditingChanged: timeSliderEditingChanged
            )
                .accessibilityLabel("時刻")
                .tint(.accentColor)

            Text(viewModel.displayTimeString)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: StarMapLayout.timeLabelWidth, alignment: .trailing)
        }
        .padding(.vertical, Spacing.xs)
    }

    private var observationDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.observationDate },
            set: { viewModel.setObservationDate($0) }
        )
    }

    private var locationLabel: some View {
        HStack {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("夜空を表示中")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            skyStatusLabel
        }
        .padding(.bottom, 2)
    }

    private var skyStatusLabel: some View {
        HStack(spacing: 4) {
            if viewModel.moonAltitude > 0 {
                Label(String(format: "月 %.0f°", viewModel.moonAltitude),
                      systemImage: "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if !viewModel.meteorShowerRadiants.isEmpty {
                let shower = viewModel.meteorShowerRadiants[0].shower
                Label("\(shower.name)活動中", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.7))
            } else if let next = viewModel.nextMeteorShower {
                Label("次: \(next.shower.name)(\(next.daysUntilPeak)日後)",
                      systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlState: iOSStarMapControlState {
        let isCameraBackgroundVisible = viewModel.isGyroMode
            && isCameraBackgroundEnabled
            && cameraController.authorizationStatus == .authorized
            && cameraController.hasCameraHardware

        let displayedCameraNotice: CameraNotice? = {
            guard viewModel.isGyroMode else { return nil }
            if !cameraController.hasCameraHardware {
                return .cameraUnavailable
            }
            return cameraNotice
        }()

        let cameraButtonHelpText: String = {
            if !viewModel.isGyroMode {
                return "カメラ背景はジャイロ操作中のみ利用できます"
            }
            if !cameraController.hasCameraHardware {
                return "この環境ではカメラ背景を利用できません"
            }
            return isCameraBackgroundVisible ? "カメラ背景をオフにします" : "カメラ背景をオンにします"
        }()

        let cameraButtonHintText: String = {
            if !viewModel.isGyroMode {
                return "ジャイロ操作をオンにすると利用できます"
            }
            if !cameraController.hasCameraHardware {
                return "カメラを利用できるデバイスで使用してください"
            }
            return "実際の空の映像を背景に重ねて表示します"
        }()

        return iOSStarMapControlState(
            selectedStarDisplayDensity: StarDisplayDensity(rawValue: starDisplayDensityRaw) ?? .defaultValue,
            canEnableGyroMode: motionController.canEnableGyroMode,
            isGyroMode: viewModel.isGyroMode,
            isCameraBackgroundVisible: isCameraBackgroundVisible,
            canToggleCameraBackground: viewModel.isGyroMode && cameraController.hasCameraHardware,
            cameraButtonHelpText: cameraButtonHelpText,
            cameraButtonHintText: cameraButtonHintText,
            displayedCameraNotice: displayedCameraNotice
        )
    }

    private var screenOrientation: StarMapScreenOrientation {
        interfaceOrientation.starMapScreenOrientation
    }

    private var cameraAlignedHorizontalFOV: Double? {
        guard controlState.isCameraBackgroundVisible,
              let cameraFieldOfView = cameraController.cameraFieldOfView else {
            return nil
        }
        return cameraFieldOfView.visibleHorizontalDegrees(
            viewportSize: viewModel.canvasSize,
            screenOrientation: screenOrientation
        )
    }

    private func toggleGyroMode() {
        withAnimation(reduceMotion ? .none : .standard) {
            viewModel.isGyroMode.toggle()
        }
    }

    // MARK: - CoreMotion

    private func handleGyroChange() {
        if viewModel.isGyroMode {
            startMotion()
        } else {
            stopMotion()
            disableCameraBackground(clearNotice: true)
        }
        syncCameraSession()
    }

    private func startMotion() {
        motionController.updateScreenOrientation(screenOrientation)
        motionController.start(
            onPoseUpdate: { pose in
                viewModel.viewAzimuth = pose.azimuth
                viewModel.viewAltitude = pose.altitude
                viewModel.viewRoll = pose.roll
            },
            onFailure: {
                viewModel.isGyroMode = false
            }
        )
    }

    private func stopMotion() {
        motionController.stop()
    }

    private func toggleCameraBackground() {
        guard viewModel.isGyroMode else { return }
        guard cameraController.hasCameraHardware else {
            cameraNotice = .cameraUnavailable
            return
        }

        if isCameraBackgroundEnabled {
            disableCameraBackground(clearNotice: true)
            return
        }

        cameraNotice = nil

        switch cameraController.authorizationStatus {
        case .authorized:
            isCameraBackgroundEnabled = true
        case .notDetermined:
            invalidatePendingCameraPermissionRequest()
            let requestID = cameraPermissionRequestID
            Task { @MainActor in
                let granted = await cameraController.requestAccess()
                guard requestID == cameraPermissionRequestID else { return }

                if granted, viewModel.isGyroMode {
                    cameraNotice = nil
                    isCameraBackgroundEnabled = true
                } else if granted {
                    disableCameraBackground(clearNotice: true)
                } else {
                    disableCameraBackground(clearNotice: false)
                    cameraNotice = .cameraPermissionDenied
                }
            }
        case .denied:
            disableCameraBackground(clearNotice: false)
            cameraNotice = .cameraPermissionDenied
        case .restricted:
            disableCameraBackground(clearNotice: false)
            cameraNotice = .cameraRestricted
        @unknown default:
            disableCameraBackground(clearNotice: false)
            cameraNotice = .cameraUnexpectedFailure("カメラの利用状況を判定できませんでした。")
        }
    }

    private func disableCameraBackground(clearNotice: Bool) {
        invalidatePendingCameraPermissionRequest()
        isCameraBackgroundEnabled = false
        cameraController.setSessionActive(false)
        if clearNotice {
            cameraNotice = nil
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            updateInterfaceOrientation()
            cameraController.refreshAuthorizationStatus()
        }
        syncCameraSession()
    }

    private func syncCameraSession() {
        cameraController.setSessionActive(scenePhase == .active && controlState.isCameraBackgroundVisible)
    }

    private func handleCameraAuthorizationChange(_ status: AVAuthorizationStatus) {
        if status == .authorized {
            cameraNotice = nil
        }
        if status != .authorized && isCameraBackgroundEnabled {
            disableCameraBackground(clearNotice: false)
            switch status {
            case .denied:
                cameraNotice = .cameraPermissionDenied
            case .restricted:
                cameraNotice = .cameraRestricted
            default:
                break
            }
        }
        syncCameraSession()
    }

    private func handleCameraErrorChange(_ message: String?) {
        guard let message else { return }
        disableCameraBackground(clearNotice: false)
        cameraNotice = .cameraUnexpectedFailure(message)
    }

    private func invalidatePendingCameraPermissionRequest() {
        cameraPermissionRequestID &+= 1
    }

    private func updateInterfaceOrientation() {
        let resolvedOrientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .effectiveGeometry.interfaceOrientation ?? interfaceOrientation
        interfaceOrientation = resolvedOrientation
        motionController.updateScreenOrientation(resolvedOrientation.starMapScreenOrientation)
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private var timeSliderBinding: Binding<Double> {
        Binding(
            get: { viewModel.timeSliderMinutes },
            set: { viewModel.setTimeSliderMinutes($0) }
        )
    }

    private func timeSliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            viewModel.beginTimeSliderInteraction()
        } else {
            viewModel.endTimeSliderInteraction()
        }
    }
}

private struct iOSStarMapControlState {
    let selectedStarDisplayDensity: StarDisplayDensity
    let canEnableGyroMode: Bool
    let isGyroMode: Bool
    let isCameraBackgroundVisible: Bool
    let canToggleCameraBackground: Bool
    let cameraButtonHelpText: String
    let cameraButtonHintText: String
    let displayedCameraNotice: CameraNotice?
}

private struct iOSStarMapHeaderOverlay: View {
    @Binding var starDisplayDensityRaw: String
    let controlState: iOSStarMapControlState
    let onToggleCameraBackground: () -> Void
    let onToggleGyroMode: () -> Void
    let onOpenSettings: () -> Void

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
                    Text("星空を表示します")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } trailing: {
                HStack(spacing: Spacing.xs / 2) {
                    starDensityMenu
                    cameraBackgroundButton
                    gyroToggleButton
                }
            }

            if let notice = controlState.displayedCameraNotice {
                iOSStarMapNoticeCard(notice: notice, onOpenSettings: onOpenSettings)
            }
        }
    }

    private var starDensityMenu: some View {
        Menu {
            Picker("星の表示数", selection: $starDisplayDensityRaw) {
                ForEach(StarDisplayDensity.allCases) { density in
                    Text(density.settingsLabel).tag(density.rawValue)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("星の表示数")
        .accessibilityValue(controlState.selectedStarDisplayDensity.settingsLabel)
        .accessibilityHint("表示する恒星の量を変更します")
    }

    private var cameraBackgroundButton: some View {
        Button(action: onToggleCameraBackground) {
            Image(systemName: controlState.isCameraBackgroundVisible ? "camera.fill" : "camera")
                .font(.headline)
                .frame(width: 44, height: 44)
                .symbolEffect(.bounce, value: controlState.isCameraBackgroundVisible)
        }
        .buttonStyle(.glass)
        .help(controlState.cameraButtonHelpText)
        .accessibilityLabel(controlState.isCameraBackgroundVisible ? "カメラ背景をオフにする" : "カメラ背景をオンにする")
        .accessibilityValue(controlState.isCameraBackgroundVisible ? "オン" : "オフ")
        .accessibilityHint(controlState.cameraButtonHintText)
        .disabled(!controlState.canToggleCameraBackground)
    }

    private var gyroToggleButton: some View {
        Button(action: onToggleGyroMode) {
            Image(systemName: controlState.isGyroMode ? "gyroscope" : "hand.draw")
                .font(.headline)
                .frame(width: 44, height: 44)
                .symbolEffect(.bounce, value: controlState.isGyroMode)
        }
        .buttonStyle(.glass)
        .help(controlState.isGyroMode ? "タッチ操作に切替" : "ジャイロ操作に切替")
        .accessibilityLabel(controlState.isGyroMode ? "タッチ操作に切り替える" : "ジャイロ操作に切り替える")
        .disabled(!controlState.canEnableGyroMode)
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
                Button("設定を開く", action: onOpenSettings)
                    .buttonStyle(.glass)
                    .accessibilityHint("NightScope の設定画面を開きます")
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

private struct CameraNotice: Equatable {
    let symbolName: String
    let title: String
    let message: String
    let showsSettingsButton: Bool

    static let cameraUnavailable = CameraNotice(
        symbolName: "camera.slash",
        title: "カメラ背景を利用できません",
        message: "この環境では背面カメラを利用できないため、星空マップの通常背景を表示しています。",
        showsSettingsButton: false
    )

    static let cameraRestricted = CameraNotice(
        symbolName: "hand.raised.fill",
        title: "カメラの使用が制限されています",
        message: "スクリーンタイムやデバイス設定の制限により、この機能は利用できません。",
        showsSettingsButton: false
    )

    static let cameraPermissionDenied = CameraNotice(
        symbolName: "camera.badge.ellipsis",
        title: "カメラのアクセスが必要です",
        message: "ジャイロモード中に実景と星図を重ねるには、設定から NightScope のカメラアクセスを許可してください。",
        showsSettingsButton: true
    )

    static func cameraUnexpectedFailure(_ message: String) -> CameraNotice {
        CameraNotice(
            symbolName: "exclamationmark.triangle.fill",
            title: "カメラを開始できませんでした",
            message: message,
            showsSettingsButton: false
        )
    }
}

@MainActor
private final class StarMapMotionController: ObservableObject {
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
private final class StarMapCameraController: ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var hasCameraHardware: Bool
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var cameraFieldOfView: StarMapCameraFieldOfView?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "NightScope.StarMapCameraSession")
    private var hasConfiguredSession = false
    private var isConfiguringSession = false

    init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraHardware = Self.currentBackCameraDevice() != nil
        cameraFieldOfView = Self.currentCameraFieldOfView()
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
        guard hasCameraHardware, authorizationStatus == .authorized else {
            stopSession()
            return
        }

        let session = session
        let sessionQueue = sessionQueue
        if isActive {
            ensureSessionConfigured()
            sessionQueue.async {
                guard !session.isRunning else { return }
                Task { @MainActor in
                    self.lastErrorMessage = nil
                }
                session.startRunning()
            }
        } else {
            stopSession()
        }
    }

    private func ensureSessionConfigured() {
        guard !hasConfiguredSession, !isConfiguringSession else { return }
        isConfiguringSession = true

        let session = session
        sessionQueue.async {
            guard let device = Self.currentBackCameraDevice() else {
                Task { @MainActor in
                    self.hasCameraHardware = false
                    self.hasConfiguredSession = false
                    self.isConfiguringSession = false
                    self.cameraFieldOfView = nil
                    self.lastErrorMessage = "背面カメラを利用できないため、カメラ背景を開始できません。"
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
                            self.lastErrorMessage = "カメラ入力を追加できませんでした。"
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
                }
            } catch {
                Task { @MainActor in
                    self.hasConfiguredSession = false
                    self.isConfiguringSession = false
                    self.cameraFieldOfView = nil
                    self.lastErrorMessage = "カメラの初期化に失敗しました。"
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

    private func stopSession() {
        let session = session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
}

private struct StarMapCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let interfaceOrientation: UIInterfaceOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.configure(session: session, interfaceOrientation: interfaceOrientation)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.configure(session: session, interfaceOrientation: interfaceOrientation)
    }

    final class PreviewView: UIView {
        private var interfaceOrientation: UIInterfaceOrientation = .portrait

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func configure(session: AVCaptureSession, interfaceOrientation: UIInterfaceOrientation) {
            previewLayer.videoGravity = .resizeAspectFill
            if previewLayer.session !== session {
                previewLayer.session = session
            }
            self.interfaceOrientation = interfaceOrientation
            updatePreviewRotation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePreviewRotation()
        }

        private func updatePreviewRotation() {
            guard let connection = previewLayer.connection,
                  let rotationAngle = interfaceOrientation.captureVideoRotationAngle else {
                return
            }
            guard connection.isVideoRotationAngleSupported(rotationAngle) else { return }
            connection.videoRotationAngle = rotationAngle
        }
    }
}

private extension UIInterfaceOrientation {
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

    var captureVideoRotationAngle: CGFloat? {
        switch self {
        case .portrait:
            0
        case .portraitUpsideDown:
            180
        case .landscapeLeft:
            90
        case .landscapeRight:
            270
        default:
            nil
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

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return iOSStarMapView(viewModel: vm)
        .preferredColorScheme(.dark)
}
