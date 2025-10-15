import Foundation
import SwiftUI
import WhatsThatDomain
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
        #if os(iOS)
        let makeViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel = {
            container.makeDiscoveryCreationViewModel(for: $0)
        }
        #else
        let makeViewModel: (DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel = { _ in
            fatalError("Discovery creation flow is only supported on iOS.")
        }
        #endif

        return RootContentView(
            feedUseCase: container.discoveryFeedUseCase,
            authUseCase: container.authUseCase,
            onboardingUseCase: container.onboardingUseCase,
            flowResolver: container.flowResolver,
            makeCreationViewModel: makeViewModel
        )
    }
}
