import SwiftUI
import CoreMotion

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel

    @State private var motionManager = CMMotionManager()
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
        .onAppear { handleGyroChange() }
        .onDisappear { stopMotion() }
        .onChange(of: viewModel.isGyroMode) { handleGyroChange() }
    }

    // MARK: - Bottom Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: Spacing.xs) {
            dateTimePicker
            locationLabel
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    private var dateTimePicker: some View {
        HStack {
            Label("観測日時", systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            DatePicker(
                "",
                selection: $viewModel.displayDate,
                displayedComponents: [.date, .hourAndMinute]
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
        }
    }

    // MARK: - Gyroscope Toggle

    private var gyroToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .standard) {
                viewModel.isGyroMode.toggle()
            }
        } label: {
            Image(systemName: viewModel.isGyroMode
                  ? "gyroscope"
                  : "map")
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
        motionManager.deviceMotionUpdateInterval = 1.0 / 30
        // xMagneticNorthZVertical: x軸=磁北, z軸=鉛直上方
        // → 磁北を基準にした絶対方位が得られる
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [self] motion, _ in
            guard let motion else { return }
            updateViewDirection(from: motion)
        }
    }

    private func stopMotion() {
        motionManager.stopDeviceMotionUpdates()
    }

    /// デバイスの姿勢 → 画面中心が向く仰角・方位角に変換
    ///
    /// xMagneticNorthZVertical フレームでの attitude.rotationMatrix:
    ///   - デバイスをフラットに置いた状態 (画面上向き): z軸が上を指す
    ///   - デバイスを傾けて空に向ける場合:
    ///     - ポートレートで垂直に立てると画面が自分を向く (仰角 0°)
    ///     - ポートレートで傾けて上を向くと画面が空を向く (仰角増加)
    ///
    /// 画面の "奥" 方向 (-Z screen) がどこを向いているかを計算する。
    private func updateViewDirection(from motion: CMDeviceMotion) {
        let r = motion.attitude.rotationMatrix

        // デバイス座標系での画面奥方向 = (0, 0, -1)
        // ワールド座標系 (xMagneticNorthZVertical) での方向:
        // xWorld = r.m31 * 0 + r.m32 * 0 + r.m33 * (-1) = -r.m33
        // yWorld = r.m21 * 0 + r.m22 * 0 + r.m23 * (-1) = -r.m23  (実際は行列の転置)
        // zWorld = r.m31*0 + ...
        //
        // CMRotationMatrix は行優先: m{行}{列}
        // ワールド → デバイス なので、デバイス→ワールドは転置
        // デバイスZ軸(-1)のワールド表現:
        let wx = -r.m13   // x_world = 北方向
        let wy = -r.m23   // y_world = 東方向 ... 実際は xMagNorthZVert での軸定義による
        let wz = -r.m33   // z_world = 鉛直上方

        // 仰角 = arcsin(wz)
        let altitude = asin(max(-1, min(1, wz))) * 180 / .pi

        // 方位角: atan2(wx_east, wx_north) → ただし xMagNorthZVert の x=北, y=東 (右手系)
        // NightScope の方位角: 0=北, 90=東
        var azimuth = atan2(wy, wx) * 180 / .pi
        if azimuth < 0 { azimuth += 360 }

        viewModel.viewAltitude = altitude
        viewModel.viewAzimuth  = azimuth
    }
}

// MARK: - Preview

#Preview {
    let appController = AppController()
    let vm = StarMapViewModel(appController: appController)
    return iOSStarMapView(viewModel: vm)
        .preferredColorScheme(.dark)
}
