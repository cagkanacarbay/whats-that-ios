#if os(iOS)
import Foundation
import WhatsThatDomain
import WhatsThatInfrastructure
import WhatsThatPresentation

struct DiscoveryCreationDependencyProvider: @unchecked Sendable {
    private let maxImageDimension: Int
    private let recentHistoryLimit: Int
    private let captureService: DiscoveryCaptureService
    private let selectionService: DiscoverySelectionService
    private let historyRepository: DiscoveryHistoryRepository
    private let creditsRepository: DiscoveryCreditsRepository
    private let creditBalanceStore: CreditBalanceStore
    private let analysisClient: DiscoveryAnalysisClient
    private let imageEncoder: DiscoveryImageEncodingService
    private let pushService: DiscoveryPushService
    private let locationService: DiscoveryLocationService
    private let voiceoverRepository: (any DiscoveryVoiceoverRepository)?
    private let voiceoverPreferencesStore: VoiceoverPreferencesStore?
    private let ipopPreferencesStore: IPoPPreferencesStore?

    init(
        maxImageDimension: Int,
        recentHistoryLimit: Int,
        captureService: DiscoveryCaptureService,
        selectionService: DiscoverySelectionService,
        historyRepository: DiscoveryHistoryRepository,
        creditsRepository: DiscoveryCreditsRepository,
        creditBalanceStore: CreditBalanceStore,
        analysisClient: DiscoveryAnalysisClient,
        imageEncoder: DiscoveryImageEncodingService,
        pushService: DiscoveryPushService,
        locationService: DiscoveryLocationService,
        voiceoverRepository: (any DiscoveryVoiceoverRepository)?,
        voiceoverPreferencesStore: VoiceoverPreferencesStore?,
        ipopPreferencesStore: IPoPPreferencesStore?
    ) {
        self.maxImageDimension = maxImageDimension
        self.recentHistoryLimit = recentHistoryLimit
        self.captureService = captureService
        self.selectionService = selectionService
        self.historyRepository = historyRepository
        self.creditsRepository = creditsRepository
        self.creditBalanceStore = creditBalanceStore
        self.analysisClient = analysisClient
        self.imageEncoder = imageEncoder
        self.pushService = pushService
        self.locationService = locationService
        self.voiceoverRepository = voiceoverRepository
        self.voiceoverPreferencesStore = voiceoverPreferencesStore
        self.ipopPreferencesStore = ipopPreferencesStore
    }

    @MainActor
    func makeViewModel(for type: DiscoveryCreationFlowType) -> DiscoveryCreationFlowViewModel {
        DiscoveryCreationFlowViewModel(
            configuration: .init(
                type: type,
                maxImageDimension: maxImageDimension,
                recentHistoryLimit: recentHistoryLimit
            ),
            captureService: captureService,
            selectionService: selectionService,
            historyRepository: historyRepository,
            creditsRepository: creditsRepository,
            creditBalanceStore: creditBalanceStore,
            analysisClient: analysisClient,
            imageEncoder: imageEncoder,
            pushService: pushService,
            locationService: locationService,
            voiceoverRepository: voiceoverRepository,
            voiceoverPreferencesStore: voiceoverPreferencesStore,
            ipopPreferencesStore: ipopPreferencesStore
        )
    }
}
#endif
