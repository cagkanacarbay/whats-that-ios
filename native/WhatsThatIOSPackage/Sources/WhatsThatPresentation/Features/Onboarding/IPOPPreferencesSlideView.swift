import SwiftUI
import WhatsThatShared

/// IPOP preferences slide for post-purchase configuration.
struct IPOPPreferencesSlideView: View {
    @ObservedObject var viewModel: IPoPPreferencesViewModel

    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: BrandTheme.Palette {
        BrandTheme.palette(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Spacer()

                // Title
                Text("What makes a story great for you?")
                .font(.adaptiveSystem(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.small)

            // Subtitle
            Text("Some people love the history. Others want the human drama.\nTell us what pulls you in, we'll do the rest.")
                .font(.adaptiveSystem(size: 17, weight: .regular))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, BrandSpacing.large)
                .padding(.bottom, BrandSpacing.large)

            // IPOP preferences editor
            IPoPPreferencesListView(viewModel: viewModel)

            Spacer()

            // Button
            BrandPrimaryButton(title: "Continue") {
                onContinue()
            }
            .padding(.horizontal, BrandSpacing.large)
            .padding(.bottom, BrandSpacing.xLarge)
            }
            .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
            .frame(maxWidth: .infinity)
            .background(palette.background)

            // Back button
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.top, BrandSpacing.medium)
            .padding(.leading, BrandSpacing.medium)
        }
        .background(palette.background)
    }
}

#Preview {
    IPOPPreferencesSlideView(
        viewModel: IPoPPreferencesViewModel(
            loadPreferences: { nil },
            savePreferences: { _ in }
        ),
        onContinue: {},
        onBack: {}
    )
}
