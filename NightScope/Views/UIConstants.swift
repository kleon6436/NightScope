import SwiftUI

// MARK: - Spacing

enum Spacing {
    /// 8pt
    static let xs: CGFloat = 8
    /// 16pt
    static let sm: CGFloat = 16
    /// 24pt
    static let md: CGFloat = 24
    /// 32pt
    static let lg: CGFloat = 32
}

// MARK: - Layout

enum Layout {
    /// カードの角丸半径
    static let cardCornerRadius: CGFloat = 12
    /// カードの内側パディング
    static let cardPadding: CGFloat = 16
    /// 検索結果・小コンポーネントの角丸半径
    static let smallCornerRadius: CGFloat = 8
    /// サイドバー水平パディング
    static let sidebarHorizontalPadding: CGFloat = 16
    /// サイドバー垂直パディング
    static let sidebarVerticalPadding: CGFloat = 16
    /// 地図コンテナの角丸半径
    static let mapCornerRadius: CGFloat = 8
    /// 地図コンテナ内の補助ラベル間隔
    static let mapInstructionSpacing: CGFloat = 8
    /// 地図コンテナの最小高
    static let mapMinHeight: CGFloat = 160
    /// 地図コンテナの最大高
    static let mapMaxHeight: CGFloat = 280
    /// 地図上ボタン（現在地）の角丸半径
    static let mapButtonCornerRadius: CGFloat = 6
    /// 地図上ボタン（現在地）のサイズ
    static let mapButtonSize: CGFloat = 28
    /// 地図上のアイコンサイズ
    static let mapIconSize: CGFloat = 14
    /// 地図コンテナの枠線太さ
    static let mapSeparatorLineWidth: CGFloat = 0.5
    /// サイドバー補助ラベルの固定幅
    static let sidebarStatusWidth: CGFloat = 64
    /// 今後2週間グリッドカードの高さ
    static let upcomingCardHeight: CGFloat = 170
    /// グリッドのアイコン列幅
    static let gridIconWidth: CGFloat = 14
}

// MARK: - Star Map Presentation

enum StarMapLayout {
    static let minFOV: Double = 30
    static let maxFOV: Double = 150
    static let defaultFOV: Double = 90
    static let resetAltitude: Double = 30
    static let panoramaBottomMargin: CGFloat = 28
    static let panoramaCardinalLabelOffset: CGFloat = 12
    static let directionStep: Double = 5
    static let zoomStep: Double = 10
    static let sliderIconWidth: CGFloat = 18
    static let timeLabelWidth: CGFloat = 52
    static let sheetMinWidth: CGFloat = 900
    static let sheetMinHeight: CGFloat = 820
    static let canvasMinWidth: CGFloat = 860
    static let canvasMinHeight: CGFloat = 620

    static func clampedFOV(_ value: Double) -> Double {
        max(minFOV, min(maxFOV, value))
    }

    static func panoramaMaxAltitude(size: CGSize, fov: Double,
                                    bottomMargin: CGFloat = panoramaBottomMargin) -> Double {
        let clampedFOV = clampedFOV(fov)
        guard size.width > 0, size.height > 0, clampedFOV > 0 else {
            return 90
        }

        let hScale = size.width / clampedFOV
        guard hScale > 0 else { return 90 }

        let usableHeight = max(0, size.height / 2 - bottomMargin)
        return max(0, min(90, Double(usableHeight) / hScale))
    }

    /// パノラマ操作時に地平線が上へ逃げすぎないようにする下限。
    /// 初期表示の下端寄せと同じ幾何条件を使う。
    static func panoramaLowerBoundAltitude(size: CGSize, fov: Double,
                                           bottomMargin: CGFloat = panoramaBottomMargin) -> Double {
        preferredPanoramaAltitude(size: size, fov: fov, bottomMargin: bottomMargin)
    }

    static func preferredPanoramaAltitude(size: CGSize, fov: Double,
                                          bottomMargin: CGFloat = panoramaBottomMargin) -> Double {
        guard size.width > 0, size.height > 0 else { return resetAltitude }
        return panoramaMaxAltitude(size: size, fov: fov, bottomMargin: bottomMargin)
    }

    static func clampedPanoramaAltitude(_ altitude: Double, size: CGSize, fov: Double,
                                        bottomMargin: CGFloat = panoramaBottomMargin) -> Double {
        let lowerBound = panoramaLowerBoundAltitude(size: size, fov: fov, bottomMargin: bottomMargin)
        return max(lowerBound, min(90, altitude))
    }

    static func panoramaHorizonY(altitude: Double, size: CGSize, fov: Double) -> Double {
        let clampedFOV = clampedFOV(fov)
        guard size.width > 0 else { return size.height / 2 }
        let hScale = size.width / clampedFOV
        return (size.height / 2) + altitude * hScale
    }
}

enum StarMapPalette {
    static let canvasBackground = Color(red: 0.02, green: 0.04, blue: 0.12)
    static let groundFill = Color(red: 0.06, green: 0.04, blue: 0.02)
    static let meteorAccent = Color(red: 0.4, green: 1.0, blue: 0.7)
}

enum StarMapPresentation {
    private static let azimuthNames = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]

    static func azimuthName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % azimuthNames.count
        return azimuthNames[index]
    }

    static func timeString(from minutes: Double) -> String {
        let hour = Int(minutes) / 60
        let minute = Int(minutes) % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

#if os(macOS)
enum LayoutMacOS {
    /// ウィンドウ最小幅
    static let windowMinWidth: CGFloat = 820
    /// ウィンドウ最小高
    static let windowMinHeight: CGFloat = 750
    /// サイドバー最小幅
    static let sidebarMinWidth: CGFloat = 260
    /// サイドバー理想幅
    static let sidebarIdealWidth: CGFloat = 280
    /// サイドバー最大幅
    static let sidebarMaxWidth: CGFloat = 300
}
#endif

#if os(iOS)
enum LayoutiOS {
    /// 2カラムグリッドのカード最小高さ
    static let gridCardMinHeight: CGFloat = 140
    /// グリッドの列間隔
    static let gridSpacing: CGFloat = Spacing.sm
}
#endif

// MARK: - GlassCard ViewModifier

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - Animation

extension Animation {
    /// アプリ標準スプリングアニメーション
    static let standard: Animation = .spring(duration: 0.3)
}

// MARK: - Time Formatting

private enum FormatterFactory {
    static func currentTimeZone(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.timeZone = .current
        return formatter
    }

    static func currentTimeZone(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = .current
        return formatter
    }

    static func localizedDate(localeIdentifier: String, dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateFormat = dateFormat
        return formatter
    }
}

enum DateFormatters {
    /// HH:mm 形式の夜間時刻フォーマッタ
    static let nightTime = FormatterFactory.currentTimeZone(dateFormat: "HH:mm")

    /// カレンダー見出し（yyyy年M月）
    static let monthTitle = FormatterFactory.currentTimeZone(dateFormat: "yyyy年M月")

    /// アクセシビリティ用の完全日付
    static let fullDate = FormatterFactory.currentTimeZone(dateStyle: .full, timeStyle: .none)
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Date {
    /// HH:mm 形式の時刻文字列を返す
    func nightTimeString() -> String {
        DateFormatters.nightTime.string(from: self)
    }
}

// MARK: - StarGazingIndex.Tier Color

extension StarGazingIndex.Tier {
    var color: Color {
        switch self {
        case .excellent, .good: return .green
        case .fair:             return .yellow
        case .poor:             return .orange
        case .bad:              return .red
        }
    }
}

// MARK: - Weather Presentation

enum WeatherPresentation {
    static func combinedLabel(for weather: DayWeatherSummary) -> String {
        weather.weatherLabel == weather.cloudLabel
            ? weather.weatherLabel
            : "\(weather.weatherLabel)（\(weather.cloudLabel)）"
    }

    static func color(forWeatherCode code: Int) -> Color {
        switch code {
        case 0, 1:       return .yellow
        case 2:          return .secondary
        case 3:          return .secondary
        case 45, 48:     return .secondary
        case 51...65:    return .blue
        case 71...77:    return Color.blue.opacity(0.7)
        case 80...82:    return .blue
        case 85, 86:     return Color.blue.opacity(0.7)
        case 95...99:    return .orange
        default:         return .secondary
        }
    }
}

// MARK: - Forecast Card Presentation

struct ForecastCardPresentation {
    let night: NightSummary
    let weather: DayWeatherSummary?

    private static let shortDateFormatter = FormatterFactory.localizedDate(
        localeIdentifier: "ja_JP",
        dateFormat: "M/d(E)"
    )

    var shortDateLabel: String {
        Self.shortDateFormatter.string(from: night.date)
    }

    var relativeNightLabel: String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(night.date) { return "今夜" }
        if calendar.isDateInTomorrow(night.date) { return "明夜" }
        return nil
    }

    var cloudCoverText: String {
        weather.map { String(format: "%.0f%%", $0.avgCloudCover) } ?? "—"
    }

    var weatherDetailText: String? {
        weather.map { WeatherPresentation.combinedLabel(for: $0) }
    }
}

// MARK: - AppIcons

enum AppIcons {
    enum Navigation {
        static let locationPin      = "mappin.circle.fill"
        static let locationPinPlain = "mappin"
        static let calendar         = "calendar"
        static let currentLocation  = "location.fill"
    }
    enum Astronomy {
        static let star         = "star"
        static let starFill     = "star.fill"
        static let moonStars    = "moon.stars"
        static let moonZzz      = "moon.zzz"
        static let moonFill     = "moon.fill"
        static let sparkles     = "sparkles"
        // 月相（8段階）
        static let moonPhaseNew             = "moonphase.new.moon"
        static let moonPhaseWaxingCrescent  = "moonphase.waxing.crescent"
        static let moonPhaseFirstQuarter    = "moonphase.first.quarter"
        static let moonPhaseWaxingGibbous   = "moonphase.waxing.gibbous"
        static let moonPhaseFull            = "moonphase.full.moon"
        static let moonPhaseWaningGibbous   = "moonphase.waning.gibbous"
        static let moonPhaseLastQuarter     = "moonphase.last.quarter"
        static let moonPhaseWaningCrescent  = "moonphase.waning.crescent"
    }
    enum Weather {
        static let cloud              = "cloud"
        static let cloudFill          = "cloud.fill"
        static let sunMaxFill         = "sun.max.fill"
        static let cloudSunFill       = "cloud.sun.fill"
        static let cloudFogFill       = "cloud.fog.fill"
        static let cloudDrizzleFill   = "cloud.drizzle.fill"
        static let cloudRainFill      = "cloud.rain.fill"
        static let cloudHeavyrainFill = "cloud.heavyrain.fill"
        static let cloudSnowFill      = "cloud.snow.fill"
        static let cloudBoltFill      = "cloud.bolt.fill"
        static let cloudBoltRainFill  = "cloud.bolt.rain.fill"
    }
    enum Status {
        static let warning       = "exclamationmark.triangle"
        static let checkmarkFill = "checkmark.circle.fill"
    }
    enum Controls {
        static let chevronLeft  = "chevron.left"
        static let chevronRight = "chevron.right"
        static let chevronDown  = "chevron.down"
    }
    enum Observation {
        static let clock         = "clock"
        static let altitudeArrow = "arrow.up"
        static let azimuthArrow  = "location.north.fill"
    }
}

// MARK: - FocusedValues

extension FocusedValues {
    @Entry var selectedDate: Binding<Date>? = nil
    @Entry var refreshAction: (() -> Void)? = nil
    @Entry var focusSearchAction: (() -> Void)? = nil
    @Entry var currentLocationAction: (() -> Void)? = nil
}

// MARK: - WindSpeedUnit

enum WindSpeedUnit: String, CaseIterable, Identifiable {
    case kmh  = "km/h"
    case ms   = "m/s"
    case knot = "kn"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kmh:  return "km/h"
        case .ms:   return "m/s"
        case .knot: return "ノット (kn)"
        }
    }

    /// WeatherService が km/h に変換済みの風速値をこの単位に変換してフォーマットする
    func format(_ kmh: Double) -> String {
        switch self {
        case .kmh:  return String(format: "風速 %.0f km/h", kmh)
        case .ms:   return String(format: "風速 %.1f m/s", kmh / 3.6)
        case .knot: return String(format: "風速 %.0f kn", kmh / 1.852)
        }
    }
}
