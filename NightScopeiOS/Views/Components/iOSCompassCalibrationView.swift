import SwiftUI

// MARK: - コンパスキャリブレーションシート

/// コンパス方位補正の専用シート。
/// - リアルタイム方位角とコンパスローズを表示する。
/// - 補正ボタンはジャイロ稼働中のみ有効（停止中の誤補正を防ぐ）。
@MainActor
struct iOSCompassCalibrationView: View {
    @ObservedObject var motionController: StarMapMotionController
    @AppStorage(StarMapDisplaySettings.compassAzimuthOffsetDefaultsKey)
    private var storedOffset: Double = 0

    @State private var justCalibrated = false

    private var hasOffset: Bool { storedOffset != 0 }

    var body: some View {
        List {
            Section {
                compassRoseSection
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                infoRows
            }
            Section {
                calibrateButton
                resetButton
            }
            Section {
                instructionRow
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tr("コンパスキャリブレーション"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - コンパスローズ

    private var compassRoseSection: some View {
        ZStack {
            // 外周リング
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
                .frame(width: 200, height: 200)

            // 方位ラベル（N は赤）
            Text("N")
                .foregroundStyle(.red)
                .font(.caption.weight(.bold))
                .offset(y: -88)
            Text("S")
                .foregroundStyle(.secondary)
                .font(.caption.weight(.bold))
                .offset(y: 88)
            Text("E")
                .foregroundStyle(.secondary)
                .font(.caption.weight(.bold))
                .offset(x: 88)
            Text("W")
                .foregroundStyle(.secondary)
                .font(.caption.weight(.bold))
                .offset(x: -88)

            // コンパス針（現在の方位を指す）
            Image(systemName: "location.north.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(needleColor)
                .rotationEffect(
                    .degrees(motionController.isMotionActive ? motionController.calibrationAzimuth : 0)
                )

            // 補正完了チェックマーク
            if justCalibrated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .animation(.easeOut(duration: 0.15), value: justCalibrated)
    }

    /// 磁気精度に応じた針の色。精度不明（xTrueNorthZVertical）はブルー。
    private var needleColor: Color {
        guard motionController.isMotionActive else { return .secondary }
        guard let accuracy = motionController.headingAccuracy else { return .blue }
        if accuracy < 5 { return .green }
        if accuracy < 15 { return .yellow }
        return .orange
    }

    // MARK: - 情報行

    @ViewBuilder
    private var infoRows: some View {
        LabeledContent(L10n.tr("現在の方位角")) {
            Text(
                motionController.isMotionActive
                    ? String(format: "%.1f°", motionController.calibrationAzimuth)
                    : "—"
            )
        }
        Stepper(
            value: $storedOffset,
            in: -180.0...180.0,
            step: 0.5
        ) {
            LabeledContent(L10n.tr("補正オフセット")) {
                Text(hasOffset ? String(format: "%.1f°", storedOffset) : L10n.tr("未設定"))
                    .foregroundStyle(hasOffset ? .primary : .secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityValue(hasOffset ? String(format: "%.1f°", storedOffset) : L10n.tr("未設定"))
        Slider(value: $storedOffset, in: -180.0...180.0, step: 0.5) {
            Text(L10n.tr("補正オフセット"))
        } minimumValueLabel: {
            Text("-180°").font(.caption2).foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("180°").font(.caption2).foregroundStyle(.secondary)
        }
        .tint(.accentColor)
        if let accuracy = motionController.headingAccuracy {
            LabeledContent(L10n.tr("磁気精度")) {
                Text(accuracyLabel(accuracy))
                    .foregroundStyle(accuracyColor(accuracy))
            }
        }
    }

    // MARK: - アクションボタン

    private var calibrateButton: some View {
        Button {
            performCalibration()
        } label: {
            Label(L10n.tr("現在の向きで補正"), systemImage: "location.north.fill")
        }
        .disabled(!motionController.isMotionActive)
        .accessibilityHint(L10n.tr("デバイスを真北に向けた状態でタップしてください"))
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            resetCalibration()
        } label: {
            Label(L10n.tr("補正をリセット"), systemImage: "arrow.counterclockwise")
        }
        .disabled(!hasOffset)
        .accessibilityHint(L10n.tr("保存済みの補正オフセットを削除します"))
    }

    private var instructionRow: some View {
        Group {
            if !motionController.isMotionActive {
                Label(
                    L10n.tr("ジャイロ操作が有効なときに補正できます"),
                    systemImage: "gyroscope"
                )
            } else {
                Text(
                    L10n.tr("デバイスを真北に向けた状態で「現在の向きで補正」をタップすると、その方向を 0°（北）として補正します。")
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - ロジック

    private func performCalibration() {
        let azimuth = motionController.calibrationAzimuth
        var newOffset = -azimuth
        if newOffset < -180 { newOffset += 360 }
        if newOffset > 180 { newOffset -= 360 }
        storedOffset = newOffset

        withAnimation {
            justCalibrated = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                justCalibrated = false
            }
        }
    }

    private func resetCalibration() {
        storedOffset = 0
        justCalibrated = false
    }

    private func accuracyLabel(_ accuracy: Double) -> String {
        if accuracy < 5 { return L10n.format("良好（±%d°）", Int(accuracy)) }
        if accuracy < 15 { return L10n.format("普通（±%d°）", Int(accuracy)) }
        return L10n.format("低い（±%d°）", Int(accuracy))
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy < 5 { return .green }
        if accuracy < 15 { return .yellow }
        return .orange
    }
}

// MARK: - スタンドアローン版（設定画面から遷移する場合）

/// 設定画面の NavigationLink から表示する際に使用する自立型ラッパー。
/// 独自の `StarMapMotionController` を保持し、表示/非表示に合わせてモーションを開始/停止する。
@MainActor
struct iOSCompassCalibrationStandaloneView: View {
    @StateObject private var motionController = StarMapMotionController()

    var body: some View {
        iOSCompassCalibrationView(motionController: motionController)
            .onAppear {
                motionController.start(onPoseUpdate: { _ in }, onFailure: { })
            }
            .onDisappear {
                motionController.stop()
            }
    }
}
