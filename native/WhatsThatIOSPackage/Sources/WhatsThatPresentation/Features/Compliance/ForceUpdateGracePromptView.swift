import MarkdownUI
import SwiftUI
import WhatsThatShared

struct ForceUpdateGracePromptView: View {
    let targetVersion: String
    let currentVersion: String
    let daysRemaining: Int
    let message: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: BrandSpacing.large) {
                ScrollView {
                    VStack(spacing: BrandSpacing.large) {
                        Spacer()
                            .frame(height: BrandSpacing.large)

                        Text("⚠️")
                            .font(.system(size: 48))

                        Text("Update Required")
                            .font(.adaptiveSystem(size: 24, weight: .bold))
                            .foregroundStyle(titleColor)

                        VersionUpgradeBadge(currentVersion: currentVersion, targetVersion: targetVersion)

                        Text("You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to update.")
                            .font(.adaptiveSystem(size: 14))
                            .foregroundStyle(bodyColor.opacity(0.8))
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
                    .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: BrandSpacing.medium) {
                    BrandPrimaryButton(title: "Update Now") {
                        onUpdate()
                    }

                    Button("Remind Me Later") {
                        onDismiss()
                    }
                    .font(.adaptiveSystem(size: 16, weight: .medium))
                    .foregroundStyle(bodyColor.opacity(0.7))
                }
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large)
                .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
            }
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var complianceTheme: Theme {
        BrandMarkdownThemeFactory.complianceMessageTheme(for: BrandTheme.palette(for: colorScheme))
    }
}
