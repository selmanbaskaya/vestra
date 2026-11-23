import SwiftUI
import UIKit

/// Vestra's palette. Each colour has a hand-picked light and dark variant.
enum Theme {
    static let background = Color(light: 0xF5F4F0, dark: 0x0B0C0F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x17191E)
    static let surfaceMuted = Color(light: 0xEFEEE9, dark: 0x23262C)
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)

    static let accent = Color(light: 0x8A6A3B, dark: 0xD6B77D)
    static let gold = Color(light: 0xA27C3E, dark: 0xE2C486)
    static let income = Color(light: 0x1C8A55, dark: 0x3FD18A)
    static let expense = Color(light: 0xC53D33, dark: 0xFF6E64)

    /// The total balance card stays dark in both appearances; its content colours are fixed.
    static let hero = Color(light: 0x16181E, dark: 0x1D2027)
    static let heroSecondaryText = Color.white.opacity(0.62)
    static let heroCash = Color(hex: 0x9DB3C6)
    static let heroGold = Color(hex: 0xD6B77D)

    static let brandInk = Color(hex: 0x12141A)
    static let brandLight = Color(hex: 0xE4C890)
    static let brandDeep = Color(hex: 0xA6834A)

    static func signColor(_ value: Decimal) -> Color {
        value > 0 ? income : (value < 0 ? expense : .primary)
    }
}

extension Color {
    init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }

    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
