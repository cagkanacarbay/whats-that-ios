import Foundation
import SwiftUI
import UIKit
import WhatsThatDomain
import WhatsThatShared

@MainActor
final class DiscoveryDetailTransitionCoordinator: ObservableObject {
    enum DismissReason {
        case backButton
        case gesture
    }

    @Published private(set) var snapshot = DiscoveryDetailOverlaySnapshot()

    private let voiceoverController: VoiceoverPlaybackController
    private let heroAnimator: DiscoveryDetailHeroAnimator
    private var settleWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private let chromeRevealFraction: Double = 0.1

    private let detailDismissalThreshold: CGFloat = 150
    private let detailVerticalDismissalThreshold: CGFloat = 180
    private let detailHorizontalActivationTranslation: CGFloat = 14
    private let detailVerticalActivationTranslation: CGFloat = 22
    private let detailDismissDominantAxisSlack: CGFloat = 8
    private let verticalDismissActivationMaximumOffset: CGFloat = 12
    // Non-published copy of content distance used for gesture gating. This avoids
    // publishing during view updates while still allowing immediate gating.
    private var contentDistanceForGating: CGFloat = 0

    init(
        voiceoverController: VoiceoverPlaybackController,
        heroAnimator: DiscoveryDetailHeroAnimator = DiscoveryDetailHeroAnimator()
    ) {
        self.voiceoverController = voiceoverController
        self.heroAnimator = heroAnimator
    }

    private var lastPresentationTime: Date = .distantPast
    private let presentationThrottleInterval: TimeInterval = 0.25

    func present(
        discovery: DiscoverySummary,
        cardFrame: CGRect,
        imageURL: URL?,
        placeholderImage: UIImage? = nil,
        animated: Bool = true
    ) {
        guard canBeginPresentation(for: discovery.id) else { return }

        // If replacing an active presentation, force immediate cleanup to prevent animation conflicts
        if snapshot.phase.isActive && snapshot.context?.discovery.id != discovery.id {
            var resetSnapshot = DiscoveryDetailOverlaySnapshot()
            // Preserve voiceover state if needed, but reset layout/phase
            resetSnapshot.accessibility.isVoiceoverActive = snapshot.accessibility.isVoiceoverActive
            snapshot = resetSnapshot
        }
        
        lastPresentationTime = Date()

        let resolvedFrame = resolvedStartFrame(from: cardFrame)
        let sessionId = UUID()
        let cachedImage = placeholderImage ?? DiscoveryDetailImageCache.shared.image(for: discovery.id)

        cancelPendingWork()

        var newSnapshot = DiscoveryDetailOverlaySnapshot()
        newSnapshot.phase = .preparing
        newSnapshot.context = DiscoveryDetailContext(
            sessionId: sessionId,
            discovery: discovery,
            imageURL: imageURL,
            startFrame: resolvedFrame,
            placeholderImage: cachedImage,
            cardAspectRatio: resolvedFrame.height / max(resolvedFrame.width, 1)
        )
        newSnapshot.progress = 0
        newSnapshot.dismissProgress = 0
        newSnapshot.contentOpacity = 0
        newSnapshot.isContentReady = false
        newSnapshot.isClosing = false
        newSnapshot.isInteracting = false
        newSnapshot.contentScrollOffset = 0
        newSnapshot.activeDiscoveryId = discovery.id
        newSnapshot.accessibility.isVoiceoverActive = true

        snapshot = newSnapshot

        voiceoverController.isDetailOverlayActive = true

        // For direct replace/no-animation cases, force the overlay into the fully open state immediately.
        let openBlock = { [weak self] in
            guard let self else { return }
            self.snapshot.phase = .animatingIn
            self.snapshot.progress = 1
        }
        
        if animated {
            // Force a new transaction to ensure clean animation state
            var transaction = Transaction(animation: heroAnimator.openAnimation())
            transaction.disablesAnimations = true // Disable implicit animations
            
            withTransaction(transaction) {
                 withAnimation(self.heroAnimator.openAnimation()) {
                     openBlock()
                 }
            }
        } else {
            // Disabling animation explicitly
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                openBlock()
            }
        }

        scheduleDetailSettled(for: sessionId)
    }

    func updateDrag(_ value: DragGesture.Value) {
        guard snapshot.context != nil, !snapshot.isClosing else { return }

        let interactor = makeDismissInteractor()

        if !snapshot.isInteracting {
            guard let direction = interactor.interactionDirection(
                startLocation: value.startLocation,
                translation: value.translation
            ) else { return }
            snapshot.isInteracting = true
            snapshot.phase = .interactiveDismiss
            snapshot.activeDismissDirection = direction
        }

        guard snapshot.isInteracting, let direction = snapshot.activeDismissDirection else { return }

        let metrics = interactor.metrics(for: value.translation, direction: direction)
        snapshot.gestureTranslation = metrics.translation
        snapshot.gestureScale = metrics.scale
        snapshot.gestureRotation = metrics.rotation
        snapshot.gestureCornerRadius = metrics.cornerRadius
        snapshot.gestureShadowOpacity = metrics.shadowOpacity

        snapshot.dismissProgress = metrics.progress
    }

    func endDrag(_ value: DragGesture.Value) {
        guard snapshot.isInteracting else { return }
        guard let direction = snapshot.activeDismissDirection else {
            snapshot.isInteracting = false
            resetGestureState(animated: true)
            if let sessionId = snapshot.context?.sessionId {
                scheduleDetailSettled(for: sessionId)
            }
            return
        }
        snapshot.isInteracting = false

        let interactor = makeDismissInteractor()
        let shouldDismiss = interactor.shouldDismiss(
            translation: value.translation,
            predictedTranslation: value.predictedEndTranslation,
            direction: direction
        )


        if shouldDismiss {
            snapshot.closeStartTranslation = snapshot.gestureTranslation
            snapshot.closeStartScale = snapshot.gestureScale
            snapshot.closeStartRotation = snapshot.gestureRotation
            snapshot.dismissProgress = 1
            resetGestureState(animated: true, resetDismissProgress: false)
            dismiss(reason: .gesture)
        } else {
            resetGestureState(animated: true)
            if let sessionId = snapshot.context?.sessionId {
                scheduleDetailSettled(for: sessionId)
            }
        }
    }

    func updateContentScrollOffset(_ offset: CGFloat) {
        guard snapshot.hasActiveOverlay else { return }
        // Update non-published gating value synchronously for immediate use.
        self.contentDistanceForGating = offset
        // Mirror into snapshot asynchronously to avoid publishing during view updates.
        DispatchQueue.main.async { [weak self] in
            self?.snapshot.contentScrollOffset = offset
        }
    }

    func dismiss(reason: DismissReason = .backButton, animated: Bool = true) {
        guard let context = snapshot.context else { return }
        guard !snapshot.isClosing else { return }

        snapshot.isInteracting = false
        snapshot.activeDismissDirection = nil
        if reason == .backButton {
            snapshot.closeStartTranslation = .zero
            snapshot.closeStartScale = 1
            snapshot.closeStartRotation = 0
        }

        snapshot.dismissProgress = 1
        resetGestureState(animated: animated, resetDismissProgress: false)
        snapshot.isClosing = true
        snapshot.phase = .closing

        settleWorkItem?.cancel()
        settleWorkItem = nil

        let sessionId = context.sessionId

        if animated {
            // Unified one-pass close: fade chrome and collapse in a single animation.
            // Important: schedule the progress animation to the next runloop tick so that
            // the initial frame of the uniform transform starts at transformProgress = 0.
            // This avoids a visible jump to the target (small) scale at gesture release.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.snapshot.context?.sessionId == sessionId else { return }
                withAnimation(self.heroAnimator.closeAnimation()) {
                    self.snapshot.progress = 0
                }
            }
            scheduleCloseCleanup(for: sessionId)
        } else {
            // Instant close - no animation, clear immediately
            snapshot.progress = 0
            snapshot = DiscoveryDetailOverlaySnapshot()
            voiceoverController.isDetailOverlayActive = false
        }
    }

    func resetIfNeeded() {
        guard snapshot.phase == .idle else { return }
        cancelPendingWork()
    }

    private func canBeginPresentation(for discoveryId: Int64) -> Bool {
        // Throttle rapid presentations
        guard Date().timeIntervalSince(lastPresentationTime) > presentationThrottleInterval else {
            // Log this? It might be noisy, but confirms the throttle is working
            return false
        }

        // If nothing is active, always allow.
        if !snapshot.phase.isActive {
            return true
        }
        guard let existingContext = snapshot.context else {
            return true
        }
        if existingContext.discovery.id != discoveryId {
            return true
        }
        return snapshot.isClosing
    }

    private func resolvedStartFrame(from frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else {
            let fallbackWidth: CGFloat = 200
            let fallbackHeight: CGFloat = fallbackWidth * 1.2
            let bounds = UIScreen.main.bounds
            return CGRect(
                x: bounds.midX - (fallbackWidth / 2),
                y: bounds.midY - (fallbackHeight / 2),
                width: fallbackWidth,
                height: fallbackHeight
            )
        }
        return frame
    }

    private func updateContentVisibility(animated: Bool = true) {
        let shouldShow = !snapshot.isClosing && snapshot.isContentReady
        let targetOpacity: Double = shouldShow ? 1 : 0
        guard snapshot.contentOpacity != targetOpacity else { return }

        let update = {
            self.snapshot.contentOpacity = targetOpacity
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                update()
            }
        } else {
            update()
        }
    }

    private func scheduleDetailSettled(for sessionId: UUID) {
        settleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.snapshot.context?.sessionId == sessionId,
                  !self.snapshot.isClosing,
                  !self.snapshot.isInteracting
            else { return }

            if !self.snapshot.isContentReady {
                self.snapshot.isContentReady = true
                self.snapshot.phase = .presented
                self.updateContentVisibility()
            }
        }
        settleWorkItem = workItem
        let revealDelay = heroAnimator.openDuration * chromeRevealFraction
        DispatchQueue.main.asyncAfter(
            deadline: .now() + revealDelay,
            execute: workItem
        )
    }

    private func scheduleCloseCleanup(for sessionId: UUID, additionalDelay: TimeInterval = 0) {
        closeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.snapshot.context?.sessionId == sessionId {
                self.snapshot = DiscoveryDetailOverlaySnapshot()
            } else if self.snapshot.context == nil {
                self.snapshot = DiscoveryDetailOverlaySnapshot()
            }
            self.voiceoverController.isDetailOverlayActive = false
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + additionalDelay + heroAnimator.closeDuration,
            execute: workItem
        )
    }

    private func resetGestureState(animated: Bool, resetDismissProgress: Bool = true) {
        let animations = { [self] in
            snapshot.gestureTranslation = .zero
            snapshot.gestureScale = 1
            snapshot.gestureRotation = 0
            snapshot.gestureShadowOpacity = 0
            snapshot.gestureCornerRadius = 0
            snapshot.activeDismissDirection = nil
            if resetDismissProgress {
                snapshot.dismissProgress = 0
            }
        }

        if animated {
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                animations()
            }
        } else {
            animations()
        }
    }

    private func makeDismissInteractor() -> DiscoveryDetailDismissInteractor {
        let offset = self.contentDistanceForGating
        let allowVertical = offset <= self.verticalDismissActivationMaximumOffset
        return DiscoveryDetailDismissInteractor(
            horizontalDismissalDistance: computeHorizontalDismissalDistance(),
            verticalDismissalDistance: computeVerticalDismissalDistance(),
            horizontalDismissalThreshold: detailDismissalThreshold,
            verticalDismissalThreshold: detailVerticalDismissalThreshold,
            horizontalActivationTranslation: detailHorizontalActivationTranslation,
            verticalActivationTranslation: detailVerticalActivationTranslation,
            dominantAxisSlack: detailDismissDominantAxisSlack,
            allowVerticalDismiss: allowVertical
        )
    }

    private func computeHorizontalDismissalDistance() -> CGFloat {
        if let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        {
            return max(window.bounds.width, 1)
        }
        return max(UIScreen.main.bounds.width, 1)
    }

    private func computeVerticalDismissalDistance() -> CGFloat {
        if let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        {
            return max(window.bounds.height, 1)
        }
        return max(UIScreen.main.bounds.height, 1)
    }

    private func cancelPendingWork() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

}
