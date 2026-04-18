import SwiftUI
import CoreMotion

// MARK: - iOSStarMapView

struct iOSStarMapView: View {
    @ObservedObject var viewModel: StarMapViewModel
    @AppStorage(StarDisplayDensity.defaultsKey) private var starDisplayDensityRaw = StarDisplayDensity.defaultValue.rawValue

    @State private var motionManager = CMMotionManager()
    @State private var lastMotionPose: StarMapMotionPose?
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
