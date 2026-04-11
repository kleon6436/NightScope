import SwiftUI

// MARK: - StarInfoMacView

/// クリックした天体の情報を表示する macOS 用 popover ビュー
struct StarInfoMacView: View {
    let starPosition: StarPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 名前・見出し
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text(displayName)
                    .font(.headline)
            }

            Divider()

            // 等級
            infoRow(icon: "sparkles", label: "等級", value: String(format: "%.1f", starPosition.star.magnitude))

            // 現在の位置
            infoRow(icon: "arrow.up.circle", label: "仰角",
                    value: String(format: "%.1f°", starPosition.altitude))
            infoRow(icon: "arrow.clockwise.circle", label: "方位",
                    value: azimuthText)

            // 地平線上/下
            HStack(spacing: 4) {
                Image(systemName: starPosition.altitude > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(starPosition.altitude > 0 ? .green : .secondary)
                Text(starPosition.altitude > 0 ? "地平線の上" : "地平線の下")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 赤経・赤緯 (J2000.0)
            Text(String(format: "赤経 %.2f°  赤緯 %.2f°", starPosition.star.ra, starPosition.star.dec))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 240)
    }

    private var displayName: String {
        starPosition.star.name.isEmpty
            ? String(format: "%.1f 等星", starPosition.star.magnitude)
            : starPosition.star.name
    }

    private var azimuthText: String {
        let az = starPosition.azimuth
        let normalized = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % 8
        let names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        return String(format: "%@ %.1f°", names[index], az)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }
}
