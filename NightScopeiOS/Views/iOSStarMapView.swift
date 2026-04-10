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
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                StarMapCanvasView(viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                bottomControlPanel
            }
            .navigationTitle("星空マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    gyroToggleButton
                }
            }
        }
        .onAppear {
            viewModel.syncWithSelectedDate()
            handleGyroChange()
        }
        .onDisappear {
            stopMotion()
        }
        .onChange(of: viewModel.isGyroMode) { handleGyroChange() }
    }

    // MARK: - Bottom Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: Spacing.xs) {
            dateControlRow
            timeSliderRow
            locationLabel
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    private var dateControlRow: some View {
        HStack {
            Label("観測日", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            DatePicker(
                "",
                selection: $viewModel.displayDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .colorScheme(.dark)

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

            Slider(value: timeSliderBinding, in: 0...StarMapLayout.minutesInDay, step: 1) {
                Text("時刻")
            }
            .tint(.accentColor)

            Text(viewModel.displayTimeString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: StarMapLayout.timeLabelWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var locationLabel: some View {
        HStack {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.isNight ? "夜空を表示中" : "昼間 (太陽が地平線上)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            sunMoonStatusLabel
        }
        .padding(.bottom, 2)
    }

    private var sunMoonStatusLabel: some View {
        HStack(spacing: 4) {
            if viewModel.sunAltitude > 0 {
                Label(String(format: "太陽 %.0f°", viewModel.sunAltitude),
                      systemImage: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
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
            Image(systemName: viewModel.isGyroMode ? "gyroscope" : "map")
                .symbolEffect(.bounce, value: viewModel.isGyroMode)
        }
        .help(viewModel.isGyroMode ? "全天マップに切替" : "ジャイロモードに切替")
        .disabled(!motionManager.isDeviceMotionAvailable)
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
        guard motionManager.isDeviceMotionAvailable else {
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
        headingController.start { heading in
            viewModel.viewAzimuth = heading
        }
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
}

// MARK: - StarMapHeadingController

/// CLLocationManager のラッパー。StarMapViewModel に NSObject 継承を持ち込まないための分離クラス。
@Observable
final class StarMapHeadingController: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var onHeading: ((Double) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start(onHeading: @escaping (Double) -> Void) {
        self.onHeading = onHeading
        locationManager.startUpdatingHeading()
    }

    func stop() {
        locationManager.stopUpdatingHeading()
        onHeading = nil
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
