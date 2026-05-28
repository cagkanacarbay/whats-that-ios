import SwiftUI
import WhatsThatShared

/// Wrapper that owns the `@ObservedObject` observation of `DiscoverySessionManager`.
///
/// By isolating the session manager observation here, changes to `sessionStatuses`,
/// `inProgressItems`, or `pendingCompletionToasts` only re-render this subtree —
/// not the parent `DiscoveriesHomeView` and its detail overlay hero animation.
///
/// Uses `.drawingGroup()` to rasterize the spinner animations into a Metal texture,
/// preventing them from interfering with the detail overlay's hero animation compositing.
struct InProgressSectionContainer: View {
    @ObservedObject private var sessionManager = DiscoverySessionManager.shared

    let gridHorizontalPadding: CGFloat
    let onTap: (InProgressItem) -> Void
    let onDismissFailure: (InProgressItem) -> Void

    var body: some View {
        if !sessionManager.inProgressItems.isEmpty {
            InProgressSection(
                items: sessionManager.inProgressItems,
                onTap: { item in onTap(item) },
                onDismissFailure: { item in onDismissFailure(item) }
            )
            .padding(.horizontal, gridHorizontalPadding + 8)
            .drawingGroup()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
