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

    public func loadProducts() async throws -> [CreditProduct] {
        let products = try await Product.products(for: productIdentifiers)
        cachedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        // Log diagnostic info for debugging StoreKit issues
        #if DEBUG
        print("[StoreKit] Requested \(productIdentifiers.count) products, received \(products.count)")
        if products.isEmpty {
            print("[StoreKit] WARNING: No products returned from App Store")
            print("[StoreKit] Requested IDs: \(productIdentifiers)")
        } else {
            print("[StoreKit] Received products: \(products.map { $0.id })")
        }
        // Log invalid product identifiers if any
        let invalidIds = Set(productIdentifiers).subtracting(products.map { $0.id })
        if !invalidIds.isEmpty {
            print("[StoreKit] ERROR: Invalid Product IDs: \(invalidIds)")
        }
        #endif

        // Always use our local titles and descriptions for consistent branding.
        // Only take the price from Apple (localized for the user's region).
        // Mark products as available only if they were actually returned by StoreKit.
        return CreditPackCatalog.standardPacks.map { definition in
            let storeKitProduct = cachedProducts[definition.id]
            let displayPrice = storeKitProduct?.displayPrice ?? "Unavailable"
            let isAvailable = storeKitProduct != nil
            
            return CreditProduct(
                id: definition.id,
                title: definition.fallbackTitle,
                description: definition.fallbackDescription,
                displayPrice: displayPrice,
                creditAmount: definition.creditAmount,
                isAvailable: isAvailable
            )
        }
    }

    public func purchase(productId: String) async throws -> CreditPurchaseResult {
        #if DEBUG
        print("[StoreKit] Starting purchase for productId: \(productId)")
        #endif
        
        let product = try await loadProductIfNeeded(for: productId)
        
        #if DEBUG
        print("[StoreKit] Product loaded, initiating StoreKit purchase...")
        #endif
        
        let purchaseResult = try await product.purchase()
        
        #if DEBUG
        print("[StoreKit] StoreKit purchase returned")
        #endif
        
        switch purchaseResult {
        case let .success(verification):
            #if DEBUG
            print("[StoreKit] Purchase result: SUCCESS - extracting transaction")
            #endif
            
            // Extract JWS from VerificationResult before unwrapping
            let jwsString = verification.jwsRepresentation
            let transaction = try verify(verification)
            
            #if DEBUG
            print("[StoreKit] Transaction verified, calling validate-receipt edge function...")
            #endif
            
            // Validate with server using StoreKit 2's signed JWS
            try await validateTransaction(transaction, jwsString: jwsString, for: product)
            
            #if DEBUG
            print("[StoreKit] Server validation complete, finishing transaction...")
            #endif
            
            await transaction.finish()
            
            #if DEBUG
            print("[StoreKit] Transaction finished successfully")
            #endif
            
            return CreditPurchaseResult(
                status: .success,
                debugInfo: "Step: SUCCESS. Transaction ID: \(transaction.originalID)"
            )
            
        case .pending:
            #if DEBUG
            print("[StoreKit] Purchase result: PENDING")
            #endif
            return CreditPurchaseResult(
                status: .pending,
                message: "Your purchase is pending approval from Apple.",
                debugInfo: "Step: PENDING from StoreKit"
            )
            
        case .userCancelled:
            #if DEBUG
            print("[StoreKit] Purchase result: USER CANCELLED")
            #endif
            return CreditPurchaseResult(
                status: .cancelled,
                message: nil,
                debugInfo: "Step: USER_CANCELLED from StoreKit"
            )
            
        @unknown default:
            #if DEBUG
            print("[StoreKit] Purchase result: UNKNOWN DEFAULT CASE")
            #endif
            throw CreditsStoreError.validationFailed("Unknown StoreKit result (DEBUG)")
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
        #if DEBUG
        print("[StoreKit] validateTransaction starting...")
        #endif
        
        guard let accessToken = client.auth.currentSession?.accessToken else {
            #if DEBUG
            print("[StoreKit] ERROR: User not authenticated")
            #endif
            throw CreditsStoreError.userNotAuthenticated
        }

        guard let url = try makeFunctionsURL(for: "validate-receipt") else {
            #if DEBUG
            print("[StoreKit] ERROR: Could not construct functions URL")
            #endif
            throw CreditsStoreError.unsupportedResponse
        }
        
        #if DEBUG
        print("[StoreKit] Calling edge function at: \(url.absoluteString)")
        #endif

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

        #if DEBUG
        print("[StoreKit] Sending request to validate-receipt...")
        #endif
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[StoreKit] ERROR: Invalid response type")
            #endif
            throw CreditsStoreError.unsupportedResponse
        }
        
        #if DEBUG
        let responseBody = String(data: data, encoding: .utf8) ?? "<unable to decode>"
        print("[StoreKit] Response received: status=\(httpResponse.statusCode), body=\(responseBody)")
        #endif

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if (200..<300).contains(httpResponse.statusCode) {
            let outcome = try decoder.decode(ValidateReceiptResponse.self, from: data)
            guard outcome.success else {
                #if DEBUG
                print("[StoreKit] ERROR: Server returned success=false, message=\(outcome.message ?? "nil")")
                #endif
                throw CreditsStoreError.validationFailed(outcome.message)
            }
            #if DEBUG
            print("[StoreKit] Server validation succeeded")
            #endif
        } else {
            let outcome = try? decoder.decode(ValidateReceiptResponse.self, from: data)
            #if DEBUG
            print("[StoreKit] ERROR: Non-2xx status code, message=\(outcome?.message ?? "nil")")
            #endif
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
