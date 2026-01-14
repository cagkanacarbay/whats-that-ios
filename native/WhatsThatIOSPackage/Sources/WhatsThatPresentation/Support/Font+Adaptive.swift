import SwiftUI
import UIKit

extension Font {
    /// Creates an adaptive system font that scales up on iPad
    /// - Parameters:
    ///   - size: Base size for iPhone
    ///   - weight: Font weight (default: .regular)
    ///   - scaleFactor: iPad scale multiplier (default: 1.4x)
    /// - Returns: Font with original size on iPhone, scaled size on iPad
    static func adaptiveSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        scaleFactor: CGFloat = 1.4
    ) -> Font {
        let finalSize = UIDevice.isIPad ? size * scaleFactor : size
        return .system(size: finalSize, weight: weight)
    }

    /// Large title text — iPhone: .title, iPad: .largeTitle
    static func adaptiveLargeTitle() -> Font {
        UIDevice.isIPad ? .largeTitle : .title
    }
    
    /// Title text — iPhone: .title2, iPad: .title
    static func adaptiveTitle() -> Font {
        UIDevice.isIPad ? .title : .title2
    }
    
    /// Body text — iPhone: .body, iPad: .title3
    static func adaptiveBody() -> Font {
        UIDevice.isIPad ? .title3 : .body
    }
    
    /// Callout text — iPhone: .callout, iPad: .body
    static func adaptiveCallout() -> Font {
        UIDevice.isIPad ? .body : .callout
    }
    
    /// Caption text — iPhone: .caption, iPad: .callout
    static func adaptiveCaption() -> Font {
        UIDevice.isIPad ? .callout : .caption
    }
    
    /// Footnote text — iPhone: .footnote, iPad: .body
    static func adaptiveFootnote() -> Font {
        UIDevice.isIPad ? .body : .footnote
    }
}
