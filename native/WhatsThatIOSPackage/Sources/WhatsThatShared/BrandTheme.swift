import SwiftUI

public enum BrandColors {
    public static let logo = Color(hex: "#FFAA00")

    public enum Light {
        public static let background = Color(.white)
        public static let border = Color(hex: "#E8E8E8")
        public static let secondaryAction = Color(hex: "#DBDBDB")
        public static let secondaryActionPressed = Color(hex: "#C7C7C7")
        public static let primaryAction = Color(hex: "#5BB98C")
        public static let primaryActionPressed = Color(hex: "#30A46C")
        public static let accentText = Color(hex: "#1F2933")
        public static let bodyText = Color(hex: "#4B5563")
    }

    public enum Dark {
        public static let background = Color(hex: "#080A15")
        public static let border = Color(hex: "#2E2E2E")
        public static let secondaryAction = Color(hex: "#343434")
        public static let secondaryActionPressed = Color(hex: "#3E3E3E")
        public static let primaryAction = Color(hex: "#236E4A")
        public static let primaryActionPressed = Color(hex: "#1B543A")
        public static let accentText = Color(.white)
        public static let bodyText = Color(.white).opacity(0.82)
    }
}

public enum BrandSpacing {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
}

public enum BrandCornerRadius {
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
}

public extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleanedHex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = (
                ((int >> 8) & 0xF) * 17,
                ((int >> 4) & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6: // RGB (24-bit)
            (r, g, b) = (
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF
            )
        default:
            (r, g, b) = (1, 1, 1)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
