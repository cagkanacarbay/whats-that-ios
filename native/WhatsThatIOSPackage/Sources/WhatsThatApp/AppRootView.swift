import Foundation
import SwiftUI
import WhatsThatPresentation
import WhatsThatShared

public struct AppRootView: View {
    private let container: AppDependencyContainer

    public init(
        configuration: AppConfiguration = .fromBundle(),
        session: URLSession = .shared
    ) {
        self.container = AppDependencyContainer.bootstrap(
            configuration: configuration,
            session: session
        )
    }

    public var body: some View {
        RootContentView(
            feedUseCase: container.discoveryFeedUseCase,
            authUseCase: container.authUseCase,
            onboardingUseCase: container.onboardingUseCase,
            flowResolver: container.flowResolver
        )
    }
}
