import Foundation

extension Decimal {
    func currencyText(_ locale: Locale, signed: Bool = false, fractionDigits: Int = 2) -> String {
        let style = Decimal.FormatStyle.Currency(code: "TRY", locale: locale)
            .presentation(.narrow)
            .precision(.fractionLength(fractionDigits))
        let text = formatted(style)
        return signed && self > 0 ? "+" + text : text
    }

    func gramsText(_ locale: Locale, signed: Bool = false) -> String {
        let text = formatted(.number.precision(.fractionLength(0...3)).locale(locale)) + " g"
        return signed && self > 0 ? "+" + text : text
    }
}

extension Double {
    func percentText(_ locale: Locale, signed: Bool = false) -> String {
        let text = formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
        return signed && self > 0 ? "+" + text : text
    }

    func compactText(_ locale: Locale) -> String {
        formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }
}
