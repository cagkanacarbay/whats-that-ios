import UIKit

extension UIDevice {
    /// Returns true if running on iPad, false on iPhone
    /// Safe to use for conditional UI—iPhone code path is completely isolated
    public static var isIPad: Bool {
        current.userInterfaceIdiom == .pad
    }
}
