import SwiftUI
import WhatsThatShared
#if canImport(MarkdownUI)
import MarkdownUI
#endif

struct DiscoveryStreamingMarkdownView: View {
    let palette: DiscoveryCreationPalette
    let displayedMarkdown: String
    let shouldShowLoader: Bool
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            if shouldShowLoader {
                if !isStreaming {
                    Text("Analysis complete.")
                        .font(.adaptiveSystem(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            } else if !displayedMarkdown.isEmpty {
                #if canImport(MarkdownUI)
                Markdown(displayedMarkdown)
                    .markdownTheme(BrandMarkdownThemeFactory.discoveryDetailTheme(for: palette.brandPalette))
                #else
                Text(displayedMarkdown)
                    .font(.adaptiveSystem(size: 16))
                    .foregroundStyle(palette.textSecondary)
                #endif
            }
        }
        .padding(.top, BrandSpacing.large)
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, BrandSpacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
