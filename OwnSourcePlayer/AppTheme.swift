import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case ocean
    case graphite
    case sunset
    case forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Default"
        case .ocean:
            return "Ocean"
        case .graphite:
            return "Graphite"
        case .sunset:
            return "Sunset"
        case .forest:
            return "Forest"
        }
    }

    var accent: Color {
        switch self {
        case .system:
            return Color.accentColor
        case .ocean:
            return Color(red: 0.0, green: 0.50, blue: 0.62)
        case .graphite:
            return Color(red: 0.36, green: 0.39, blue: 0.43)
        case .sunset:
            return Color(red: 0.88, green: 0.35, blue: 0.18)
        case .forest:
            return Color(red: 0.12, green: 0.48, blue: 0.30)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .system, .ocean:
            return [Color(red: 0.0, green: 0.50, blue: 0.62), Color(red: 0.0, green: 0.75, blue: 0.84)]
        case .graphite:
            return [Color(red: 0.18, green: 0.20, blue: 0.23), Color(red: 0.48, green: 0.52, blue: 0.56)]
        case .sunset:
            return [Color(red: 0.78, green: 0.24, blue: 0.16), Color(red: 0.98, green: 0.62, blue: 0.24)]
        case .forest:
            return [Color(red: 0.06, green: 0.32, blue: 0.22), Color(red: 0.36, green: 0.68, blue: 0.28)]
        }
    }

    var heroGradientColors: [Color] {
        switch self {
        case .system, .ocean:
            return [Color(red: 0.02, green: 0.12, blue: 0.16), Color(red: 0.0, green: 0.50, blue: 0.58)]
        case .graphite:
            return [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.32, green: 0.35, blue: 0.38)]
        case .sunset:
            return [Color(red: 0.20, green: 0.08, blue: 0.08), Color(red: 0.80, green: 0.28, blue: 0.16)]
        case .forest:
            return [Color(red: 0.03, green: 0.14, blue: 0.10), Color(red: 0.16, green: 0.48, blue: 0.28)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var heroGradient: LinearGradient {
        LinearGradient(colors: heroGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
