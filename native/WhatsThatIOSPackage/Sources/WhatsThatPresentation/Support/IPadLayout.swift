import SwiftUI
import UIKit

/// Centralized layout constants for iPad adaptations
/// All iPad-specific constraints should reference these values
enum IPadLayout {
    /// Mini player max width on iPad (centered, not full width)
    static let miniPlayerMaxWidth: CGFloat = 500
    
    /// Toast max width (can be wider than mini player for content fit)
    static let toastMaxWidth: CGFloat = 540
    
    /// Onboarding image max width
    static let onboardingImageMaxWidth: CGFloat = 600
    
    /// Auth form content max width
    static let authContentMaxWidth: CGFloat = 400
    
    /// Audio player image max width
    static let audioPlayerImageMaxWidth: CGFloat = 400
}
