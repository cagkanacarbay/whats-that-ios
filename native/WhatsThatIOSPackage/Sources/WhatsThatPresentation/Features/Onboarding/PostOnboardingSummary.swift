import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct PostOnboardingSummary: View {
    let user: AuthenticatedUser
    let onContinue: () -> Void
    let onSignOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var permissionsCoordinator = OnboardingPermissionsCoordinator()

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                Text("Welcome aboard, \(user.email)!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(titleColor)
                VStack(alignment: .leading, spacing: BrandSpacing.small) {
                    Label("You’ve got 3 free credits ready to explore.", systemImage: "sparkles")
                    Label("Point your camera or upload a photo to get instant stories.", systemImage: "camera.viewfinder")
                    Label("Enable location later for richer, nearby context.", systemImage: "location")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(bodyColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingPermissionsSection(permissions: permissionsCoordinator)

            BrandPrimaryButton(title: "Start Exploring", action: onContinue)

            Button("Sign out") {
                onSignOut()
            }
            .buttonStyle(.plain)
            .foregroundStyle(bodyColor)
            .font(.system(size: 14, weight: .semibold))

            Spacer()
        }
        .frame(maxWidth: 520)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}

