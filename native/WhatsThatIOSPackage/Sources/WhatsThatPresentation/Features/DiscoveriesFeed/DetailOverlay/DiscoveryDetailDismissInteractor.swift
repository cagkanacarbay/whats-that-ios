import CoreGraphics

struct DiscoveryDetailDismissMetrics {
    let translation: CGSize
    let scale: CGFloat
    let rotation: Double
    let shadowOpacity: Double
    let cornerRadius: CGFloat
    let progress: CGFloat
}

struct DiscoveryDetailDismissInteractor {
    typealias DismissDirection = DiscoveryDetailOverlaySnapshot.DismissDirection

    let horizontalDismissalDistance: CGFloat
    let verticalDismissalDistance: CGFloat
    let horizontalDismissalThreshold: CGFloat
    let verticalDismissalThreshold: CGFloat
    let horizontalActivationTranslation: CGFloat
    let verticalActivationTranslation: CGFloat
    let dominantAxisSlack: CGFloat
    let allowVerticalDismiss: Bool

    init(
        horizontalDismissalDistance: CGFloat,
        verticalDismissalDistance: CGFloat,
        horizontalDismissalThreshold: CGFloat,
        verticalDismissalThreshold: CGFloat,
        horizontalActivationTranslation: CGFloat,
        verticalActivationTranslation: CGFloat,
        dominantAxisSlack: CGFloat = 6,
        allowVerticalDismiss: Bool
    ) {
        self.horizontalDismissalDistance = horizontalDismissalDistance
        self.verticalDismissalDistance = verticalDismissalDistance
        self.horizontalDismissalThreshold = horizontalDismissalThreshold
        self.verticalDismissalThreshold = verticalDismissalThreshold
        self.horizontalActivationTranslation = horizontalActivationTranslation
        self.verticalActivationTranslation = verticalActivationTranslation
        self.dominantAxisSlack = dominantAxisSlack
        self.allowVerticalDismiss = allowVerticalDismiss
    }

    func interactionDirection(startLocation _: CGPoint, translation: CGSize) -> DismissDirection? {
        let horizontalMagnitude = abs(translation.width)
        let verticalMagnitude = abs(translation.height)

        let isHorizontalEligible = translation.width > 0 && horizontalMagnitude >= horizontalActivationTranslation
        let isVerticalEligible = allowVerticalDismiss
            && translation.height > 0
            && verticalMagnitude >= verticalActivationTranslation

        guard isHorizontalEligible || isVerticalEligible else { return nil }

        let horizontalDominates = horizontalMagnitude >= verticalMagnitude + dominantAxisSlack
        let verticalDominates = verticalMagnitude >= horizontalMagnitude + dominantAxisSlack

        if horizontalDominates, isHorizontalEligible {
            return .horizontal
        }
        if verticalDominates, isVerticalEligible {
            return .vertical
        }

        if verticalMagnitude > horizontalMagnitude {
            if isVerticalEligible {
                return .vertical
            }
            return nil
        }

        if horizontalMagnitude > verticalMagnitude {
            if isHorizontalEligible {
                return .horizontal
            }
            return nil
        }

        if isVerticalEligible {
            return .vertical
        }
        if isHorizontalEligible {
            return .horizontal
        }
        return nil
    }

    func metrics(for translation: CGSize, direction: DismissDirection) -> DiscoveryDetailDismissMetrics {
        switch direction {
        case .horizontal:
            return horizontalMetrics(for: translation)
        case .vertical:
            return verticalMetrics(for: translation)
        }
    }

    func shouldDismiss(
        translation: CGSize,
        predictedTranslation: CGSize,
        direction: DismissDirection
    ) -> Bool {
        switch direction {
        case .horizontal:
            let horizontalTranslation = max(translation.width, 0)
            let predicted = max(predictedTranslation.width, horizontalTranslation)
            return predicted > horizontalDismissalThreshold || horizontalTranslation > horizontalDismissalThreshold
        case .vertical:
            let verticalTranslation = max(translation.height, 0)
            let predicted = max(predictedTranslation.height, verticalTranslation)
            return predicted > verticalDismissalThreshold || verticalTranslation > verticalDismissalThreshold
        }
    }

    private func horizontalMetrics(for translation: CGSize) -> DiscoveryDetailDismissMetrics {
        let translationX = max(translation.width, 0)
        let translationY = translation.height * 0.5
        let normalizedProgress = min(max(translationX / horizontalDismissalDistance, 0), 1)

        let clampedScaleProgress = min(normalizedProgress, 0.5) / 0.5
        let scaleReduction = 0.35 * clampedScaleProgress
        let scale = max(0.65, 1 - scaleReduction)

        let clampedRotationProgress = min(normalizedProgress, 0.5) / 0.5
        let rotation = -5 * Double(clampedRotationProgress)

        let borderRadius: CGFloat
        if normalizedProgress <= 0.1 {
            borderRadius = (normalizedProgress / 0.1) * 12
        } else {
            borderRadius = 12
        }

        let clampedShadowProgress = min(normalizedProgress, 0.3) / 0.3
        let shadowOpacity = Double(clampedShadowProgress * 0.3)

        return DiscoveryDetailDismissMetrics(
            translation: CGSize(width: translationX, height: translationY),
            scale: scale,
            rotation: rotation,
            shadowOpacity: shadowOpacity,
            cornerRadius: borderRadius,
            progress: normalizedProgress
        )
    }

    private func verticalMetrics(for translation: CGSize) -> DiscoveryDetailDismissMetrics {
        let translationY = max(translation.height, 0)
        let dampedX = max(min(translation.width * 0.3, 60), -60)
        let normalizedProgress = min(max(translationY / verticalDismissalDistance, 0), 1)

        let clampedScaleProgress = min(normalizedProgress, 0.5) / 0.5
        let scaleReduction = 0.28 * clampedScaleProgress
        let scale = max(0.7, 1 - scaleReduction)

        let borderRadius: CGFloat
        if normalizedProgress <= 0.1 {
            borderRadius = (normalizedProgress / 0.1) * 12
        } else {
            borderRadius = 12
        }

        let clampedShadowProgress = min(normalizedProgress, 0.4) / 0.4
        let shadowOpacity = Double(clampedShadowProgress * 0.25)

        return DiscoveryDetailDismissMetrics(
            translation: CGSize(width: dampedX, height: translationY),
            scale: scale,
            rotation: 0,
            shadowOpacity: shadowOpacity,
            cornerRadius: borderRadius,
            progress: normalizedProgress
        )
    }
}
