import Foundation
import StoreKit
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
        public let title: String
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
    @Published public private(set) var isRefreshingBalance = false
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var balance: Int?
    @Published public private(set) var creditPacks: [CreditPackItem] = []
    @Published public private(set) var activePurchaseIdentifier: String?
    @Published public var toastMessage: ToastMessage?
    @Published public var alertContent: AlertContent?

    private let creditsRepository: DiscoveryCreditsRepository
    private let store: CreditsStore
    private let balanceStore: CreditBalanceStore
    private let packDefinitions: [CreditPackDefinition]
    private var hasLoadedOnce = false

    public var onBalanceUpdated: ((Int?) -> Void)?

    public init(
        creditsRepository: DiscoveryCreditsRepository,
        store: CreditsStore,
        balanceStore: CreditBalanceStore,
        packDefinitions: [CreditPackDefinition] = CreditPackCatalog.standardPacks
    ) {
        self.creditsRepository = creditsRepository
        self.store = store
        self.balanceStore = balanceStore
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
            // Pre-populate with cached balance while we refresh.
            if let cached = await balanceStore.getCached() {
                updateBalance(cached)
            }

            // Fetch products from StoreKit
            let productsValue = try await fetchProducts()
            updateProducts(productsValue)

            // Refresh balance from our database
            isRefreshingBalance = true
            defer { isRefreshingBalance = false }
            do {
                let balanceValue = try await balanceStore.refreshIfStale()
                updateBalance(balanceValue)
            } catch {
                // If refresh fails, fall back to repository as a one-off.
                let balanceValue = try await fetchBalance()
                updateBalance(balanceValue)
            }
        } catch {
            present(error: error)
        }
    }


    public func refreshBalance() async {
        if isRefreshingBalance { return }
        isRefreshingBalance = true
        defer { isRefreshingBalance = false }

        do {
            let balanceValue = try await balanceStore.refresh(force: true)
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
            #if DEBUG
            print("[CreditsVM] Starting purchase for pack: \(pack.id)")
            #endif
            
            let result = try await store.purchase(productId: pack.id)
            
            #if DEBUG
            print("[CreditsVM] Purchase returned with status: \(result.status)")
            if let debugInfo = result.debugInfo {
                print("[CreditsVM] Debug info: \(debugInfo)")
            }
            #endif
            
            switch result.status {
            case .success:
                toastMessage = ToastMessage(
                    title: "Purchase complete",
                    message: "\(pack.creditAmount) credits added.",
                    style: .success
                )
                // Refresh balance after successful purchase
                do {
                    let newValue = try await balanceStore.refresh(force: true)
                    updateBalance(newValue)
                } catch {
                    #if DEBUG
                    print("[CreditsVM] Failed to refresh balance after purchase: \(error)")
                    #endif
                    // Purchase was successful but balance refresh failed - let user know
                    toastMessage = ToastMessage(
                        title: "Purchase complete",
                        message: "Your credits were added. If your balance doesn't update, try pulling down to refresh.",
                        style: .success
                    )
                }
            case .pending:
                toastMessage = ToastMessage(
                    title: "Purchase pending",
                    message: result.message ?? "We'll update your balance once it clears.",
                    style: .info
                )
            case .cancelled:
                #if DEBUG
                print("[CreditsVM] Purchase was cancelled. Message: \(result.message ?? "nil")")
                #endif
                toastMessage = ToastMessage(
                    title: "Purchase cancelled",
                    message: result.message ?? "The purchase was not completed.",
                    style: .info
                )
            }
        } catch {
            #if DEBUG
            print("[CreditsVM] Purchase threw error: \(error)")
            #endif
            alertContent = AlertContent(
                title: "Purchase failed",
                message: "Something went wrong with your purchase. Please try again. If the issue persists, check your payment method in Settings."
            )
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
                    isAvailable: product.isAvailable  // Use the actual availability from StoreKit
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
