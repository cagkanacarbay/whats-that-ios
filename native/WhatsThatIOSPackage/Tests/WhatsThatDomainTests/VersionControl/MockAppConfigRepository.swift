import Foundation
@testable import WhatsThatDomain

/// Mock repository for testing ComplianceUseCase
actor MockAppConfigRepository: AppConfigRepository {
    var fetchConfigResult: Result<AppConfigResponse, Error> = .failure(MockError.notConfigured)
    var acceptTermsResult: Result<AcceptTermsResponse, Error> = .failure(MockError.notConfigured)

    private(set) var fetchConfigCallCount = 0
    private(set) var acceptTermsCallCount = 0
    private(set) var lastAcceptedTosVersion: String?
    private(set) var lastAcceptedPrivacyVersion: String?

    enum MockError: Error {
        case notConfigured
        case networkError
    }

    func fetchConfig() async throws -> AppConfigResponse {
        fetchConfigCallCount += 1
        switch fetchConfigResult {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        acceptTermsCallCount += 1
        lastAcceptedTosVersion = tosVersion
        lastAcceptedPrivacyVersion = privacyVersion
        switch acceptTermsResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Configuration Helpers

    func setFetchConfigResult(_ result: Result<AppConfigResponse, Error>) {
        fetchConfigResult = result
    }

    func setAcceptTermsResult(_ result: Result<AcceptTermsResponse, Error>) {
        acceptTermsResult = result
    }
}
