import SwiftUI

/// 各タブ上部で使う共通ヘッダー。
struct iOSTabHeaderView<Subtitle: View, Trailing: View>: View {
    let title: String
    let titleColor: Color
    let subtitleColor: Color
    let titleLineLimit: Int
    let titleMinimumScaleFactor: CGFloat
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
        titleLineLimit: Int = 2,
        titleMinimumScaleFactor: CGFloat = 1,
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
        self.titleLineLimit = titleLineLimit
        self.titleMinimumScaleFactor = titleMinimumScaleFactor
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
                    .lineLimit(titleLineLimit)
                    .minimumScaleFactor(titleMinimumScaleFactor)
                    .allowsTightening(true)

                subtitle()
                    .foregroundStyle(subtitleColor)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, verticalPadding)
        .padding(.bottom, bottomPadding)
    }
}

/// Material パネルの背景と境界線を共通化する ViewModifier。
private struct iOSMaterialPanelModifier: ViewModifier {
    let material: Material
    let cornerRadius: CGFloat
    let style: RoundedCornerStyle
    let showsBorder: Bool

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: style))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: style)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Material パネルの見た目を簡単に適用する。
    func iOSMaterialPanel(
        material: Material = .thinMaterial,
        cornerRadius: CGFloat = Layout.smallCornerRadius,
        style: RoundedCornerStyle = .continuous,
        showsBorder: Bool = true
    ) -> some View {
        modifier(
            iOSMaterialPanelModifier(
                material: material,
                cornerRadius: cornerRadius,
                style: style,
                showsBorder: showsBorder
            )
        )
    }
}
