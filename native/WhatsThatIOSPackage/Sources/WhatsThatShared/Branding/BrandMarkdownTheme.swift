#if canImport(MarkdownUI)
import MarkdownUI
import SwiftUI
import UIKit

public enum BrandMarkdownThemeFactory {
    /// Scale factor for iPad fonts (1.4x the iPhone size)
    private static var scaleFactor: CGFloat { UIDevice.isIPad ? 1.4 : 1.0 }

    /// Computes adaptive font size: original on iPhone, scaled on iPad
    private static func adaptiveSize(_ baseSize: CGFloat) -> CGFloat {
        baseSize * scaleFactor
    }

    /// Computes font size that responds to Dynamic Type accessibility settings
    /// Scales for both iPad (1.4x) and user's preferred text size
    private static func dynamicTypeSize(_ baseSize: CGFloat) -> CGFloat {
        let iPadScaled = baseSize * scaleFactor
        return UIFontMetrics.default.scaledValue(for: iPadScaled)
    }
    
    public static func discoveryDetailTheme(for palette: BrandTheme.Palette) -> Theme {
        Theme()
            .text {
                FontSize(adaptiveSize(16))
                ForegroundColor(palette.textSecondary)
            }
            .strong {
                FontWeight(.semibold)
            }
            .link {
                ForegroundColor(palette.primaryAction)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(adaptiveSize(24))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.4), bottom: .em(0.6))
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(adaptiveSize(20))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.2), bottom: .em(0.5))
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(adaptiveSize(18))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.1), bottom: .em(0.45))
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(adaptiveSize(17))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1), bottom: .em(0.4))
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(adaptiveSize(16))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(0.9), bottom: .em(0.35))
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(adaptiveSize(15))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(0.8), bottom: .em(0.3))
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .zero, bottom: .em(1))
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: .zero, bottom: .em(1))
            }
            .listItem { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.28))
                    .markdownMargin(top: .em(0.25))
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontStyle(.italic)
                        ForegroundColor(palette.textSecondary.opacity(0.9))
                    }
                    .relativePadding(.leading, length: .em(0.9))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(palette.primaryAction.opacity(0.35))
                            .frame(width: 3)
                            .padding(.vertical, 4)
                    }
                    .markdownMargin(top: .zero, bottom: .em(1))
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(adaptiveSize(14))
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: true)
                        .relativeLineSpacing(.em(0.2))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(adaptiveSize(14))
                            ForegroundColor(palette.textSecondary)
                        }
                        .padding(.horizontal, BrandSpacing.medium)
                        .padding(.vertical, BrandSpacing.small)
                        .background(
                            palette.surface.opacity(0.85)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: BrandCornerRadius.medium,
                                        style: .continuous
                                    )
                                )
                        )
                }
                .markdownMargin(top: .zero, bottom: .em(1))
            }
            .image { configuration in
                configuration.label
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .markdownMargin(top: .em(1), bottom: .em(1))
            }
    }

    /// Simplified theme for compliance/update message views
    /// Optimized for bullet points, numbered lists, and body text at 14pt
    /// Supports Dynamic Type for accessibility
    public static func complianceMessageTheme(for palette: BrandTheme.Palette) -> Theme {
        Theme()
            .text {
                FontSize(dynamicTypeSize(14))
                ForegroundColor(palette.textSecondary)
            }
            .strong {
                FontWeight(.semibold)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(dynamicTypeSize(17))
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .zero, bottom: .em(0.6))
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: .zero, bottom: .em(0.6))
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.3), bottom: .em(0.3))
            }
            .listItem { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: .em(0.15))
            }
    }
}
#endif
