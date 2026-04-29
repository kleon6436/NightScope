import Foundation

/// NSLocalizedString と数値フォーマットをまとめたローカライズ補助。
enum L10n {
    /// 翻訳キーをそのまま NSLocalizedString に渡して解決する。
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// 翻訳済みフォーマット文字列に引数を差し込む。
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(
            format: tr(key),
            locale: .autoupdatingCurrent,
            arguments: args
        )
    }

    /// 0〜100 の値を割合表記に整形する。
    static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        (value / 100).formatted(
            .percent
                .precision(.fractionLength(fractionDigits))
                .locale(.autoupdatingCurrent)
        )
    }

    /// 小数桁数を指定して数値を整形する。
    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(.autoupdatingCurrent)
        )
    }
}
