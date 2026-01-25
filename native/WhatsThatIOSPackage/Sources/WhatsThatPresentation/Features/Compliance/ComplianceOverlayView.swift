import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct ComplianceOverlayView: View {
    let blockingState: ComplianceBlockingState
    let onAcceptTerms: (String?, String?) async -> Result<Void, Error>
    let onSignOut: () async -> Void
    let onOpenAppStore: (String) -> Void
    let onCheckAgain: () async -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            switch blockingState {
            case .maintenance(let message):
                MaintenanceBlockingView(
                    message: message,
                    onCheckAgain: onCheckAgain
                )
            case .forceUpdateImmediate(let targetVersion, let appStoreUrl):
                ForceUpdateBlockingView(
                    targetVersion: targetVersion,
                    message: nil,
                    isGraceExpired: false,
                    onOpenAppStore: { onOpenAppStore(appStoreUrl) },
                    onCheckAgain: onCheckAgain
                )
            case .forceUpdateExpired(let targetVersion, let appStoreUrl, let message):
                ForceUpdateBlockingView(
                    targetVersion: targetVersion,
                    message: message,
                    isGraceExpired: true,
                    onOpenAppStore: { onOpenAppStore(appStoreUrl) },
                    onCheckAgain: onCheckAgain
                )
            case .legalAcceptance(let needsTos, let needsPrivacy, let tosVersion, let privacyVersion, let tosMessage, let privacyMessage):
                LegalAcceptanceModalView(
                    needsTos: needsTos,
                    needsPrivacy: needsPrivacy,
                    tosVersion: tosVersion,
                    privacyVersion: privacyVersion,
                    tosMessage: tosMessage,
                    privacyMessage: privacyMessage,
                    onAccept: onAcceptTerms,
                    onSignOut: onSignOut
                )
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}
