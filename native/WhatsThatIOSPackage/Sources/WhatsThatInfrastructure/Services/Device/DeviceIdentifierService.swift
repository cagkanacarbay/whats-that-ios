#if USE_REMOTE_DEPS && canImport(Security)
import Foundation
import Security
import OSLog

/// A service that generates and persists a unique device identifier in the iOS Keychain.
/// This ID survives app deletion and reinstall, allowing us to track devices that have
/// already received free credits.
public protocol DeviceIdentifierServicing: Sendable {
    /// Returns the device ID, creating one if it doesn't exist
    func getOrCreateDeviceId() -> String
    
    /// Clears the device ID (for testing purposes only)
    func clearDeviceId()
}

public final class DeviceIdentifierService: DeviceIdentifierServicing, @unchecked Sendable {
    private let logger = Logger(subsystem: "WhatsThatIOS", category: "DeviceIdentifier")
    private let keychainKey = "com.whatsthat.device_id"
    private let serviceName = "com.whatsthat.WhatsThatIOS"
    
    public init() {}
    
    public func getOrCreateDeviceId() -> String {
        // Try to read existing ID from Keychain
        if let existingId = readFromKeychain() {
            logger.debug("Retrieved existing device ID from Keychain")
            return existingId
        }
        
        // Generate new UUID and store it
        let newId = UUID().uuidString
        if saveToKeychain(newId) {
            logger.info("Generated and stored new device ID in Keychain")
        } else {
            logger.error("Failed to store device ID in Keychain, using ephemeral ID")
        }
        return newId
    }
    
    public func clearDeviceId() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.info("Cleared device ID from Keychain")
        } else {
            logger.error("Failed to clear device ID from Keychain: \(status)")
        }
    }
    
    // MARK: - Private
    
    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let deviceId = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return deviceId
    }
    
    private func saveToKeychain(_ deviceId: String) -> Bool {
        guard let data = deviceId.data(using: .utf8) else {
            return false
        }
        
        // First try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item with accessibility that persists after backup restore
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            // This ensures the item is available after first unlock and persists across backups
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
#endif
