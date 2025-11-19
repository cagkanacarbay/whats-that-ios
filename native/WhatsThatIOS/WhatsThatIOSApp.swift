import SwiftUI
import WhatsThatApp
import WhatsThatPresentation

@main
struct WhatsThatIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var passwordResetLinkCoordinator = PasswordResetLinkCoordinator()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(passwordResetLinkCoordinator)
                .onOpenURL { url in
                    passwordResetLinkCoordinator.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    passwordResetLinkCoordinator.handle(url)
                }
        }
    }
}
