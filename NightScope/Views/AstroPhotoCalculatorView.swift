import SwiftUI

/// 天体写真の撮影設定を入力して推奨値を確認する共通ビュー。
/// シートとして表示する場合は `isSheet: true`（デフォルト）、タブとして埋め込む場合は `isSheet: false`。
struct AstroPhotoCalculatorView: View {
    @StateObject private var viewModel: AstroPhotoCalculatorViewModel
    @Environment(\.dismiss) private var dismiss
    private let isSheet: Bool

    init(bortleClass: Double?, isSheet: Bool = true) {
        _viewModel = StateObject(wrappedValue: AstroPhotoCalculatorViewModel(bortleClass: bortleClass))
        self.isSheet = isSheet
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle("天体写真設定")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    private var formContent: some View {
        Form {
            lensSection
            sensorSection
            captureSection
            bortleSection
            resultsSection
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var lensSection: some View {
        Section("レンズ設定") {
            numericInputRow(
                title: "焦点距離 (mm)",
                binding: focalLengthBinding,
                format: .number.precision(.fractionLength(0)),
                range: 1...2400,
                step: 1
            )

            numericInputRow(
                title: "絞り (F値)",
                binding: apertureBinding,
                format: .number.precision(.fractionLength(1)),
                range: 1...22,
                step: 0.1
            )
        }
    }

    private var sensorSection: some View {
        Section("センサー設定") {
            Picker("センサーサイズ", selection: $viewModel.sensorSize) {
                ForEach(SensorSize.allCases) { sensorSize in
                    Text(sensorSize.rawValue).tag(sensorSize)
                }
            }

            if viewModel.sensorSize != .custom {
                numericInputRow(
                    title: "画素数 (MP)",
                    binding: megapixelsBinding,
                    format: .number.precision(.fractionLength(0)),
                    range: 1...200,
                    step: 1
                )

                LabeledContent("ピクセルピッチ (µm)（参考）") {
                    Text(viewModel.effectivePixelPitch, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                numericInputRow(
                    title: "カスタムピクセルピッチ (µm)",
                    binding: customPixelPitchBinding,
                    format: .number.precision(.fractionLength(1)),
                    range: 0.1...20,
                    step: 0.1
                )
            }
        }
    }

    private var captureSection: some View {
        Section("撮影設定") {
            Toggle("スタッキング撮影", isOn: $viewModel.isStacking)

            if viewModel.isStacking {
                HStack {
                    Text("目標枚数")
                    Spacer()
                    Stepper(value: $viewModel.targetFrameCount, in: 10...200, step: 5) {
                        Text("\(viewModel.targetFrameCount) 枚")
                    }
                }
            }
        }
    }

    private var bortleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Slider(value: bortleSliderBinding, in: 1...9, step: 1)
                Text("現在値: Bortle \(viewModel.bortleClass)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("光害（Bortle クラス）")
                Text("観測地点から自動取得")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section("計算結果") {
            if let settings = viewModel.settings {
                LabeledContent("推奨 ISO") {
                    Text("\(settings.recommendedISO)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                LabeledContent("シャッタースピード") {
                    Text(shutterDisplayText(settings.shutterSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if settings.totalMinutes > 0 {
                    LabeledContent("合計露出時間") {
                        Text("\(settings.totalMinutes) 分")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isStacking {
                    LabeledContent("推奨枚数") {
                        Text("\(settings.frameCount) 枚")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("入力値を確認してください")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func numericInputRow(
        title: String,
        binding: Binding<Double>,
        format: FloatingPointFormatStyle<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline)

            HStack(spacing: Spacing.sm) {
                TextField("", value: binding, format: format)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Stepper(value: binding, in: range, step: step) {
                    Text(title).hidden()
                }
                .labelsHidden()
            }
        }
    }

    private var focalLengthBinding: Binding<Double> {
        Binding(
            get: { viewModel.focalLength },
            set: { viewModel.focalLength = clamp($0, lowerBound: 1, upperBound: 2400) }
        )
    }

    private var apertureBinding: Binding<Double> {
        Binding(
            get: { viewModel.aperture },
            set: { viewModel.aperture = clamp($0, lowerBound: 1, upperBound: 22) }
        )
    }

    private var megapixelsBinding: Binding<Double> {
        Binding(
            get: { viewModel.megapixels },
            set: { viewModel.megapixels = clamp($0.rounded(), lowerBound: 1, upperBound: 200) }
        )
    }

    private var customPixelPitchBinding: Binding<Double> {
        Binding(
            get: { viewModel.customPixelPitch },
            set: { viewModel.customPixelPitch = clamp($0, lowerBound: 0.1, upperBound: 20) }
        )
    }

    private var bortleSliderBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.bortleClass) },
            set: { viewModel.bortleClass = clamp(Int($0.rounded()), lowerBound: 1, upperBound: 9) }
        )
    }

    private func shutterDisplayText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "-" }
        if seconds >= 1 {
            return "\(L10n.number(seconds, fractionDigits: 1)) 秒"
        }

        let denominator = max(1, Int((1 / seconds).rounded()))
        return "1/\(denominator) 秒"
    }

    private func clamp<T: Comparable>(_ value: T, lowerBound: T, upperBound: T) -> T {
        min(max(value, lowerBound), upperBound)
    }
}

#Preview {
    AstroPhotoCalculatorView(bortleClass: 4)
}
