import Foundation
import WhatsThatDomain
import WhatsThatInfrastructure

public struct StubDiscoveryRepository: DiscoveryRepository {
    private let samples: [DiscoverySummary]

    public init(transport _: SupabaseTransport = StubSupabaseTransport()) {
        self.samples = [
            DiscoverySummary(
                id: 10,
                title: "Golden Gate Bridge",
                highlight: "Suspension bridge in San Francisco with Art Deco accents.",
                capturedAt: Date()
            ),
            DiscoverySummary(
                id: 9,
                title: "Yosemite Falls",
                highlight: "Iconic waterfall cascading 739 meters within Yosemite National Park.",
                capturedAt: Date().addingTimeInterval(-86_400)
            ),
            DiscoverySummary(
                id: 8,
                title: "Alcatraz Island",
                highlight: "Former federal prison island with panoramic bay views.",
                capturedAt: Date().addingTimeInterval(-172_800)
            ),
            DiscoverySummary(
                id: 7,
                title: "Muir Woods",
                highlight: "Ancient coastal redwood forest just north of San Francisco.",
                capturedAt: Date().addingTimeInterval(-259_200)
            )
        ]
    }

    public func fetchDiscoveries(limit: Int, before discoveryId: Int64?) async throws -> [DiscoverySummary] {
        let ordered = samples.sorted { $0.id > $1.id }
        let filtered: [DiscoverySummary]

        if let discoveryId {
            filtered = ordered.filter { $0.id < discoveryId }
        } else {
            filtered = ordered
        }

        if filtered.isEmpty {
            return []
        }

        return Array(filtered.prefix(limit))
    }
}
