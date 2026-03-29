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
    /// 地図コンテナの角丸半径
    static let mapCornerRadius: CGFloat = 8
    /// 地図上ボタン（現在地）の角丸半径
    static let mapButtonCornerRadius: CGFloat = 6
    /// 地図上ボタン（現在地）のサイズ
    static let mapButtonSize: CGFloat = 28
    /// 地図上のアイコンサイズ
    static let mapIconSize: CGFloat = 14
    /// 地図コンテナの枠線太さ
    static let mapSeparatorLineWidth: CGFloat = 0.5
    /// 今後2週間グリッドカードの高さ
    static let upcomingCardHeight: CGFloat = 170
    /// グリッドのアイコン列幅
    static let gridIconWidth: CGFloat = 14
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

// MARK: - Animation

extension Animation {
    /// アプリ標準スプリングアニメーション
    static let standard: Animation = .spring(duration: 0.3)
}

// MARK: - Time Formatting

extension DateFormatter {
    /// HH:mm 形式の夜間時刻フォーマッタ
    static let nightTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()
}

extension Date {
    /// HH:mm 形式の時刻文字列を返す
    func nightTimeString() -> String {
        DateFormatter.nightTime.string(from: self)
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

// MARK: - AppIcons

enum AppIcons {
    enum Navigation {
        static let locationPin      = "mappin.circle.fill"
        static let locationPinPlain = "mappin"
        static let calendar         = "calendar"
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
