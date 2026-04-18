import SwiftUI
@preconcurrency import AVFoundation
import CoreMotion
import UIKit

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel
    @AppStorage(StarDisplayDensity.defaultsKey) private var starDisplayDensityRaw = StarDisplayDensity.defaultValue.rawValue

    @State private var motionManager = CMMotionManager()
    @StateObject private var cameraController = StarMapCameraController()
    @State private var lastMotionPose: StarMapMotionPose?
    @State private var isCameraBackgroundEnabled = false
    @State private var cameraNotice: CameraNotice?
    @State private var bottomControlPanelHeight: CGFloat = 0
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
                    backgroundColor: isCameraBackgroundVisible ? .clear : StarMapPalette.canvasBackground
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
            cameraController.refreshAuthorizationStatus()
            handleGyroChange()
            syncCameraSession()
        }
        .onDisappear {
            stopMotion()
            cameraController.setSessionActive(false)
        }
        .onChange(of: viewModel.isGyroMode) { handleGyroChange() }
        .onChange(of: isCameraBackgroundEnabled) { syncCameraSession() }
        .onChange(of: scenePhase) { syncCameraSession() }
        .onChange(of: cameraController.authorizationStatus) { _, newStatus in
            handleCameraAuthorizationChange(newStatus)
        }
        .onChange(of: cameraController.lastErrorMessage) { _, newMessage in
            handleCameraErrorChange(newMessage)
        }
    }

    private var backgroundLayer: some View {
        Group {
            if isCameraBackgroundVisible {
                ZStack {
                    StarMapCameraPreviewView(session: cameraController.session)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            headerSection
            if let notice = displayedCameraNotice {
                cameraNoticeCard(notice)
            }
        }
    }

    private var headerSection: some View {
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
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

    private var selectedStarDisplayDensity: StarDisplayDensity {
        StarDisplayDensity(rawValue: starDisplayDensityRaw) ?? .defaultValue
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
        .accessibilityValue(selectedStarDisplayDensity.settingsLabel)
        .accessibilityHint("表示する恒星の量を変更します")
    }

    // MARK: - Gyroscope Toggle

    private var gyroToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .standard) {
                viewModel.isGyroMode.toggle()
            }
        } label: {
            Image(systemName: viewModel.isGyroMode ? "gyroscope" : "hand.draw")
                .font(.headline)
                .frame(width: 44, height: 44)
                .symbolEffect(.bounce, value: viewModel.isGyroMode)
        }
        .buttonStyle(.glass)
        .help(viewModel.isGyroMode ? "タッチ操作に切替" : "ジャイロ操作に切替")
        .accessibilityLabel(viewModel.isGyroMode ? "タッチ操作に切り替える" : "ジャイロ操作に切り替える")
        .disabled(!canEnableGyroMode)
    }

    private var cameraBackgroundButton: some View {
        Button(action: toggleCameraBackground) {
            Image(systemName: isCameraBackgroundVisible ? "camera.fill" : "camera")
                .font(.headline)
                .frame(width: 44, height: 44)
                .symbolEffect(.bounce, value: isCameraBackgroundVisible)
        }
        .buttonStyle(.glass)
        .help(cameraButtonHelpText)
        .accessibilityLabel(isCameraBackgroundVisible ? "カメラ背景をオフにする" : "カメラ背景をオンにする")
        .accessibilityValue(isCameraBackgroundVisible ? "オン" : "オフ")
        .accessibilityHint(cameraButtonHintText)
        .disabled(!canToggleCameraBackground)
    }

    private var displayedCameraNotice: CameraNotice? {
        guard viewModel.isGyroMode else { return nil }
        if !cameraController.hasCameraHardware {
            return .cameraUnavailable
        }
        return cameraNotice
    }

    private var isCameraBackgroundVisible: Bool {
        viewModel.isGyroMode
            && isCameraBackgroundEnabled
            && cameraController.authorizationStatus == .authorized
            && cameraController.hasCameraHardware
    }

    private var canToggleCameraBackground: Bool {
        viewModel.isGyroMode && cameraController.hasCameraHardware
    }

    private var cameraButtonHelpText: String {
        if !viewModel.isGyroMode {
            return "カメラ背景はジャイロ操作中のみ利用できます"
        }
        if !cameraController.hasCameraHardware {
            return "この環境ではカメラ背景を利用できません"
        }
        return isCameraBackgroundVisible ? "カメラ背景をオフにします" : "カメラ背景をオンにします"
    }

    private var cameraButtonHintText: String {
        if !viewModel.isGyroMode {
            return "ジャイロ操作をオンにすると利用できます"
        }
        if !cameraController.hasCameraHardware {
            return "カメラを利用できるデバイスで使用してください"
        }
        return "実際の空の映像を背景に重ねて表示します"
    }

    private func cameraNoticeCard(_ notice: CameraNotice) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(notice.title, systemImage: notice.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            if notice.showsSettingsButton {
                Button("設定を開く", action: openAppSettings)
                    .buttonStyle(.glass)
                    .accessibilityHint("NightScope の設定画面を開きます")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
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
        guard let referenceFrame = preferredMotionReferenceFrame else {
            viewModel.isGyroMode = false
            return
        }
        guard motionManager.isDeviceMotionAvailable else {
            viewModel.isGyroMode = false
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }

        lastMotionPose = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 45
        motionManager.startDeviceMotionUpdates(
            using: referenceFrame,
            to: .main
        ) { motion, error in
            if error != nil {
                viewModel.isGyroMode = false
                return
            }
            guard let motion else { return }

            let rawPose = StarMapMotionPose.make(
                rotationMatrix: StarMapMotionMatrix(rotationMatrix: motion.attitude.rotationMatrix)
            )
            let smoothedPose = StarMapMotionPose.smoothed(previous: lastMotionPose, next: rawPose)
            lastMotionPose = smoothedPose
            viewModel.viewAzimuth = smoothedPose.azimuth
            viewModel.viewAltitude = smoothedPose.altitude
        }
    }

    private func stopMotion() {
        motionManager.stopDeviceMotionUpdates()
        lastMotionPose = nil
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
            syncCameraSession()
        case .notDetermined:
            Task { @MainActor in
                let granted = await cameraController.requestAccess()
                if granted {
                    cameraNotice = nil
                    isCameraBackgroundEnabled = true
                    syncCameraSession()
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
        isCameraBackgroundEnabled = false
        cameraController.setSessionActive(false)
        if clearNotice {
            cameraNotice = nil
        }
    }

    private func syncCameraSession() {
        cameraController.setSessionActive(scenePhase == .active && isCameraBackgroundVisible)
    }

    private func handleCameraAuthorizationChange(_ status: AVAuthorizationStatus) {
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

    private var preferredMotionReferenceFrame: CMAttitudeReferenceFrame? {
        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()

        if availableFrames.contains(.xTrueNorthZVertical) {
            return .xTrueNorthZVertical
        }
        if availableFrames.contains(.xMagneticNorthZVertical) {
            return .xMagneticNorthZVertical
        }

        return nil
    }

    private var canEnableGyroMode: Bool {
        motionManager.isDeviceMotionAvailable && preferredMotionReferenceFrame != nil
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
private final class StarMapCameraController: ObservableObject {
    private static let stopDelayNanoseconds: UInt64 = 600_000_000

    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var hasCameraHardware: Bool
    @Published private(set) var lastErrorMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "NightScope.StarMapCameraSession")
    private var hasConfiguredSession = false
    private var pendingStopTask: Task<Void, Never>?

    init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraHardware = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if hasCameraHardware {
            hasCameraHardware = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        }
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
            cancelPendingStop()
            stopSession()
            return
        }

        if isActive {
            cancelPendingStop()
        } else {
            cancelPendingStop()
        }

        ensureSessionConfigured()

        let session = session
        let sessionQueue = sessionQueue
        if isActive {
            sessionQueue.async {
                guard !session.isRunning else { return }
                Task { @MainActor in
                    self.lastErrorMessage = nil
                }
                session.startRunning()
            }
        } else {
            pendingStopTask = Task { [session, sessionQueue] in
                try? await Task.sleep(nanoseconds: Self.stopDelayNanoseconds)
                guard !Task.isCancelled else { return }
                sessionQueue.async {
                    guard session.isRunning else { return }
                    session.stopRunning()
                }
            }
        }
    }

    private func ensureSessionConfigured() {
        guard !hasConfiguredSession else { return }
        hasConfiguredSession = true

        let session = session
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                Task { @MainActor in
                    self.hasCameraHardware = false
                    self.lastErrorMessage = "背面カメラを利用できないため、カメラ背景を開始できません。"
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .high

                guard session.canAddInput(input) else {
                    Task { @MainActor in
                        self.lastErrorMessage = "カメラ入力を追加できませんでした。"
                    }
                    return
                }

                session.addInput(input)
            } catch {
                Task { @MainActor in
                    self.lastErrorMessage = "カメラの初期化に失敗しました。"
                }
            }
        }
    }

    private func stopSession() {
        cancelPendingStop()
        let session = session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func cancelPendingStop() {
        pendingStopTask?.cancel()
        pendingStopTask = nil
    }
}

private struct StarMapCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
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
