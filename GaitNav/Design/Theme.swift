import SwiftUI

// shared visual theme, dark mode, high contrast
enum Theme {
    
    static let backgroundPrimary = Color(hex: 0x121212)
    static let backgroundCard = Color(hex: 0x1E1E1E)
    static let backgroundElevated = Color(hex: 0x2A2A2A)
    
    static let danger = Color(hex: 0xFF4500)
    static let dangerSubtle = Color(hex: 0xFF4500).opacity(0.15)
    static let safe = Color(hex: 0x00FF00)
    static let safeSubtle = Color(hex: 0x00FF00).opacity(0.12)
    static let warning = Color(hex: 0xFFB800)
    static let accent = Color(hex: 0x4A9EFF)
    
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xB0B0B0)
    static let textDisabled = Color(hex: 0x666666)
    
    static let border = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.06)
    
    static func distanceColor(for distance: Float?) -> Color {
        guard let d = distance else { return safe }
        if d < 1.5 { return danger }
        if d < 3.5 { return warning }
        return safe
    }
    
    static func distanceColorSubtle(for distance: Float?) -> Color {
        guard let d = distance else { return safeSubtle }
        if d < 1.5 { return dangerSubtle }
        if d < 3.5 { return warning.opacity(0.12) }
        return safeSubtle
    }
    
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
