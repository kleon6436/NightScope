import SwiftUI
import CoreMotion
import CoreLocation

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel

    @State private var motionManager = CMMotionManager()
    @State private var headingController = StarMapHeadingController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                StarMapCanvasView(
                    viewModel: viewModel,
                    showsCardinalOverlay: false
                )
                    .ignoresSafeArea(edges: .top)

                headerSection
                bottomControlPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    gyroToggleButton
                }
            }
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
            title: "星空マップ",
            titleColor: .white,
            subtitleColor: .white.opacity(0.75)
        ) {
            Text("視野と時刻を調整します")
                .font(.caption)
                .lineLimit(2)
        } trailing: {
            EmptyView()
        }
    }

    // MARK: - Bottom Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: Spacing.xs) {
            cardinalLegend
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
        Spacing.lg
    }

    private var cardinalLegend: some View {
        let directions: [(Double, String)] = [
            (0, StarMapPresentation.azimuthName(for: 0)),
            (45, StarMapPresentation.azimuthName(for: 45)),
            (90, StarMapPresentation.azimuthName(for: 90)),
            (135, StarMapPresentation.azimuthName(for: 135)),
            (180, StarMapPresentation.azimuthName(for: 180)),
            (225, StarMapPresentation.azimuthName(for: 225)),
            (270, StarMapPresentation.azimuthName(for: 270)),
            (315, StarMapPresentation.azimuthName(for: 315))
        ]

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 4),
            spacing: Spacing.xs
        ) {
            ForEach(directions, id: \.0) { _, label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, StarMapLayout.cardinalLabelVerticalPadding)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
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
                in: 0...viewModel.nightDurationMinutes,
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

    // MARK: - Gyroscope Toggle

    private var gyroToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .standard) {
                viewModel.isGyroMode.toggle()
            }
        } label: {
            Image(systemName: viewModel.isGyroMode ? "gyroscope" : "hand.draw")
                .symbolEffect(.bounce, value: viewModel.isGyroMode)
        }
        .help(viewModel.isGyroMode ? "タッチ操作に切替" : "ジャイロ操作に切替")
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
