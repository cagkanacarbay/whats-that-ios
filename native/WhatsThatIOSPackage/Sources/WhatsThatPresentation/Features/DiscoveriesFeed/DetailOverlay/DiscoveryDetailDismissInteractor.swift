#if canImport(UIKit)
import CoreGraphics

struct DiscoveryDetailDismissMetrics {
    let translation: CGSize
    let scale: CGFloat
    let rotation: Double
    let shadowOpacity: Double
    let cornerRadius: CGFloat
}

struct DiscoveryDetailDismissInteractor {
    let edgeActivationWidth: CGFloat
    let dismissalDistance: CGFloat
    let dismissalThreshold: CGFloat

    func canBeginInteraction(startLocation: CGPoint, translation: CGSize) -> Bool {
        guard startLocation.x <= edgeActivationWidth else { return false }
        guard translation.width > 0 else { return false }
        return abs(translation.width) >= abs(translation.height)
    }

    func metrics(for translation: CGSize) -> DiscoveryDetailDismissMetrics {
        let translationX = max(translation.width, 0)
        let translationY = translation.height * 0.5
        let normalizedProgress = min(max(translationX / dismissalDistance, 0), 1)

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
            cornerRadius: borderRadius
        )
    }

    func shouldDismiss(translation: CGSize, predictedTranslation: CGSize) -> Bool {
        let horizontalTranslation = max(translation.width, 0)
        let predicted = max(predictedTranslation.width, horizontalTranslation)
        return predicted > dismissalThreshold || horizontalTranslation > dismissalThreshold
    }
}
#endif
