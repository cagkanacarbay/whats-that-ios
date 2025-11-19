import Foundation

public actor NativePushTokenStore {
    public static let shared = NativePushTokenStore()

    private var token: String?
    private var continuations: [CheckedContinuation<String?, Never>] = []

    public init() {}

    public func currentToken() -> String? {
        token
    }

    public func waitForToken() async -> String? {
        if let token {
            return token
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    public func updateToken(_ data: Data) {
        let tokenString = data.map { String(format: "%02x", $0) }.joined()
        token = tokenString
        resolveContinuations(with: tokenString)
    }

    public func registrationFailed() {
        resolveContinuations(with: nil)
    }

    private func resolveContinuations(with value: String?) {
        continuations.forEach { $0.resume(returning: value) }
        continuations.removeAll()
    }
}

