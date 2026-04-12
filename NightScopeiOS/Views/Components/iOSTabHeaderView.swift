import SwiftUI

struct iOSTabHeaderView<Subtitle: View, Trailing: View>: View {
    let title: String
    let titleColor: Color
    let subtitleColor: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let bottomPadding: CGFloat
    let subtitleSpacing: CGFloat
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        titleColor: Color = .primary,
        subtitleColor: Color = .secondary,
        horizontalPadding: CGFloat = Spacing.sm,
        verticalPadding: CGFloat = Spacing.sm,
        bottomPadding: CGFloat = Spacing.xs,
        subtitleSpacing: CGFloat = Spacing.xs,
        @ViewBuilder subtitle: @escaping () -> Subtitle,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.bottomPadding = bottomPadding
        self.subtitleSpacing = subtitleSpacing
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: subtitleSpacing) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                subtitle()
                    .foregroundStyle(subtitleColor)
            }

            Spacer(minLength: 0)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, verticalPadding)
        .padding(.bottom, bottomPadding)
    }
}
