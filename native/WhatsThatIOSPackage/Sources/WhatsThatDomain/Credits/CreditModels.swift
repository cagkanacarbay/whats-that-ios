import Foundation

public struct CreditProduct: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let displayPrice: String
    public let creditAmount: Int

    public init(
        id: String,
        title: String,
        description: String,
        displayPrice: String,
        creditAmount: Int
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.displayPrice = displayPrice
        self.creditAmount = creditAmount
    }
}

public struct CreditPurchaseResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case success
        case pending
        case cancelled
    }

    public let status: Status
    public let message: String?

    public init(status: Status, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

public protocol CreditsStore: Sendable {
    func loadProducts() async throws -> [CreditProduct]
    func purchase(productId: String) async throws -> CreditPurchaseResult
    /// Called when the user opens the credits UI. Default no-op.
    /// Implementations may perform an optional receipt sync here.
    func syncReceiptsOnCreditsOpen() async
}

public extension CreditsStore {
    func syncReceiptsOnCreditsOpen() async {}
}

public struct CreditPackDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let creditAmount: Int
    public let fallbackTitle: String
    public let fallbackDescription: String
    public let iconSystemName: String

    public init(
        id: String,
        creditAmount: Int,
        fallbackTitle: String,
        fallbackDescription: String,
        iconSystemName: String
    ) {
        self.id = id
        self.creditAmount = creditAmount
        self.fallbackTitle = fallbackTitle
        self.fallbackDescription = fallbackDescription
        self.iconSystemName = iconSystemName
    }
}

public enum CreditPackCatalog {
    public static let standardPacks: [CreditPackDefinition] = [
        CreditPackDefinition(
            id: "100credits",
            creditAmount: 100,
            fallbackTitle: "Explorer Pack",
            fallbackDescription: "Unlock 100 discoveries for your next adventures.",
            iconSystemName: "sparkles"
        ),
        CreditPackDefinition(
            id: "1000credits",
            creditAmount: 1000,
            fallbackTitle: "Trailblazer Pack",
            fallbackDescription: "Fuel a thousand discoveries with our best value bundle.",
            iconSystemName: "globe.americas.fill"
        )
    ]
}
