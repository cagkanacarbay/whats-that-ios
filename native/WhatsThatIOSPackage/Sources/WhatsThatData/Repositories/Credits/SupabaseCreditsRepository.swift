#if USE_REMOTE_DEPS && canImport(Supabase)
import Foundation
import Supabase
import WhatsThatDomain

public final class SupabaseCreditsRepository: DiscoveryCreditsRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func fetchCreditBalance() async throws -> Int {
        guard let userId = client.auth.currentUser?.id.uuidString else {
            throw DiscoveryFeedError.unauthorized
        }

        let response: PostgrestResponse<CreditBalanceResponse> = try await client
            .from("user_credits")
            .select("credit_balance")
            .eq("user_id", value: userId)
            .single()
            .execute()

        return response.value.credit_balance
    }
}

private struct CreditBalanceResponse: Decodable {
    let credit_balance: Int
}
#endif
