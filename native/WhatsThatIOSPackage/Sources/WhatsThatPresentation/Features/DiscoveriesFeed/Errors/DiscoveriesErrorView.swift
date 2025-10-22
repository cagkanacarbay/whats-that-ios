import SwiftUI
import WhatsThatShared

struct DiscoveriesErrorView: View {
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.orange)

            Text("We couldn’t refresh your discoveries.")
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            BrandPrimaryButton(title: "Try again", action: action)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(BrandSpacing.large)
    }
}
