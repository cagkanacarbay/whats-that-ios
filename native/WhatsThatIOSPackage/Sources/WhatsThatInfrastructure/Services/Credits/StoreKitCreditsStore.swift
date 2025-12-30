#if os(iOS) && USE_REMOTE_DEPS && canImport(StoreKit) && canImport(Supabase)
import Foundation
import StoreKit
import Supabase
import WhatsThatDomain
import WhatsThatShared

enum CreditsStoreError: LocalizedError {
    case userNotAuthenticated
    case validationFailed(String?)
    case unverifiedTransaction
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "You need to sign in before purchasing credits."
        case let .validationFailed(message):
            if let message, !message.isEmpty {
                return message
            }
            return "The App Store could not confirm this purchase. Please contact support if the issue persists."
        case .unverifiedTransaction:
            return "Apple was unable to verify this transaction."
        case .unsupportedResponse:
            return "Received an unexpected response from the server."
        }
    }
}

public actor StoreKitCreditsStore: CreditsStore {
    private let configuration: AppConfiguration
    private let client: SupabaseClient
    private let urlSession: URLSession
    private let productIdentifiers: [String]
    private var cachedProducts: [String: Product] = [:]

    public init(
        productIdentifiers: [String],
        configuration: AppConfiguration,
        client: SupabaseClient,
        urlSession: URLSession = .shared
    ) {
        self.productIdentifiers = productIdentifiers
        self.configuration = configuration
        self.client = client
        self.urlSession = urlSession
    }

    public func restorePurchases() async throws {
        // Manually sync App Store receipts. This is triggered by user action
        // (Restore Purchases button) rather than automatically on screen load.
        try await AppStore.sync()
    }

    public func loadProducts() async throws -> [CreditProduct] {
        let products = try await Product.products(for: productIdentifiers)
        cachedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        // Always use our local titles and descriptions for consistent branding.
        // Only take the price from Apple (localized for the user's region).
        return CreditPackCatalog.standardPacks.map { definition in
            let displayPrice = cachedProducts[definition.id]?.displayPrice ?? "Unavailable"
            
            return CreditProduct(
                id: definition.id,
                title: definition.fallbackTitle,
                description: definition.fallbackDescription,
                displayPrice: displayPrice,
                creditAmount: definition.creditAmount
            )
        }
    }

    public func purchase(productId: String) async throws -> CreditPurchaseResult {
        let product = try await loadProductIfNeeded(for: productId)
        let purchaseResult = try await product.purchase()
        
        switch purchaseResult {
        case let .success(verification):
            // Extract JWS from VerificationResult before unwrapping
            let jwsString = verification.jwsRepresentation
            let transaction = try verify(verification)
            
            // Validate with server using StoreKit 2's signed JWS
            try await validateTransaction(transaction, jwsString: jwsString, for: product)
            
            await transaction.finish()
            return CreditPurchaseResult(status: .success)
        case .pending:
            return CreditPurchaseResult(
                status: .pending,
                message: "Your purchase is pending approval from Apple."
            )
        case .userCancelled:
            return CreditPurchaseResult(status: .cancelled, message: nil)
        @unknown default:
            throw CreditsStoreError.validationFailed(nil)
        }
    }
}

private extension StoreKitCreditsStore {
    func loadProductIfNeeded(for identifier: String) async throws -> Product {
        if let product = cachedProducts[identifier] {
            return product
        }

        let fetched = try await Product.products(for: [identifier])
        if let product = fetched.first {
            cachedProducts[identifier] = product
            return product
        }

        throw CreditsStoreError.validationFailed("That credit pack is currently unavailable. Please try again later.")
    }

    func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(safe):
            return safe
        case .unverified:
            throw CreditsStoreError.unverifiedTransaction
        }
    }

    func validateTransaction(
        _ transaction: Transaction,
        jwsString: String,
        for product: Product
    ) async throws {
        guard let accessToken = client.auth.currentSession?.accessToken else {
            throw CreditsStoreError.userNotAuthenticated
        }

        guard let url = try makeFunctionsURL(for: "validate-receipt") else {
            throw CreditsStoreError.unsupportedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "platform": "ios",
            "signedTransaction": jwsString,
            "productId": product.id,
            "storeTransactionId": String(transaction.originalID)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CreditsStoreError.unsupportedResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if (200..<300).contains(httpResponse.statusCode) {
            let outcome = try decoder.decode(ValidateReceiptResponse.self, from: data)
            guard outcome.success else {
                throw CreditsStoreError.validationFailed(outcome.message)
            }
        } else {
            let outcome = try? decoder.decode(ValidateReceiptResponse.self, from: data)
            throw CreditsStoreError.validationFailed(outcome?.message)
        }
    }

    func makeFunctionsURL(for pathComponent: String) throws -> URL? {
        guard let supabaseURL = configuration.supabaseURL else {
            throw CreditsStoreError.unsupportedResponse
        }

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.host = supabaseURL
            .host?
            .replacingOccurrences(of: ".supabase.co", with: ".functions.supabase.co")
        guard var url = components?.url else {
            return nil
        }
        url.appendPathComponent(pathComponent)
        return url
    }
}

private struct ValidateReceiptResponse: Decodable {
    let success: Bool
    let message: String?
}

#if os(iOS)
public extension StoreKitCreditsStore {
    /// Clears local StoreKit cache and optionally deletes the on-disk App Store receipt.
    /// This does not sign the user out of the App Store (system-level),
    /// but simulates a fresh state for testing prompts and purchase flows.
    func clearLocalStoreState(deleteReceipt: Bool = true) {
        cachedProducts.removeAll()
        if deleteReceipt,
           let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path) {
            _ = try? FileManager.default.removeItem(at: receiptURL)
        }
    }

    /// Starts a background listener for StoreKit transaction updates.
    /// Ensures out-of-band purchases are validated and finished.
    /// Optionally refreshes the credit balance upon successful validation.
    @discardableResult
    func startListeningForTransactionUpdates(balanceStore: CreditBalanceStore? = nil) -> Task<Void, Never> {
        Task {
            for await update in Transaction.updates {
                do {
                    let jwsString = update.jwsRepresentation
                    let transaction: Transaction = try self.verify(update)
                    let product = try await self.loadProductIfNeeded(for: transaction.productID)
                    try await self.validateTransaction(transaction, jwsString: jwsString, for: product)
                    await transaction.finish()
                    if let balanceStore {
                        _ = try? await balanceStore.refresh(force: true)
                    }
                } catch {
                    // Intentionally swallow errors here; user will have an
                    // opportunity to retry purchases from the Credits screen.
                }
            }
        }
    }
}
#endif
#endif
