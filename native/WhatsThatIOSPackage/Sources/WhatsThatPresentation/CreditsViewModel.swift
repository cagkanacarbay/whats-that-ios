import Foundation
import SwiftUI
import WhatsThatDomain

@MainActor
public final class CreditsViewModel: ObservableObject {
    public struct CreditPackItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let description: String
        public let price: String
        public let creditAmount: Int
        public let iconSystemName: String
        public let isAvailable: Bool
    }

    public struct ToastMessage: Identifiable {
        public enum Style {
            case success
            case info
            case warning

            var tint: Color {
                switch self {
                case .success:
                    return Color.green
                case .info:
                    return Color.blue
                case .warning:
                    return Color.orange
                }
            }
        }

        public let id = UUID()
        public let message: String
        public let style: Style
    }

    public struct AlertContent: Identifiable {
        public let id = UUID()
        public let title: String
        public let message: String
    }

    @Published public private(set) var isLoading = false
    @Published public private(set) var isFetchingProducts = false
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var balance: Int?
    @Published public private(set) var creditPacks: [CreditPackItem] = []
    @Published public private(set) var activePurchaseIdentifier: String?
    @Published public var toastMessage: ToastMessage?
    @Published public var alertContent: AlertContent?

    private let creditsRepository: DiscoveryCreditsRepository
    private let store: CreditsStore
    private let packDefinitions: [CreditPackDefinition]
    private var hasLoadedOnce = false

    public var onBalanceUpdated: ((Int?) -> Void)?

    public init(
        creditsRepository: DiscoveryCreditsRepository,
        store: CreditsStore,
        packDefinitions: [CreditPackDefinition] = CreditPackCatalog.standardPacks
    ) {
        self.creditsRepository = creditsRepository
        self.store = store
        self.packDefinitions = packDefinitions
    }

    public func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        await load()
    }

    public func load() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let balanceTask = fetchBalance()
            async let productsTask = fetchProducts()

            let balanceValue = try await balanceTask
            let productsValue = try await productsTask

            updateBalance(balanceValue)
            updateProducts(productsValue)
        } catch {
            present(error: error)
        }
    }

    public func refreshBalance() async {
        do {
            let balanceValue = try await fetchBalance()
            updateBalance(balanceValue)
        } catch {
            present(error: error)
        }
    }

    public func purchase(_ pack: CreditPackItem) async {
        guard pack.isAvailable else {
            alertContent = AlertContent(
                title: "Not available",
                message: "This credit pack isn’t available right now. Please try again later."
            )
            return
        }

        if isPurchasing { return }
        isPurchasing = true
        activePurchaseIdentifier = pack.id
        defer {
            isPurchasing = false
            activePurchaseIdentifier = nil
        }

        do {
            let result = try await store.purchase(productId: pack.id)
            switch result.status {
            case .success:
                toastMessage = ToastMessage(
                    message: result.message ?? "Purchase successful! Check out your new credits.",
                    style: .success
                )
                let balanceValue = try await fetchBalance()
                updateBalance(balanceValue)
            case .pending:
                toastMessage = ToastMessage(
                    message: result.message ?? "This purchase is pending. We’ll update your balance as soon as it clears.",
                    style: .info
                )
            case .cancelled:
                if let message = result.message, !message.isEmpty {
                    toastMessage = ToastMessage(message: message, style: .info)
                }
            }
        } catch {
            present(error: error)
        }
    }

    private func fetchBalance() async throws -> Int {
        try await creditsRepository.fetchCreditBalance()
    }

    private func fetchProducts() async throws -> [CreditProduct] {
        isFetchingProducts = true
        defer { isFetchingProducts = false }
        return try await store.loadProducts()
    }

    private func updateBalance(_ value: Int) {
        balance = value
        onBalanceUpdated?(value)
    }

    private func updateProducts(_ products: [CreditProduct]) {
        let mapped = mapProducts(products)
        creditPacks = mapped
    }

    private func mapProducts(_ products: [CreditProduct]) -> [CreditPackItem] {
        let lookup = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return packDefinitions.map { definition in
            if let product = lookup[definition.id] {
                return CreditPackItem(
                    id: definition.id,
                    title: product.title,
                    description: product.description,
                    price: product.displayPrice,
                    creditAmount: definition.creditAmount,
                    iconSystemName: definition.iconSystemName,
                    isAvailable: true
                )
            } else {
                return CreditPackItem(
                    id: definition.id,
                    title: definition.fallbackTitle,
                    description: definition.fallbackDescription,
                    price: "Unavailable",
                    creditAmount: definition.creditAmount,
                    iconSystemName: definition.iconSystemName,
                    isAvailable: false
                )
            }
        }
    }

    private func present(error: Error) {
        alertContent = AlertContent(
            title: "Something went wrong",
            message: error.localizedDescription
        )
    }
}
