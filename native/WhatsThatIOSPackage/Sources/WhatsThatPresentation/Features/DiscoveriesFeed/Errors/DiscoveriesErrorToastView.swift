import SwiftUI
import WhatsThatShared

struct DiscoveriesErrorToastView: View {
    let message: String
    let retryAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }

            HStack(spacing: BrandSpacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(toastTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Retry") {
                    retryAction()
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.85))
                .clipShape(Capsule())
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity(colorScheme == .dark ? 0.65 : 0.55),
                Color.black.opacity(colorScheme == .dark ? 0.45 : 0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var toastTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.85) : Color.white.opacity(0.92)
    }
}
