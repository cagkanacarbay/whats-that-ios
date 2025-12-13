import Foundation
import WhatsThatDomain

/// Model for a generation complete toast notification
public struct GenerationCompleteToast: Identifiable, Equatable {
    public let id: UUID
    public let discovery: DiscoverySummary
    public let createdAt: Date
    
    public init(discovery: DiscoverySummary) {
        self.id = UUID()
        self.discovery = discovery
        self.createdAt = Date()
    }
    
    public static func == (lhs: GenerationCompleteToast, rhs: GenerationCompleteToast) -> Bool {
        lhs.id == rhs.id
    }
}
