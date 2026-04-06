import SwiftUI

/// MLX モデルの選択・ダウンロード・管理 UI
struct MLXModelDownloadView: View {
    @ObservedObject var mlxBackend: MLXBackend
    let onModelSelected: (MLXModelSpec) -> Void

    private let physicalMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ローカル LLM モデル")
                .font(.headline)

            ForEach(MLXModelSpec.builtinModels) { spec in
                modelRow(spec)
            }

            if physicalMemoryGB < 8 {
                Label("搭載 RAM が \(physicalMemoryGB)GB のため、2B モデルを推奨します。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ spec: MLXModelSpec) -> some View {
        let isSelected = mlxBackend.selectedModel?.id == spec.id
        let isLowRAM = physicalMemoryGB < spec.minRAMGB

        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(spec.displayName)
                        .font(.subheadline.bold())
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text(String(format: "約 %.1f GB", spec.sizeGB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLowRAM {
                    Text("RAM \(spec.minRAMGB)GB 以上推奨")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if isSelected {
                stateView(for: mlxBackend.modelState, spec: spec)
            } else {
                Button("選択") {
                    onModelSelected(spec)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isLowRAM)
            }
        }
        .padding(Spacing.xs)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
        )
    }

    @ViewBuilder
    private func stateView(for state: MLXBackend.ModelState, spec: MLXModelSpec) -> some View {
        switch state {
        case .idle:
            Button("ダウンロード") {
                onModelSelected(spec)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

        case .downloading(let progress):
            HStack(spacing: Spacing.xs) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .loading:
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("読込中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loaded:
            Label("使用中", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .error(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Label("エラー", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("再試行") {
                    onModelSelected(spec)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
    }
}
