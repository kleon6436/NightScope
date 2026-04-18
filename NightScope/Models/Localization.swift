import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(
            format: tr(key),
            locale: .autoupdatingCurrent,
            arguments: args
        )
    }

    static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        (value / 100).formatted(
            .percent
                .precision(.fractionLength(fractionDigits))
                .locale(.autoupdatingCurrent)
        )
    }

    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(.autoupdatingCurrent)
        )
    }
}
