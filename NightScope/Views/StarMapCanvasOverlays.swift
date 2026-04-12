import SwiftUI

extension StarMapCanvasView {
    struct PinchFOVOverlayView: View {
        let displayFov: Double

        var body: some View {
            VStack {
                Spacer()
                Text(String(format: "視野 %.0f°", displayFov))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    struct CardinalOverlayView: View {
        let placements: [CardinalOverlayPlacement]
        let overlayY: Double

        var body: some View {
            ZStack {
                ForEach(placements) { placement in
                    Text(placement.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, StarMapLayout.cardinalLabelHorizontalPadding)
                        .padding(.vertical, StarMapLayout.cardinalLabelVerticalPadding)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .position(x: placement.x, y: overlayY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    struct GyroModeIndicatorView: View {
        let azimuth: Double
        let altitude: Double

        var body: some View {
            VStack {
                HStack {
                    Spacer()
                    Text(String(format: "方位 %.0f° 仰角 %.0f°", azimuth, altitude))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.trailing, Spacing.sm)
                        .padding(.top, Spacing.sm)
                }
                Spacer()
            }
        }
    }
}
