import SwiftUI

/// Koe design system colors - Japanese-inspired palette
public enum KoeColors {
    // Primary accent - Japanese indigo (藍色 ai-iro)
    public static let accent = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    // Background - warm off-white (washi paper inspired)
    public static let background = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))

    // Text colors
    public static let textPrimary = Color(nsColor: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0))
    public static let textSecondary = Color(nsColor: NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 1.0))
    public static let textTertiary = Color(nsColor: NSColor(red: 0.50, green: 0.48, blue: 0.46, alpha: 1.0))
    public static let textLight = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    public static let textLighter = Color(nsColor: NSColor(red: 0.70, green: 0.68, blue: 0.66, alpha: 1.0))

    // Surface colors
    public static let surface = Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0))

    // State colors
    public static let recording = Color.red.opacity(0.9)
    public static let processing = accent
    public static let idle = Color.white
}
