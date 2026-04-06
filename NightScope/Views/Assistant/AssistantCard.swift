import SwiftUI

/// 星空アシスタントのインライン表示カード（DetailView 埋め込み用）
struct AssistantCard: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if viewModel.isLoading {
                    skeletonContent
                } else if viewModel.summary.isEmpty {
                    emptyContent
                } else {
                    cardContent
                }

                Divider()
                modelFooter
            }
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        }
    }

    // MARK: - Section Title (外部ヘッダー)

    private var sectionTitle: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text("AI星空アシスタント")
                .font(.title3.bold())
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    viewModel.generateContent()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("再生成")
            }
        }
    }

    // MARK: - Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            contentRow(
                icon: "text.bubble.fill",
                accentColor: Color.accentColor,
                label: "今夜の予報",
                body: viewModel.summary
            )

            ForEach(Array(viewModel.advices.enumerated()), id: \.offset) { index, text in
                Divider()
                contentRow(
                    icon: "lightbulb.fill",
                    accentColor: .orange,
                    label: "アドバイス \(index + 1)",
                    body: text
                )
            }
        }
    }

    private func contentRow(icon: String, accentColor: Color, label: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            HStack(spacing: Spacing.xs / 2) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(accentColor)
            }
            Text(body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Loading Skeleton

    private var skeletonContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            contentRow(
                icon: "text.bubble.fill",
                accentColor: Color.accentColor,
                label: String(repeating: "　", count: 5),
                body: String(repeating: "　", count: 60)
            )
            Divider()
            contentRow(
                icon: "lightbulb.fill",
                accentColor: .orange,
                label: String(repeating: "　", count: 6),
                body: String(repeating: "　", count: 50)
            )
            Divider()
            contentRow(
                icon: "lightbulb.fill",
                accentColor: .orange,
                label: String(repeating: "　", count: 6),
                body: String(repeating: "　", count: 45)
            )
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Empty State

    private var emptyContent: some View {
        Text("データを取得中です…")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    // MARK: - Model Footer

    private var modelFooter: some View {
        HStack {
            Spacer()
            Text("AI生成 · \(viewModel.modelLabel.isEmpty ? "読み込み中" : viewModel.modelLabel)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
