import MarkdownUI
import SwiftUI
import WhatsThatShared

struct ForceUpdateBlockingView: View {
    let targetVersion: String
    let currentVersion: String
    let message: String?
    let isGraceExpired: Bool
    let onOpenAppStore: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            ScrollView {
                VStack(spacing: BrandSpacing.large) {
                    Spacer().frame(height: BrandSpacing.large)

                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(primaryColor)

                    Text("New Version Available")
                        .font(.adaptiveSystem(size: 24, weight: .bold))
                        .foregroundStyle(titleColor)

                    VersionUpgradeBadge(currentVersion: currentVersion, targetVersion: targetVersion)

                    Text("We've made some important improvements and need you to update to continue.")
                        .font(.adaptiveSystem(size: 16))
                        .foregroundStyle(bodyColor)
                        .multilineTextAlignment(.center)

                    if let message, !message.isEmpty {
                        Markdown("## Update Notes\n\n\(message)")
                            .markdownTheme(complianceTheme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(BrandSpacing.medium)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, BrandSpacing.large)
                .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            BrandPrimaryButton(title: "Update Now") {
                onOpenAppStore()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.large)
            .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var complianceTheme: Theme {
        BrandMarkdownThemeFactory.complianceMessageTheme(for: BrandTheme.palette(for: colorScheme))
    }
}
