import SwiftUI
@preconcurrency import AVFoundation
import UIKit

// MARK: - 星空ビュー
/// 星空マップとカメラ背景、操作パネルを統合する画面。
struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel

    @StateObject private var motionController = StarMapMotionController()
    @StateObject private var cameraController = StarMapCameraController()
    @State private var isCameraBackgroundEnabled = false
    @State private var isPresentingDisplaySettings = false
    @State private var isRequestingCameraPermission = false
    @State private var cameraNotice: CameraNotice?
    @State private var cameraPermissionRequestID = 0
    @State private var bottomControlPanelHeight: CGFloat = 0
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    backgroundLayer

                    StarMapCanvasView(
                        viewModel: viewModel,
                        showsCardinalOverlay: true,
                        cardinalOverlayBottomInset: cardinalOverlayBottomInset + proxy.safeAreaInsets.bottom,
                        backgroundColor: controlState.isCameraBackgroundVisible ? .clear : StarMapPalette.canvasBackground,
                        drawsDynamicSky: !controlState.isCameraBackgroundVisible,
                        horizonOverlayStyle: IOSDesignTokens.StarMap.horizonOverlayStyle,
                        fovOverride: cameraAlignedHorizontalFOV
                    )
                        .ignoresSafeArea(edges: [.top, .bottom])

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
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.activatePresentationIfNeeded()
            updateInterfaceOrientation()
            cameraController.refreshAuthorizationStatus()
            syncMotionState()
            syncCameraSession()
        }
        .onDisappear {
            invalidatePendingCameraPermissionRequest()
            viewModel.finalizeTransientInteractionState()
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
        .sheet(isPresented: $isPresentingDisplaySettings) {
            iOSStarMapDisplaySettingsSheetView(motionController: motionController)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            // カメラ背景を切り替えても、セッション再構成を避けるため preview は保持する。
            if cameraSessionState.shouldKeepPreviewAttached {
                ZStack {
                    StarMapCameraPreviewView(
                        session: cameraController.session,
                        screenOrientation: screenOrientation,
                        videoDevice: cameraController.previewDevice
                    )
                    .opacity(controlState.isCameraBackgroundVisible ? 1 : 0)
                    .accessibilityHidden(true)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.52),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(controlState.isCameraBackgroundVisible ? 1 : 0)
                }
            }
            Color.black.opacity(controlState.isCameraBackgroundVisible ? 0.14 : 1)
        }
        .ignoresSafeArea()
    }

    private var topOverlaySection: some View {
        iOSStarMapHeaderOverlay(
            controlState: controlState,
            onOpenDisplaySettings: openDisplaySettings,
            onToggleCameraBackground: toggleCameraBackground,
            onToggleGyroMode: toggleGyroMode,
            onOpenSettings: openAppSettings
        )
    }

    // MARK: - 下部コントロール

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
        // 下部パネルの実高さを使って、方位ラベルが重ならないようにする。
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
                    .accessibilityLabel(L10n.tr("時刻"))
                    .tint(.accentColor)

                Text(viewModel.displayTimeString)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: StarMapLayout.timeLabelWidth, alignment: .trailing)
            }

            ObservationHeatBarView(
                observationConditionTimeline: viewModel.observationConditionTimeline,
                sliderFraction: viewModel.timeSliderFraction,
                currentMoonAltitude: viewModel.moonAltitude,
                currentMoonPhase: viewModel.moonPhase,
                currentSunAltitude: viewModel.sunAltitude,
                currentTimeText: viewModel.displayTimeString
            )
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
            terrainStatusLabel
            Spacer()
            skyStatusLabel
        }
        .padding(.bottom, 2)
    }

    private var terrainStatusLabel: some View {
        Label(viewModel.terrainFetchState.statusText, systemImage: viewModel.terrainFetchState.systemImageName)
            .font(.caption2)
            .foregroundStyle(terrainStatusColor)
            .accessibilityLabel(L10n.format("地形データ状態: %@", viewModel.terrainFetchState.statusText))
    }

    private var terrainStatusColor: Color {
        switch viewModel.terrainFetchState {
        case .idle, .loading:
            .secondary
        case .available:
            Color(red: 0.4, green: 1.0, blue: 0.7)
        case .unavailable:
            .orange
        }
    }

    private var skyStatusLabel: some View {
        HStack(spacing: 4) {
            if viewModel.moonAltitude > 0 {
                Label(L10n.format("月 %.0f°", viewModel.moonAltitude),
                      systemImage: "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if !viewModel.meteorShowerRadiants.isEmpty {
                let shower = viewModel.meteorShowerRadiants[0].shower
                Label(L10n.format("%@活動中", shower.localizedName), systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.7))
            } else if let next = viewModel.nextMeteorShower {
                Label(L10n.format("次: %@(%d日後)", next.shower.localizedName, next.daysUntilPeak),
                       systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlState: iOSStarMapControlState {
        let isCameraBackgroundVisible = cameraSessionState.isCameraBackgroundVisible

        let displayedCameraNotice: CameraNotice? = {
            guard viewModel.isGyroMode else { return nil }
            if !cameraController.hasCameraHardware {
                return .cameraUnavailable
            }
            return cameraNotice
        }()

        let cameraButtonHelpText: String = {
            if isRequestingCameraPermission {
                return L10n.tr("カメラ権限の確認中です")
            }
            if !viewModel.isGyroMode {
                return L10n.tr("カメラ背景はジャイロ操作中のみ利用できます")
            }
            if !cameraController.hasCameraHardware {
                return L10n.tr("この環境ではカメラ背景を利用できません")
            }
            return isCameraBackgroundVisible
                ? L10n.tr("カメラ背景をオフにする")
                : L10n.tr("カメラ背景をオンにする")
        }()

        let cameraButtonHintText: String = {
            if isRequestingCameraPermission {
                return L10n.tr("権限ダイアログの完了後に背景を切り替えます")
            }
            if !viewModel.isGyroMode {
                return L10n.tr("ジャイロ操作をオンにすると利用できます")
            }
            if !cameraController.hasCameraHardware {
                return L10n.tr("カメラを利用できるデバイスで使用してください")
            }
            return L10n.tr("実際の空の映像を背景に重ねて表示します")
        }()

        return iOSStarMapControlState(
            displaySettings: viewModel.displaySettings,
            canEnableGyroMode: motionController.canEnableGyroMode,
            isGyroMode: viewModel.isGyroMode,
            isCameraBackgroundVisible: isCameraBackgroundVisible,
            canToggleCameraBackground: viewModel.isGyroMode && cameraController.hasCameraHardware && !isRequestingCameraPermission,
            cameraButtonHelpText: cameraButtonHelpText,
            cameraButtonHintText: cameraButtonHintText,
            displayedCameraNotice: displayedCameraNotice
        )
    }

    private var cameraSessionState: StarMapCameraSessionState {
        StarMapCameraSessionState(
            isGyroMode: viewModel.isGyroMode,
            isBackgroundEnabled: isCameraBackgroundEnabled,
            isAuthorized: cameraController.authorizationStatus == .authorized,
            hasCameraHardware: cameraController.hasCameraHardware,
            isSceneActive: scenePhase == .active
        )
    }

    private var screenOrientation: StarMapScreenOrientation {
        interfaceOrientation.starMapScreenOrientation
    }

    private var cameraAlignedHorizontalFOV: Double? {
        guard cameraSessionState.isCameraBackgroundVisible,
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

    private func openDisplaySettings() {
        isPresentingDisplaySettings = true
    }

    // MARK: - CoreMotion 制御

    private func handleGyroChange() {
        syncMotionState()
        if !viewModel.isGyroMode {
            stopMotion()
            disableCameraBackground(clearNotice: true)
        }
        syncCameraSession()
    }

    private func startMotion() {
        motionController.updateScreenOrientation(screenOrientation)
        motionController.start(
            onPoseUpdate: { pose in
                let offset = UserDefaults.standard.double(
                    forKey: StarMapDisplaySettings.compassAzimuthOffsetDefaultsKey
                )
                let corrected = pose.azimuth + offset
                viewModel.viewAzimuth = (corrected.truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360)
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
        guard !isRequestingCameraPermission else { return }
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
            isRequestingCameraPermission = true
            let requestID = cameraPermissionRequestID
            Task { @MainActor in
                let granted = await cameraController.requestAccess()
                guard requestID == cameraPermissionRequestID else { return }
                isRequestingCameraPermission = false

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
            cameraNotice = .cameraUnexpectedFailure(L10n.tr("カメラの利用状況を判定できませんでした。"))
        }
    }

    private func disableCameraBackground(clearNotice: Bool) {
        invalidatePendingCameraPermissionRequest()
        isCameraBackgroundEnabled = false
        syncCameraSession()
        if clearNotice {
            cameraNotice = nil
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            updateInterfaceOrientation()
            cameraController.refreshAuthorizationStatus()
        } else {
            viewModel.finalizeTransientInteractionState()
        }
        syncMotionState()
        syncCameraSession()
    }

    private func syncCameraSession() {
        cameraController.setSessionActive(cameraSessionState.shouldRunSession)
    }

    private func syncMotionState() {
        let shouldRunMotion = viewModel.isGyroMode && scenePhase == .active
        if shouldRunMotion {
            startMotion()
        } else {
            stopMotion()
        }
    }

    private func handleCameraAuthorizationChange(_ status: AVAuthorizationStatus) {
        if status != .notDetermined {
            isRequestingCameraPermission = false
        }
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
        isRequestingCameraPermission = false
    }

    private func updateInterfaceOrientation() {
        let resolvedOrientation: UIInterfaceOrientation

        if UIDevice.current.userInterfaceIdiom == .phone {
            resolvedOrientation = .portrait
        } else {
            resolvedOrientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .effectiveGeometry.interfaceOrientation ?? interfaceOrientation
        }

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

// MARK: - プレビュー

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return iOSStarMapView(viewModel: vm)
        .preferredColorScheme(.dark)
}
