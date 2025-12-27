import Foundation
import WhatsThatShared

public actor CreditBalanceStore: Sendable {
    private enum Keys {
        static let balance = "credits.balance"
        static let lastFetchedAt = "credits.lastFetchedAt"
    }

    private let repository: DiscoveryCreditsRepository
    private let defaults: UserDefaults
    private let ttl: TimeInterval

    private var cachedBalance: Int?
    private var lastFetchedAt: Date?
    private var inFlightTask: Task<Int, Error>?
    private var hasLoadedFromDefaults = false

    public init(
        repository: DiscoveryCreditsRepository,
        suiteName: String? = nil,
        ttl: TimeInterval = 90
    ) {
        self.repository = repository
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.ttl = ttl
    }

    public func getCached() -> Int? {
        ensureLoadedFromDefaultsIfNeeded()
        return cachedBalance
    }

    @discardableResult
    public func refreshIfStale() async throws -> Int {
        ensureLoadedFromDefaultsIfNeeded()
        if let last = lastFetchedAt, let balance = cachedBalance {
            if Date().timeIntervalSince(last) < ttl {
                return balance
            }
        }
        return try await refresh(force: true)
    }

    @discardableResult
    public func refresh(force: Bool = false) async throws -> Int {
        ensureLoadedFromDefaultsIfNeeded()

        if let task = inFlightTask {
            return try await task.value
        }

        let task = Task<Int, Error> {
            try await repository.fetchCreditBalance()
        }

        inFlightTask = task
        defer { inFlightTask = nil }
        let value = try await task.value
        _ = set(value)
        return value
    }

    @discardableResult
    public func set(_ newValue: Int?) -> Int? {
        ensureLoadedFromDefaultsIfNeeded()
        cachedBalance = newValue
        lastFetchedAt = newValue == nil ? nil : Date()
        persistToDefaults()
        return cachedBalance
    }

    @discardableResult
    public func adjust(by delta: Int) -> Int? {
        ensureLoadedFromDefaultsIfNeeded()
        let base = cachedBalance ?? 0
        let updated = max(0, base + delta)
        cachedBalance = updated
        lastFetchedAt = Date()
        persistToDefaults()
        return cachedBalance
    }

    public func markStale() {
        ensureLoadedFromDefaultsIfNeeded()
        lastFetchedAt = Date(timeIntervalSince1970: 0)
        persistToDefaults()
    }

    private func ensureLoadedFromDefaultsIfNeeded() {
        guard !hasLoadedFromDefaults else { return }
        hasLoadedFromDefaults = true
        if let number = defaults.object(forKey: Keys.balance) as? NSNumber {
            cachedBalance = number.intValue
        } else if defaults.object(forKey: Keys.balance) != nil {
            cachedBalance = defaults.integer(forKey: Keys.balance)
        }

        if let date = defaults.object(forKey: Keys.lastFetchedAt) as? Date {
            lastFetchedAt = date
        }
    }

    private func persistToDefaults() {
        if let balance = cachedBalance {
            defaults.set(balance, forKey: Keys.balance)
        } else {
            defaults.removeObject(forKey: Keys.balance)
        }

        if let stamp = lastFetchedAt {
            defaults.set(stamp, forKey: Keys.lastFetchedAt)
        } else {
            defaults.removeObject(forKey: Keys.lastFetchedAt)
        }
    }
}

// MARK: - UserDataClearable

extension CreditBalanceStore: UserDataClearable {
    public func clearUserData() async {
        _ = set(nil)
    }
}
