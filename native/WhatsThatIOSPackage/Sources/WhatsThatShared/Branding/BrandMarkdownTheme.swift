#if canImport(MarkdownUI)
import MarkdownUI
import SwiftUI

public enum BrandMarkdownThemeFactory {
    public static func discoveryDetailTheme(for palette: BrandTheme.Palette) -> Theme {
        Theme()
            .text {
                FontSize(16)
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
                        FontSize(24)
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.4), bottom: .em(0.6))
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(20)
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.2), bottom: .em(0.5))
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(18)
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1.1), bottom: .em(0.45))
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(17)
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(1), bottom: .em(0.4))
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(16)
                        ForegroundColor(palette.textPrimary)
                    }
                    .markdownMargin(top: .em(0.9), bottom: .em(0.35))
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(15)
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
                FontSize(14)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: true)
                        .relativeLineSpacing(.em(0.2))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(14)
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
}
#endif
