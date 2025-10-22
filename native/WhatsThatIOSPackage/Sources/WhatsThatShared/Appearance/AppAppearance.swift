import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public static let storageKey = "app.appearance.mode"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            return "Match System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    public var description: String {
        switch self {
        case .system:
            return "Use your device appearance setting automatically."
        case .light:
            return "Always use a light appearance."
        case .dark:
            return "Always use a dark appearance."
        }
    }

    public var symbolName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.stars.fill"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    public var brandMode: BrandTheme.Mode {
        switch self {
        case .system:
            return .system
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
