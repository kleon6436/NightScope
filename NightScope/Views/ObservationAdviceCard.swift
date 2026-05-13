import SwiftUI

struct ObservationAdviceCard: View {
    @ObservedObject var viewModel: ObservationAdvisorViewModel
    let input: ObservationAdvisorInput

    var body: some View {
        if viewModel.state != .unavailable {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    CardHeader(
                        icon: AppIcons.Astronomy.sparkles,
                        iconColor: .mint,
                        title: String(localized: "advice.card.title")
                    )
                    Spacer()
                    regenerateButton
                }

                content
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            Text(LocalizedStringKey("advice.card.subtitle"))
                .foregroundStyle(.secondary)
        case .loading:
            placeholder
        case .streaming(let text):
            HStack(alignment: .top, spacing: 0) {
                adviceText(text)
                Text(" ▍").accessibilityHidden(true)
            }
        case .complete(let text):
            adviceText(text)
        case .error(let message):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message)
                    .foregroundStyle(.secondary)
                regenerateButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unavailable:
            EmptyView()
        }
    }

    private var regenerateButton: some View {
        Button {
            viewModel.generate(input: input)
        } label: {
            Label(String(localized: "advice.card.regenerate"), systemImage: "arrow.clockwise")
        }
        .glassButtonStyle()
        .disabled(matchesLoadingState)
    }

    private var matchesLoadingState: Bool {
        if case .loading = viewModel.state {
            return true
        }
        return false
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(.quaternary)
                .frame(height: 16)
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(.quaternary)
                .frame(height: 16)
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(.quaternary)
                .frame(maxWidth: 320)
                .frame(height: 16)
        }
        .redacted(reason: .placeholder)
    }

    private func adviceText(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
