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
            id: "100.credits",
            creditAmount: 100,
            fallbackTitle: "100 Credits",
            fallbackDescription: "Create up to 100 discoveries or 50 discoveries and 50 audio guides.",
            iconSystemName: "banknote"
        ),
        CreditPackDefinition(
            id: "1000.credits",
            creditAmount: 1000,
            fallbackTitle: "1,000 Credits",
            fallbackDescription: "Create up to 1,000 discoveries or 500 discoveries and 500 audio guides.",
            iconSystemName: "crown"
        )
    ]
}
