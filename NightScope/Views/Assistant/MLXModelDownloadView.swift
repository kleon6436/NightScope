import SwiftUI

/// AI バックエンド（Apple Intelligence / MLX モデル）の選択・管理 UI
struct MLXModelDownloadView: View {
    @ObservedObject var mlxBackend: MLXBackend
    @AppStorage("llm_backend") private var llmBackendRaw: String = LLMBackendKind.appleIntelligence.rawValue
    let onModelSelected: (MLXModelSpec) -> Void
    let onModelDeleted: (MLXModelSpec) async -> Void
    @State private var completedDeletions: Set<String> = []

    private let physicalMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    private var selectedBackend: LLMBackendKind {
        LLMBackendKind(rawValue: llmBackendRaw) ?? .appleIntelligence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            appleIntelligenceRow

            Divider()

            Text("ローカル LLM モデル (MLX)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(MLXModelSpec.builtinModels) { spec in
                mlxModelRow(spec)
            }

            if physicalMemoryGB < 8 {
                Label("搭載 RAM が \(physicalMemoryGB)GB のため、軽量モデルを推奨します。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Apple Intelligence Row

    private var appleIntelligenceRow: some View {
        let isActive = selectedBackend == .appleIntelligence
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "apple.logo")
                        .font(.subheadline)
                    Text("Apple Intelligence")
                        .font(.subheadline.bold())
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text("オンデバイス・デフォルト")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Label("使用中", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("選択") {
                    llmBackendRaw = LLMBackendKind.appleIntelligence.rawValue
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(Spacing.xs)
        .background(
            isActive ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
        )
    }

    // MARK: - MLX Model Row

    @ViewBuilder
    private func mlxModelRow(_ spec: MLXModelSpec) -> some View {
        let isActive = selectedBackend == .mlx && mlxBackend.selectedModel?.id == spec.id
        let isDownloaded = mlxBackend.isDownloaded(spec: spec)
        let isLowRAM = physicalMemoryGB < spec.minRAMGB
        let state = isActive ? mlxBackend.modelState : .idle

        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(spec.displayName)
                        .font(.subheadline.bold())
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                HStack(spacing: Spacing.xs) {
                    Text(String(format: "約 %.1f GB", spec.sizeGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isDownloaded && !isActive {
                        Text("· キャッシュ済")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if isLowRAM {
                    Text("RAM \(spec.minRAMGB)GB 以上推奨")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                // 削除ボタン（ダウンロード済みの場合に表示）
                if isDownloaded || isActive || completedDeletions.contains(spec.id) {
                    let isDeleting = mlxBackend.deletingModelIDs.contains(spec.id)
                    let isCompleted = completedDeletions.contains(spec.id)

                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    } else if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .frame(width: 20, height: 20)
                    } else {
                        Button {
                            Task {
                                await onModelDeleted(spec)
                                completedDeletions.insert(spec.id)
                                try? await Task.sleep(for: .seconds(0.8))
                                completedDeletions.remove(spec.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.8))
                        .help("キャッシュを削除")
                        .disabled(isActive && state == .loaded)
                    }
                }

                // メインアクション
                if isActive {
                    activeStateView(state: state, spec: spec)
                } else if isDownloaded {
                    Button("切替") {
                        switchToMLX(spec: spec)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isLowRAM)
                } else {
                    Button("取得") {
                        switchToMLX(spec: spec)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isLowRAM)
                }
            }
        }
        .padding(Spacing.xs)
        .background(
            isActive ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
        )
    }

    @ViewBuilder
    private func activeStateView(state: MLXBackend.ModelState, spec: MLXModelSpec) -> some View {
        switch state {
        case .idle:
            Button("ロード") {
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

    // MARK: - Helpers

    private func switchToMLX(spec: MLXModelSpec) {
        if selectedBackend != .mlx {
            llmBackendRaw = LLMBackendKind.mlx.rawValue
        }
        onModelSelected(spec)
    }
}
