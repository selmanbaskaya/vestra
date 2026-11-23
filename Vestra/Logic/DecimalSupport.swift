import Foundation

enum DecimalCoding {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posix)
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: posix) ?? 0
    }

    static func parseStrict(_ string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: trimmed, locale: posix)
    }
}

/// Parses user-typed amounts. The decimal keypad follows the device region, so both "," and "."
/// are accepted: a single separator is treated as the decimal mark, repeated ones as grouping.
enum DecimalInput {
    static func parse(_ text: String) -> Decimal? {
        var digits = text.filter { !$0.isWhitespace && $0 != "₺" }
        guard !digits.isEmpty else { return nil }

        let separators: Set<Character> = [",", "."]
        let separatorIndices = digits.indices.filter { separators.contains(digits[$0]) }
        if let last = separatorIndices.last {
            let kinds = Set(separatorIndices.map { digits[$0] })
            if kinds.count == 1 && separatorIndices.count > 1 {
                digits.removeAll { separators.contains($0) }
            } else {
                var normalized = ""
                for index in digits.indices {
                    let character = digits[index]
                    if separators.contains(character) {
                        if index == last { normalized.append(".") }
                    } else {
                        normalized.append(character)
                    }
                }
                digits = normalized
            }
        }

        if digits.hasPrefix(".") { digits = "0" + digits }
        if digits.hasSuffix(".") { digits.removeLast() }
        guard digits.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func editingString(_ value: Decimal, locale: Locale) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...4)).locale(locale))
    }
}

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
