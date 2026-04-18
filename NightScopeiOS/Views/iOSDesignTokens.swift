import SwiftUI

enum IOSDesignTokens {
    enum Today {
        static let summaryCardMinHeight: CGFloat = 140
        static let loadingCardHeights: [CGFloat] = [summaryCardMinHeight, summaryCardMinHeight, summaryCardMinHeight]
    }

    enum StarMap {
        static let horizonOverlayStyle = StarMapCanvasView.HorizonOverlayStyle(
            groundFillColor: Color(red: 0.31, green: 0.33, blue: 0.37),
            groundFillOpacity: 0.54,
            horizonStrokeColor: .white.opacity(0.18),
            terrainFillColor: Color(red: 0.27, green: 0.29, blue: 0.33),
            terrainFillOpacity: 0.62,
            terrainStrokeColor: .white.opacity(0.14)
        )
    }

    enum Forecast {
        static let rowSpacing: CGFloat = Spacing.sm
        static let loadingMinHeight: CGFloat = 220
    }

    enum Location {
        static let searchResultsMaxHeight: CGFloat = 176
        static let estimatedSearchResultRowHeight: CGFloat = 52
        static let searchResultsVisibleRowCapacity = searchResultsMaxHeight / estimatedSearchResultRowHeight
        static let searchResultLineSpacing: CGFloat = 2
        static let viewportCoordinateEpsilon = 0.00005
        static let viewportSpanEpsilon = 0.00005
        static let defaultMapHeight: CGFloat = 220
        static let compactMapHeight: CGFloat = 160
    }

    enum NightRow {
        static let cardMinHeight: CGFloat = 80
        static let cardHorizontalPadding: CGFloat = Layout.cardPadding
        static let cardVerticalPadding: CGFloat = Layout.cardPadding
        static let contentSpacing: CGFloat = Spacing.sm / 2
        static let relativeLabelHorizontalPadding: CGFloat = 6
        static let relativeLabelVerticalPadding: CGFloat = 2
        static let starSpacing: CGFloat = 2
        static let inactiveStarOpacity: Double = 0.4
        static let selectionBorderWidth: CGFloat = 2
        static let metadataIconWidth: CGFloat = 14
        static let metadataIconSpacing: CGFloat = 4
        static let metadataGroupSpacing: CGFloat = Spacing.xs
        static let metadataMinimumScaleFactor: CGFloat = 0.78
    }
}
