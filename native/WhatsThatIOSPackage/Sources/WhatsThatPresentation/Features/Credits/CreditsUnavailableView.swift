import SwiftUI
import WhatsThatShared

struct CreditsUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.secondary)

            Text("Credits unavailable")
                .font(.system(size: 20, weight: .semibold))

            Text("This build doesn’t include the credit store.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

