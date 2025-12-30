import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct EmailVerificationSentView: View {
    let email: String
    let onBackToLogin: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            VStack(spacing: BrandSpacing.small) {
                Text("Check Your Email")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(titleColor)
                Text("We've sent a verification link to \(email). Please check your inbox and follow the instructions to activate your account.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
            }

            Button("Back to Login") {
                onBackToLogin()
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryColor)
            .fontWeight(.semibold)
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
}
