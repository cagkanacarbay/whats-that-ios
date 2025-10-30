#if os(iOS) && USE_REMOTE_DEPS && canImport(StoreKit) && canImport(Supabase)
import Foundation
import StoreKit
import Supabase
import WhatsThatDomain
import WhatsThatShared

enum CreditsStoreError: LocalizedError {
    case userNotAuthenticated
    case receiptUnavailable
    case validationFailed(String?)
    case unverifiedTransaction
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "You need to sign in before purchasing credits."
        case .receiptUnavailable:
            return "We couldn’t access the App Store receipt. Please try again in a moment."
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

    public func syncReceiptsOnCreditsOpen() async {
        // Always attempt a receipt sync when the user opens the Credits screen,
        // regardless of current receipt presence. This ensures the prompt
        // (if needed) happens here rather than during background flows.
        try? await AppStore.sync()
    }

    public func loadProducts() async throws -> [CreditProduct] {
        let products = try await Product.products(for: productIdentifiers)
        cachedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return CreditPackCatalog.standardPacks.map { definition in
            if let product = cachedProducts[definition.id] {
                return CreditProduct(
                    id: product.id,
                    title: product.displayName,
                    description: product.description,
                    displayPrice: product.displayPrice,
                    creditAmount: definition.creditAmount
                )
            } else {
                return CreditProduct(
                    id: definition.id,
                    title: definition.fallbackTitle,
                    description: definition.fallbackDescription,
                    displayPrice: "Unavailable",
                    creditAmount: definition.creditAmount
                )
            }
        }
    }

    public func purchase(productId: String) async throws -> CreditPurchaseResult {
        let product = try await loadProductIfNeeded(for: productId)

        // Preflight: if the app has no local receipt, refresh it now so any
        // Apple ID prompt (sandbox) happens before the purchase sheet.
        if !hasCurrentReceipt() {
            try? await AppStore.sync()
        }

        let purchaseResult = try await product.purchase()
        switch purchaseResult {
        case let .success(verification):
            let transaction = try verify(verification)
            do {
                try await validateTransaction(transaction, for: product, refreshReceipt: false)
            } catch let error as CreditsStoreError {
                // If receipt is still missing or the server couldn't find the
                // just-purchased transaction in the receipt, refresh once and
                // retry validation. In sandbox, this may prompt for Apple ID.
                let shouldRetry: Bool
                switch error {
                case .receiptUnavailable:
                    shouldRetry = true
                case .validationFailed(let message):
                    let lower = message?.lowercased() ?? ""
                    shouldRetry = lower.contains("transaction not found") || lower.contains("not found")
                default:
                    shouldRetry = false
                }
                if shouldRetry {
                    try? await AppStore.sync()
                    try await validateTransaction(transaction, for: product, refreshReceipt: false)
                } else {
                    throw error
                }
            }
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
        for product: Product,
        refreshReceipt: Bool = true
    ) async throws {
        guard let accessToken = client.auth.currentSession?.accessToken else {
            throw CreditsStoreError.userNotAuthenticated
        }

        // Use existing receipt when available; only refresh on-demand during
        // an explicit purchase flow to avoid unexpected sign-in prompts.
        let receiptData = try await fetchReceiptData(refreshIfMissing: refreshReceipt)
        guard let url = try makeFunctionsURL(for: "validate-receipt") else {
            throw CreditsStoreError.unsupportedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "platform": "ios",
            "receiptData": receiptData.base64EncodedString(),
            "productId": product.id,
            // Send both the StoreKit transaction id and the original id as strings
            // to match common server expectations for Apple receipt fields.
            "storeTransactionId": String(transaction.id),
            "originalTransactionId": String(transaction.originalID)
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

    func fetchReceiptData(refreshIfMissing: Bool) async throws -> Data {
        if let data = currentReceiptData(), !data.isEmpty {
            return data
        }

        if refreshIfMissing {
            try await AppStore.sync()
            if let data = currentReceiptData(), !data.isEmpty {
                return data
            }
        }

        throw CreditsStoreError.receiptUnavailable
    }

    func currentReceiptData() -> Data? {
        guard
            let url = Bundle.main.appStoreReceiptURL,
            let data = try? Data(contentsOf: url),
            !data.isEmpty
        else {
            return nil
        }
        return data
    }

    func hasCurrentReceipt() -> Bool {
        if let data = currentReceiptData(), !data.isEmpty { return true }
        return false
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
                    let transaction: Transaction = try self.verify(update)
                    let product = try await self.loadProductIfNeeded(for: transaction.productID)
                    do {
                        try await self.validateTransaction(transaction, for: product, refreshReceipt: false)
                    } catch {
                        // Do not call AppStore.sync() here to avoid prompting
                        // for Apple ID at app launch. The user can trigger a
                        // receipt sync from the Credits screen as needed.
                        throw error
                    }
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
