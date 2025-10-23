import OSLog
import SwiftUI
import UIKit
import WhatsThatShared

enum DiscoveryDetailLayout {
    static let expandedImageHeightFraction: CGFloat = 0.8
    static let cardCornerRadius: CGFloat = BrandCornerRadius.large
}

struct DiscoveryDetailHeroAnimator {
    let openDuration: TimeInterval = 0.4
    let closeDuration: TimeInterval = 0.65

    func openAnimation() -> Animation {
        .timingCurve(0.33, 1.0, 0.68, 1.0, duration: openDuration)
    }

    func closeAnimation() -> Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: closeDuration)
    }
}

struct DiscoveryDetailHeroGeometry {
    let size: CGSize
    let offset: CGPoint
    let cornerRadius: CGFloat
    let imageHeight: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    init(
        startFrame: CGRect,
        containerSize: CGSize,
        containerOrigin: CGPoint,
        targetAspectRatio: CGFloat,
        progress: CGFloat,
        targetExpandedHeightFraction: CGFloat,
        enforceAspectForImage: Bool = false,
        isClosing: Bool = false
    ) {
        let clamped = max(0, min(progress, 1))
        let startX = startFrame.minX - containerOrigin.x
        let startY = startFrame.minY - containerOrigin.y
        let width = Self.lerp(startFrame.width, containerSize.width, clamped)
        let height = Self.lerp(startFrame.height, containerSize.height, clamped)
        let x = Self.lerp(startX, 0, clamped)
        let y = Self.lerp(startY, 0, clamped)
        let aspectRatio = targetAspectRatio.isFinite && targetAspectRatio > 0.1
            ? targetAspectRatio
            : startFrame.height / max(startFrame.width, 1)

        let imageHeight: CGFloat
        if enforceAspectForImage {
            let ratioHeight = width * aspectRatio
            let desiredHeight = min(containerSize.height, ratioHeight)
            let resolvedHeight = max(startFrame.height, desiredHeight)
            imageHeight = Self.lerp(startFrame.height, resolvedHeight, clamped)
        } else {
            let widthDrivenHeight = min(containerSize.height, containerSize.width * aspectRatio)
            let clampedFraction = max(0, min(targetExpandedHeightFraction, 1))
            let fractionHeight = containerSize.height * clampedFraction
            let desiredHeight = min(containerSize.height, max(widthDrivenHeight, fractionHeight))
            let resolvedHeight = max(startFrame.height, desiredHeight)
            imageHeight = Self.lerp(startFrame.height, resolvedHeight, clamped)
        }

        self.size = CGSize(width: width, height: height)
        self.offset = CGPoint(x: x, y: y)
        self.cornerRadius = Self.cornerRadius(for: clamped, isClosing: isClosing)
        self.imageHeight = imageHeight
        self.shadowOpacity = Double(clamped) * 0.3
        self.shadowRadius = shadowOpacity > 0 ? 20 : 0
        self.shadowYOffset = shadowOpacity > 0 ? 12 : 0
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat) -> CGFloat {
        from + (to - from) * fraction
    }

    private static func cornerRadius(for progress: CGFloat, isClosing: Bool) -> CGFloat {
        if isClosing {
            return DiscoveryDetailLayout.cardCornerRadius
        }

        let start: CGFloat = 0.75
        let clamped = max(0, min(progress, 1))
        if clamped >= 1 {
            return 0
        }
        if clamped <= start {
            return DiscoveryDetailLayout.cardCornerRadius
        }

        let normalization = max(0, min((clamped - start) / (1 - start), 1))
        let eased = normalization * normalization * (3 - 2 * normalization)
        return DiscoveryDetailLayout.cardCornerRadius * (1 - eased)
    }
}

let discoveryDetailHeroLogger = Logger(subsystem: "WhatsThatIOS", category: "HeroTransition")

func logDiscoveryDetailHeroGeometry(
    phase: String,
    progress: CGFloat,
    containerSize: CGSize,
    startFrame: CGRect,
    width: CGFloat,
    height: CGFloat,
    imageHeight: CGFloat,
    cardAspect: CGFloat,
    pullDown: CGFloat,
    isChromeReady: Bool,
    isClosing: Bool
) {
    guard isClosing else { return }

    let currentAspect = height / max(width, 1)
    let widthDrivenHeight = width * cardAspect
    let heightDelta = imageHeight - widthDrivenHeight

    discoveryDetailHeroLogger.debug(
        "[Hero] phase=\(phase, privacy: .public) progress=\(progress, privacy: .public) width=\(width, privacy: .public) height=\(height, privacy: .public) imageHeight=\(imageHeight, privacy: .public) widthDrivenHeight=\(widthDrivenHeight, privacy: .public) heightDelta=\(heightDelta, privacy: .public) currentAspect=\(currentAspect, privacy: .public) cardAspect=\(cardAspect, privacy: .public) container=\(String(describing: containerSize), privacy: .public) start=\(String(describing: startFrame), privacy: .public) pullDown=\(pullDown, privacy: .public) chromeReady=\(isChromeReady, privacy: .public)"
    )
}

struct DiscoveryDetailUniformCloseTransform: ViewModifier {
    let isClosing: Bool
    let progress: CGFloat
    let startFrame: CGRect
    let containerFrame: CGRect
    let initialScale: CGFloat
    let initialOffset: CGSize
    let initialRotation: Double
    let baseWidth: CGFloat
    let baseHeight: CGFloat

    static func transformProgress(for progress: CGFloat) -> CGFloat {
        max(0, min(1, 1 - progress))
    }

    static func resolvedScale(
        transformProgress: CGFloat,
        startFrame: CGRect,
        containerFrame: CGRect,
        initialScale: CGFloat
    ) -> CGFloat {
        let containerWidth = max(containerFrame.width, 1)
        let startScale = max(startFrame.width, 1) / containerWidth
        let clampedInitialScale = initialScale.isFinite ? max(0.5, min(initialScale, 1.2)) : 1
        return clampedInitialScale + (startScale - clampedInitialScale) * transformProgress
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isClosing {
            let transformProgress = Self.transformProgress(for: progress)
            let targetCenterX = startFrame.midX - containerFrame.origin.x
            let targetCenterY = startFrame.midY - containerFrame.origin.y
            let scale = Self.resolvedScale(
                transformProgress: transformProgress,
                startFrame: startFrame,
                containerFrame: containerFrame,
                initialScale: initialScale
            )
            let currentCenterX = baseWidth / 2
            let currentCenterY = baseHeight / 2
            let targetOffsetX = targetCenterX - currentCenterX
            let targetOffsetY = targetCenterY - currentCenterY
            let offsetX = initialOffset.width + (targetOffsetX - initialOffset.width) * transformProgress
            let offsetY = initialOffset.height + (targetOffsetY - initialOffset.height) * transformProgress
            let rotation = initialRotation + (0 - initialRotation) * transformProgress

            content
                .scaleEffect(scale, anchor: .center)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .offset(x: offsetX, y: offsetY)
        } else {
            content
        }
    }
}
