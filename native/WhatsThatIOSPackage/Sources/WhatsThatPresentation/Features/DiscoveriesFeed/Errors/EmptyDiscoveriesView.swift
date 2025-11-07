import SwiftUI
import WhatsThatShared

struct EmptyDiscoveriesView: View {
    // Actions to trigger quick-start flows
    var onCamera: (() -> Void)? = nil
    var onUpload: (() -> Void)? = nil
    // Optional minimum height to allow vertical centering inside scroll content
    var minHeight: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack { // Center vertically using spacers
            Spacer(minLength: 0)

            VStack(spacing: BrandSpacing.medium) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)

                // Title + subtitle with reduced internal gap
                VStack(spacing: BrandSpacing.small) {
                    Text("Start making discoveries")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(titleColor)

                    Text("Take a photo or choose from your gallery to discover more about the world around you.")
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(bodyColor)
                        .frame(maxWidth: 320)
                }

                // Quick actions
                HStack(spacing: BrandSpacing.medium) {
                    BrandPrimaryButton(title: "Camera") {
                        onCamera?()
                    }
                    .accessibilityLabel("Open camera to create a discovery")

                BrandSecondaryButton(title: "Gallery") {
                    onUpload?()
                }
                .accessibilityLabel("Choose a photo from your gallery to analyze")
            }
                .frame(maxWidth: 420)
                .padding(.top, BrandSpacing.small)
            }
            // Nudge content slightly upward so it sits a bit above true center
            .offset(y: -BrandSpacing.large)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight ?? 320)
        .padding(.horizontal, BrandSpacing.large)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : BrandColors.Light.bodyText
    }
}
