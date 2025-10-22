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
                shortDescription: "Suspension bridge in San Francisco with Art Deco accents.",
                detailDescription: "The Golden Gate Bridge is a suspension bridge spanning the Golden Gate strait, the mile-wide channel between San Francisco Bay and the Pacific Ocean.",
                capturedAt: Date()
            ),
            DiscoverySummary(
                id: 9,
                title: "Yosemite Falls",
                highlight: "Iconic waterfall cascading 739 meters within Yosemite National Park.",
                shortDescription: "Iconic waterfall cascading within Yosemite National Park.",
                detailDescription: "Yosemite Falls drops a total of 739 meters and is one of the tallest waterfalls in North America, visible from numerous viewpoints across the valley.",
                capturedAt: Date().addingTimeInterval(-86_400)
            ),
            DiscoverySummary(
                id: 8,
                title: "Alcatraz Island",
                highlight: "Former federal prison island with panoramic bay views.",
                shortDescription: "Former federal prison island with panoramic bay views.",
                detailDescription: "Often called The Rock, Alcatraz Island housed a fort, military prison, and federal penitentiary before becoming a national recreation area.",
                capturedAt: Date().addingTimeInterval(-172_800)
            ),
            DiscoverySummary(
                id: 7,
                title: "Muir Woods",
                highlight: "Ancient coastal redwood forest just north of San Francisco.",
                shortDescription: "Ancient coastal redwood forest north of San Francisco.",
                detailDescription: "Muir Woods National Monument preserves old-growth coast redwood forests with trees soaring over 76 meters tall alongside tranquil walking trails.",
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
