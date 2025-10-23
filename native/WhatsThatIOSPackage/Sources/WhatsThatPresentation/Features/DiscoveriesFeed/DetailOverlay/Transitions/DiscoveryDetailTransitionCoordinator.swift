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

    private let detailEdgeActivationWidth: CGFloat = 30
    private let detailDismissalThreshold: CGFloat = 150

    init(
        voiceoverController: VoiceoverPlaybackController,
        heroAnimator: DiscoveryDetailHeroAnimator = DiscoveryDetailHeroAnimator()
    ) {
        self.voiceoverController = voiceoverController
        self.heroAnimator = heroAnimator
    }

    func present(
        discovery: DiscoverySummary,
        cardFrame: CGRect,
        imageURL: URL?,
        placeholderImage: UIImage? = nil
    ) {
        guard canBeginPresentation(for: discovery.id) else { return }

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
        newSnapshot.activeDiscoveryId = discovery.id
        newSnapshot.accessibility.isVoiceoverActive = true

        snapshot = newSnapshot

        voiceoverController.ensureMetadata(for: discovery)
        voiceoverController.isDetailOverlayActive = true

        withAnimation(heroAnimator.openAnimation()) {
            snapshot.phase = .animatingIn
            snapshot.progress = 1
        }

        scheduleDetailSettled(for: sessionId)
    }

    func updateDrag(_ value: DragGesture.Value) {
        guard snapshot.context != nil, !snapshot.isClosing else { return }

        if !snapshot.isInteracting {
            let interactor = makeDismissInteractor()
            guard interactor.canBeginInteraction(
                startLocation: value.startLocation,
                translation: value.translation
            ) else {
                return
            }
            snapshot.isInteracting = true
            snapshot.phase = .interactiveDismiss
        }

        guard snapshot.isInteracting else { return }

        let interactor = makeDismissInteractor()
        let metrics = interactor.metrics(for: value.translation)
        snapshot.gestureTranslation = metrics.translation
        snapshot.gestureScale = metrics.scale
        snapshot.gestureRotation = metrics.rotation
        snapshot.gestureCornerRadius = metrics.cornerRadius
        snapshot.gestureShadowOpacity = metrics.shadowOpacity

        let dismissalProgress = min(
            max(metrics.translation.width / max(interactor.dismissalDistance, 1), 0),
            1
        )
        snapshot.dismissProgress = dismissalProgress
    }

    func endDrag(_ value: DragGesture.Value) {
        guard snapshot.isInteracting else { return }
        snapshot.isInteracting = false

        let interactor = makeDismissInteractor()
        let shouldDismiss = interactor.shouldDismiss(
            translation: value.translation,
            predictedTranslation: value.predictedEndTranslation
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

    func dismiss(reason: DismissReason = .backButton) {
        guard let context = snapshot.context else { return }
        guard !snapshot.isClosing else { return }

        snapshot.isInteracting = false
        if reason == .backButton {
            snapshot.closeStartTranslation = .zero
            snapshot.closeStartScale = 1
            snapshot.closeStartRotation = 0
        }

        snapshot.dismissProgress = 1
        resetGestureState(animated: true, resetDismissProgress: false)
        snapshot.isClosing = true
        snapshot.phase = .closing
        snapshot.isContentReady = false
        updateContentVisibility(animated: false)

        withAnimation(heroAnimator.closeAnimation()) {
            snapshot.progress = 0
        }

        scheduleCloseCleanup(for: context.sessionId)
    }

    func resetIfNeeded() {
        guard snapshot.phase == .idle else { return }
        cancelPendingWork()
    }

    private func canBeginPresentation(for discoveryId: Int64) -> Bool {
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
        DispatchQueue.main.asyncAfter(
            deadline: .now() + heroAnimator.openDuration,
            execute: workItem
        )
    }

    private func scheduleCloseCleanup(for sessionId: UUID) {
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
            deadline: .now() + heroAnimator.closeDuration + 0.1,
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
        DiscoveryDetailDismissInteractor(
            edgeActivationWidth: detailEdgeActivationWidth,
            dismissalDistance: computeDismissalDistance(),
            dismissalThreshold: detailDismissalThreshold
        )
    }

    private func computeDismissalDistance() -> CGFloat {
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

    private func cancelPendingWork() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

}
