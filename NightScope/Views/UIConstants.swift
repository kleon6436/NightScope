import SwiftUI
import MapKit

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
    static let mapMaxHeight: CGFloat = 200
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
    /// 今後9日間グリッドカードの高さ
    static let upcomingCardHeight: CGFloat = 170
    /// グリッドのアイコン列幅
    static let gridIconWidth: CGFloat = 14
}

enum SearchResultsLayout {
    static func needsScroll(resultCount: Int, visibleRowCapacity: CGFloat) -> Bool {
        CGFloat(resultCount) > floor(visibleRowCapacity)
    }
}

struct DetailErrorOverlay: View {
    let weatherErrorMessage: String?
    let hasLightPollutionError: Bool
    let retryWeatherAction: () -> Void
    let retryLightPollutionAction: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if hasLightPollutionError {
                DetailErrorBanner(
                    message: L10n.tr("光害データの取得に失敗しました"),
                    retryAction: retryLightPollutionAction
                )
            }
            if let weatherErrorMessage {
                DetailErrorBanner(
                    message: weatherErrorMessage,
                    retryAction: retryWeatherAction
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }
}

private struct DetailErrorBanner: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: AppIcons.Status.warning)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .lineLimit(2)
            Spacer()
            Button("再試行", action: retryAction)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.smallCornerRadius))
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("エラー: %@", message))
    }
}

struct LocationSearchResultContent: View {
    let item: MKMapItem
    let iconSystemName: String
    let titleFont: Font
    let subtitleFont: Font
    let lineSpacing: CGFloat
    let titleFallback: String
    let iconWidth: CGFloat?

    init(
        item: MKMapItem,
        iconSystemName: String = "mappin.circle.fill",
        titleFont: Font = .body,
        subtitleFont: Font = .body,
        lineSpacing: CGFloat = 0,
        titleFallback: String = L10n.tr("不明"),
        iconWidth: CGFloat? = nil
    ) {
        self.item = item
        self.iconSystemName = iconSystemName
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.lineSpacing = lineSpacing
        self.titleFallback = titleFallback
        self.iconWidth = iconWidth
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: iconSystemName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)

            VStack(alignment: .leading, spacing: lineSpacing) {
                Text(item.name ?? titleFallback)
                    .font(titleFont)
                    .foregroundStyle(.primary)

                if let address = item.address,
                   let subtitle = address.shortAddress ?? address.fullAddress.nilIfEmpty {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SelectedLocationSummaryContent: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D
    let titleFont: Font
    let coordinateFont: Font
    let showsAccentIcon: Bool

    init(
        locationName: String,
        coordinate: CLLocationCoordinate2D,
        titleFont: Font = .headline,
        coordinateFont: Font = .body,
        showsAccentIcon: Bool = true
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.titleFont = titleFont
        self.coordinateFont = coordinateFont
        self.showsAccentIcon = showsAccentIcon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if showsAccentIcon {
                    Image(systemName: AppIcons.Navigation.locationPinPlain)
                        .foregroundStyle(Color.accentColor)
                        .font(.body)
                        .accessibilityHidden(true)
                }

                Text(locationName)
                    .font(titleFont)
            }

            Text(String(format: "%.4f°, %.4f°", coordinate.latitude, coordinate.longitude))
                .font(coordinateFont)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    L10n.format("緯度%.4f度、経度%.4f度", coordinate.latitude, coordinate.longitude)
                )
        }
    }
}

// MARK: - Star Map Presentation

enum StarMapLayout {
    static let minFOV: Double = 30
    static let maxFOV: Double = 150
    static let defaultFOV: Double = 60
    static let resetAltitude: Double = 30
    static let directionStep: Double = 5
    static let zoomStep: Double = 10
    static let sliderIconWidth: CGFloat = 18
    static let timeLabelWidth: CGFloat = 52
    static let sheetMinWidth: CGFloat = 900
    static let sheetMinHeight: CGFloat = 820
    static let canvasMinWidth: CGFloat = 860
    static let canvasMinHeight: CGFloat = 620
    static let cardinalLabelBottomInset: CGFloat = 28
    static let cardinalLabelSidePadding: CGFloat = 12
    static let cardinalLabelHorizontalPadding: CGFloat = 8
    static let cardinalLabelVerticalPadding: CGFloat = 4

    static func clampedFOV(_ value: Double) -> Double {
        max(minFOV, min(maxFOV, value))
    }
}

enum StarMapPalette {
    static let canvasBackground = Color(red: 0.02, green: 0.04, blue: 0.12)
    static let groundFill = Color(red: 0.06, green: 0.04, blue: 0.02)
    static let meteorAccent = Color(red: 0.4, green: 1.0, blue: 0.7)

    // MARK: - Dynamic Sky Color

    /// 太陽高度・月光に基づく動的空色を返す
    static func skyColor(sunAltitude: Double, moonAltitude: Double, moonPhase: Double) -> Color {
        let (r, g, b) = skyBaseRGB(sunAltitude: sunAltitude)
        let moonWash = moonBrightness(moonAltitude: moonAltitude, moonPhase: moonPhase)
        return Color(
            red: min(1, r + moonWash * 0.03),
            green: min(1, g + moonWash * 0.04),
            blue: min(1, b + moonWash * 0.08)
        )
    }

    /// 月光による暗い星の減光係数 (1.0 = 影響なし)
    static func moonDimmingFactor(moonBrightness: Double, starMagnitude: Double) -> Double {
        guard moonBrightness > 0, starMagnitude > 3.0 else { return 1.0 }
        let sensitivity = min(1.0, (starMagnitude - 3.0) / 4.0)
        return max(0.2, 1.0 - moonBrightness * sensitivity * 0.6)
    }

    /// 月光の総合的な明るさ (0 = 影響なし, 1 = 最大)
    static func moonBrightness(moonAltitude: Double, moonPhase: Double) -> Double {
        guard moonAltitude > 0 else { return 0 }
        let illumination = (1.0 - cos(moonPhase * 2.0 * .pi)) / 2.0
        return illumination * min(1, moonAltitude / 45)
    }

    /// シンチレーション係数 (1.0 中心の微小変動)
    static func scintillation(
        starRA: Double, magnitude: Double, altitude: Double,
        isDark: Bool, time: Double
    ) -> Double {
        guard isDark, magnitude < 2.0 else { return 1.0 }
        let freq = 2.5 + (starRA.truncatingRemainder(dividingBy: 7)) * 0.4
        let phase = starRA * 137.5
        let altFactor = altitude < 30 ? (1.5 - altitude / 60) : 1.0
        let amplitude = (2.0 - magnitude) / 2.0 * 0.15 * altFactor
        return 1.0 + amplitude * sin(time * freq + phase)
    }

    // MARK: - Private

    private static let skyColorStops: [(alt: Double, r: Double, g: Double, b: Double)] = [
        (alt:  10, r: 0.40, g: 0.60, b: 0.85),
        (alt:   5, r: 0.30, g: 0.40, b: 0.70),
        (alt:   0, r: 0.20, g: 0.15, b: 0.40),
        (alt:  -6, r: 0.08, g: 0.08, b: 0.25),
        (alt: -12, r: 0.04, g: 0.06, b: 0.18),
        (alt: -18, r: 0.02, g: 0.04, b: 0.12),
    ]

    private static func skyBaseRGB(sunAltitude: Double) -> (Double, Double, Double) {
        let stops = skyColorStops
        if sunAltitude >= stops[0].alt {
            return (stops[0].r, stops[0].g, stops[0].b)
        }
        if sunAltitude <= stops[stops.count - 1].alt {
            return (stops[stops.count - 1].r, stops[stops.count - 1].g, stops[stops.count - 1].b)
        }
        for i in 0..<(stops.count - 1) {
            let upper = stops[i]
            let lower = stops[i + 1]
            if sunAltitude <= upper.alt && sunAltitude >= lower.alt {
                let t = (sunAltitude - lower.alt) / (upper.alt - lower.alt)
                return (
                    lower.r + (upper.r - lower.r) * t,
                    lower.g + (upper.g - lower.g) * t,
                    lower.b + (upper.b - lower.b) * t
                )
            }
        }
        return (0.02, 0.04, 0.12)
    }
}

enum StarMapPresentation {
    private static let azimuthNames = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]

    static func azimuthName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % azimuthNames.count
        return L10n.tr(azimuthNames[index])
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
    /// 要約カード4枚の共通最小幅
    static let summaryCardMinWidth: CGFloat = 280
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

// MARK: - Card Visual

enum CardVisual {
    /// カード左側ビジュアルの統一幅
    static let width: CGFloat = 52
    /// 半円ゲージの統一高さ
    static let arcHeight: CGFloat = 28
    /// 月相アイコンのフォントサイズ
    static let moonIconSize: CGFloat = 40
    /// 方角インジケーターのサイズ（正方形）
    static let compassSize: CGFloat = 44
    /// ゲージ共通のストローク幅
    static let strokeWidth: Double = 5
    /// ゲージ共通のトラック透過度
    static let trackOpacity: Double = 0.12
}

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

// MARK: - CardHeader

/// 全カード共通のヘッダー（SF Symbol アイコン + カテゴリラベル）
struct CardHeader: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Animation

extension Animation {
    /// アプリ標準スプリングアニメーション
    static let standard: Animation = .spring(duration: 0.3)
}

// MARK: - Time Formatting

private enum FormatterFactory {
    static func observationTimeZone(dateFormat: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.timeZone = timeZone
        return formatter
    }

    static func observationTimeZone(
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = timeZone
        return formatter
    }

    static func localizedDate(
        template: String,
        timeZone: TimeZone = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatter.timeZone = timeZone
        return formatter
    }
}

enum DateFormatters {
    static func nightTimeString(from date: Date, timeZone: TimeZone = .current) -> String {
        FormatterFactory.observationTimeZone(dateFormat: "HH:mm", timeZone: timeZone).string(from: date)
    }

    static func monthTitleString(from date: Date, timeZone: TimeZone = .current) -> String {
        FormatterFactory.localizedDate(template: "yMMMM", timeZone: timeZone).string(from: date)
    }

    static func fullDateString(from date: Date, timeZone: TimeZone = .current) -> String {
        FormatterFactory.observationTimeZone(
            dateStyle: .full,
            timeStyle: .none,
            timeZone: timeZone
        )
        .string(from: date)
    }

    static func yearMonthDayWeekdayString(from date: Date, timeZone: TimeZone = .current) -> String {
        FormatterFactory.localizedDate(template: "yMMMMEEEEd", timeZone: timeZone).string(from: date)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Date {
    /// HH:mm 形式の時刻文字列を返す
    func nightTimeString(timeZone: TimeZone = .current) -> String {
        DateFormatters.nightTimeString(from: self, timeZone: timeZone)
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
    static func primaryLabel(for weather: DayWeatherSummary) -> String {
        weather.weatherLabel
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
    let timeZone: TimeZone
    let isReliableWeather: Bool
    let hasPartialWeather: Bool
    let isForecastOutOfRange: Bool
    let hasWeatherLoadError: Bool

    var shortDateLabel: String {
        FormatterFactory.localizedDate(template: "MEd", timeZone: timeZone).string(from: night.date)
    }

    var relativeNightLabel: String? {
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        if ObservationTimeZone.isDateInToday(night.date, timeZone: timeZone) { return L10n.tr("今夜") }
        if calendar.isDateInTomorrow(night.date) { return L10n.tr("明夜") }
        return nil
    }

    var cloudCoverText: String {
        guard isReliableWeather, let weather else { return "—" }
        return L10n.percent(weather.avgCloudCover)
    }

    var weatherDetailText: String? {
        if isReliableWeather, let weather {
            return WeatherPresentation.primaryLabel(for: weather)
        }
        if hasPartialWeather { return L10n.tr("夜間予報は一部のみ") }
        if isForecastOutOfRange { return L10n.tr("天気予報対象外") }
        if hasWeatherLoadError { return L10n.tr("取得失敗") }
        return nil
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
    @Entry var observationTimeZone: TimeZone? = nil
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
        case .knot: return L10n.tr("ノット (kn)")
        }
    }

    /// WeatherService が km/h に変換済みの風速値をこの単位に変換してフォーマットする
    func format(_ kmh: Double) -> String {
        switch self {
        case .kmh:  return L10n.format("風速 %.0f km/h", kmh)
        case .ms:   return L10n.format("風速 %.1f m/s", kmh / 3.6)
        case .knot: return L10n.format("風速 %.0f kn", kmh / 1.852)
        }
    }
}
