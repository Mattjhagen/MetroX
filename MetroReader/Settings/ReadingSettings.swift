import SwiftUI

enum ReadingTheme: String, CaseIterable {
    case system = "System"
    case dark   = "Dark"
    case sepia  = "Sepia"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .sepia:  return nil  // light + custom background
        }
    }

    var background: Color {
        switch self {
        case .system: return Color(.systemBackground)
        case .dark:   return Color(red: 0.10, green: 0.10, blue: 0.10)
        case .sepia:  return Color(red: 0.97, green: 0.93, blue: 0.82)
        }
    }

    var foreground: Color {
        switch self {
        case .system: return Color(.label)
        case .dark:   return Color(red: 0.90, green: 0.88, blue: 0.84)
        case .sepia:  return Color(red: 0.25, green: 0.18, blue: 0.10)
        }
    }
}

enum FontSize: String, CaseIterable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var cssValue: String {
        switch self {
        case .small:  return "16px"
        case .medium: return "19px"
        case .large:  return "22px"
        }
    }
}

enum Margin: String, CaseIterable {
    case compact = "Compact"
    case normal  = "Normal"
    case wide    = "Wide"

    var cssValue: String {
        switch self {
        case .compact: return "5%"
        case .normal:  return "10%"
        case .wide:    return "18%"
        }
    }
}

class ReadingSettings: ObservableObject {
    @AppStorage("readingTheme") var themeRaw: String = ReadingTheme.system.rawValue
    @AppStorage("fontSize")     var fontSizeRaw: String = FontSize.medium.rawValue
    @AppStorage("margin")       var marginRaw: String = Margin.normal.rawValue

    var theme: ReadingTheme {
        get { ReadingTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }
    var fontSize: FontSize {
        get { FontSize(rawValue: fontSizeRaw) ?? .medium }
        set { fontSizeRaw = newValue.rawValue }
    }
    var margin: Margin {
        get { Margin(rawValue: marginRaw) ?? .normal }
        set { marginRaw = newValue.rawValue }
    }
}
