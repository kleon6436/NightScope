import SwiftUI

enum IOSDesignTokens {
    enum Today {
        static let summaryCardMinHeight: CGFloat = 140
        static let loadingCardHeights: [CGFloat] = [summaryCardMinHeight, summaryCardMinHeight, summaryCardMinHeight]
    }

    enum Forecast {
        static let rowVerticalInset: CGFloat = Spacing.xs / 2
        static let rowInsets = EdgeInsets(
            top: rowVerticalInset,
            leading: Spacing.sm,
            bottom: rowVerticalInset,
            trailing: Spacing.sm
        )
    }

    enum Location {
        static let searchResultsMaxHeight: CGFloat = 176
        static let searchResultLineSpacing: CGFloat = 2
        static let viewportCoordinateEpsilon = 0.00005
        static let viewportSpanEpsilon = 0.00005
    }

    enum NightRow {
        static let relativeLabelHorizontalPadding: CGFloat = 6
        static let relativeLabelVerticalPadding: CGFloat = 2
        static let starSpacing: CGFloat = 2
        static let inactiveStarOpacity: Double = 0.4
        static let selectionBorderWidth: CGFloat = 2
    }
}
