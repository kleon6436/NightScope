import SwiftUI

extension StarMapCanvasView {
    /// ピンチ操作中の視野角を一時表示する。
    struct PinchFOVOverlayView: View {
        let displayFov: Double

        var body: some View {
            VStack {
                Spacer()
                Text(L10n.format("視野 %.0f°", displayFov))
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

    /// 方角ラベルを画面下端に並べる。
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
            .accessibilityHidden(true)
        }
    }

    /// ジャイロモード中の向きと仰角を示す。
    struct GyroModeIndicatorView: View {
        let azimuth: Double
        let altitude: Double

        var body: some View {
            VStack {
                HStack {
                    Spacer()
                    Text(L10n.format("方位 %.0f° 仰角 %.0f°", azimuth, altitude))
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
