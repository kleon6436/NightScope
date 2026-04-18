import SwiftUI
import CoreMotion
import CoreLocation

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel
    @AppStorage(StarDisplayDensity.defaultsKey) private var starDisplayDensityRaw = StarDisplayDensity.defaultValue.rawValue

    @State private var motionManager = CMMotionManager()
    @State private var headingController = StarMapHeadingController()
    @State private var bottomControlPanelHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                StarMapCanvasView(
                    viewModel: viewModel,
                    showsCardinalOverlay: true,
                    cardinalOverlayBottomInset: cardinalOverlayBottomInset
                )
                    .ignoresSafeArea(edges: .top)

                headerSection
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
            handleGyroChange()
        }
        .onDisappear {
            stopMotion()
        }
        .onChange(of: viewModel.isGyroMode) { handleGyroChange() }
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

    // MARK: - CoreMotion

    private func handleGyroChange() {
        if viewModel.isGyroMode {
            startMotion()
        } else {
            stopMotion()
        }
    }

    private func startMotion() {
        guard canEnableGyroMode else {
            viewModel.isGyroMode = false
            return
        }

        // xArbitraryZVertical: Z 軸 = 鉛直上方 (重力方向)
        // pitch のみで仰角を取得。方位角は CLHeading から取得する。
        motionManager.deviceMotionUpdateInterval = 1.0 / 30
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { motion, _ in
            guard let motion else { return }
            // pitch: 0 = フラット (天頂向き), π/2 = 垂直 (地平線向き)
            let pitchDeg = motion.attitude.pitch * 180 / .pi
            viewModel.viewAltitude = max(0, min(90, 90 - pitchDeg))
        }

        // 方位角は CLLocationManager の heading から取得
        headingController.start(
            onHeading: { heading in
            viewModel.viewAzimuth = heading
        },
            onAuthorizationUnavailable: {
                viewModel.isGyroMode = false
            }
        )
    }

    private func stopMotion() {
        motionManager.stopDeviceMotionUpdates()
        headingController.stop()
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

    private var canEnableGyroMode: Bool {
        motionManager.isDeviceMotionAvailable && headingController.canStartHeadingUpdates
    }
}

// MARK: - StarMapHeadingController

/// CLLocationManager のラッパー。StarMapViewModel に NSObject 継承を持ち込まないための分離クラス。
@Observable
final class StarMapHeadingController: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var onHeading: ((Double) -> Void)?
    private var onAuthorizationUnavailable: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    var canStartHeadingUpdates: Bool {
        guard CLLocationManager.headingAvailable() else {
            return false
        }
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways, .notDetermined:
            return true
        default:
            return false
        }
    }

    func start(
        onHeading: @escaping (Double) -> Void,
        onAuthorizationUnavailable: @escaping () -> Void
    ) {
        self.onHeading = onHeading
        self.onAuthorizationUnavailable = onAuthorizationUnavailable
        guard CLLocationManager.headingAvailable() else {
            onAuthorizationUnavailable()
            return
        }
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingHeading()
        default:
            onAuthorizationUnavailable()
        }
    }

    func stop() {
        locationManager.stopUpdatingHeading()
        onHeading = nil
        onAuthorizationUnavailable = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if onHeading != nil {
                manager.startUpdatingHeading()
            }
        default:
            manager.stopUpdatingHeading()
            if onHeading != nil {
                onAuthorizationUnavailable?()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // trueHeading が有効なら使用 (GPSなし環境では -1 になる場合あり)
        let heading = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        onHeading?(heading)
    }
}

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return iOSStarMapView(viewModel: vm)
        .preferredColorScheme(.dark)
}
