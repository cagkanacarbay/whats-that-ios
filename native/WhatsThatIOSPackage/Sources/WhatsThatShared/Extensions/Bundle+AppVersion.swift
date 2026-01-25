import Foundation

public extension Bundle {
    /// The app's marketing version (CFBundleShortVersionString), e.g., "1.2.0"
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// The app's build number (CFBundleVersion), e.g., "42"
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Full version string combining marketing version and build number
    /// e.g., "1.2.0 (42)"
    var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}
