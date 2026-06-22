import SwiftUI

enum Metro {
    // MARK: - Colors
    static let background         = Color(metroHex: "#121414")
    static let surfaceContLow     = Color(metroHex: "#1a1c1c")
    static let surfaceCont        = Color(metroHex: "#1e2020")
    static let surfaceContHigh    = Color(metroHex: "#282a2b")
    static let surfaceContHighest = Color(metroHex: "#333535")
    static let primary            = Color(metroHex: "#a4c9ff")
    static let onPrimary          = Color(metroHex: "#00315d")
    static let primaryContainer   = Color(metroHex: "#0078d7")
    static let secondary          = Color(metroHex: "#4bd9e5")
    static let onSecondary        = Color(metroHex: "#004347")
    static let tertiary           = Color(metroHex: "#fcaaff")
    static let onTertiary         = Color(metroHex: "#36003e")
    static let onSurface          = Color(metroHex: "#e2e2e2")
    static let onSurfaceVariant   = Color(metroHex: "#c0c7d4")
    static let outlineVariant     = Color(metroHex: "#414752")

    // MARK: - Typography
    // Replace .system calls with .custom("HankenGrotesk-Bold", size:) once font is bundled.
    static func displayHero(size: CGFloat = 72) -> Font {
        .system(size: size, weight: .heavy)
    }
    static func headlineLg(size: CGFloat = 32) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func tileTitle(size: CGFloat = 20) -> Font {
        .system(size: size, weight: .medium)
    }
    // JetBrains Mono stand-in — system monospaced for stats and labels.
    static func labelSm(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    static func bodyMd(size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular)
    }

    // MARK: - Spacing
    static let margin: CGFloat = 24
    static let gap: CGFloat    = 12
}

extension Color {
    init(metroHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red:   Double((int & 0xFF0000) >> 16) / 255,
            green: Double((int & 0x00FF00) >>  8) / 255,
            blue:  Double( int & 0x0000FF       ) / 255
        )
    }
}
