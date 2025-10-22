import SwiftUI
import WhatsThatShared

struct DiscoveryCreationPalette {
    private let palette: BrandTheme.Palette

    private init(palette: BrandTheme.Palette) {
        self.palette = palette
    }

    static func resolve(for colorScheme: ColorScheme) -> DiscoveryCreationPalette {
        DiscoveryCreationPalette(palette: BrandTheme.palette(for: colorScheme))
    }

    var background: Color { palette.background }
    var surface: Color { palette.surface }
    var textPrimary: Color { palette.textPrimary }
    var textSecondary: Color { palette.textSecondary }
    var border: Color { palette.border }
    var primaryAction: Color { palette.primaryAction }
    var primaryActionPressed: Color { palette.primaryActionPressed }
    var secondaryAction: Color { palette.secondaryAction }
    var secondaryActionPressed: Color { palette.secondaryActionPressed }
    var overlayMidtone: Color { palette.overlayMidtone }
    var overlayButtonBackground: Color { palette.overlayButtonBackground }
    var overlayButtonForeground: Color { palette.overlayButtonForeground }
    var overlayButtonBorder: Color { palette.overlayButtonBorder }
    var overlayButtonShadowOpacity: Double { palette.overlayButtonShadowOpacity }

    var brandPalette: BrandTheme.Palette { palette }
}
