import Foundation

public actor DiscoveryDeletionUseCase: Sendable {
    private let repository: DiscoveryRepository

    public init(repository: DiscoveryRepository) {
        self.repository = repository
    }

    public func delete(_ summary: DiscoverySummary) async throws {
        try await repository.deleteDiscovery(summary)
    }
}
