import Foundation
import WhatsThatShared

public protocol SupabaseTransport: Sendable {
    func get(path: String) async throws -> Data
}

public struct StubSupabaseTransport: SupabaseTransport {
    public init(configuration _: AppConfiguration = .preview) {}

    public func get(path _: String) async throws -> Data {
        Data()
    }
}
