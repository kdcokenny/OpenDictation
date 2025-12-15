import Foundation
import Security
import os.log

/// A simple service for securely storing and retrieving sensitive data in the macOS Keychain.
/// Used primarily for API key storage.
final class KeychainService: @unchecked Sendable {
  
  static let shared = KeychainService()
  
  private let service = "com.opendictation"
  private let logger = Logger.app(category: "Keychain")
  
  private init() {}
  
  // MARK: - Public API
  
  /// Saves a string value to the Keychain.
  /// - Parameters:
  ///   - value: The string value to store
  ///   - key: The key to associate with this value
  /// - Returns: true if successful, false otherwise
  @discardableResult
  func save(_ value: String, for key: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    
    // Delete any existing item first
    delete(key)
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
    ]
    
    let status = SecItemAdd(query as CFDictionary, nil)
    
    if status != errSecSuccess {
      logger.error("Failed to save key '\(key)': \(status)")
    }
    
    return status == errSecSuccess
  }
  
  /// Retrieves a string value from the Keychain.
  /// - Parameter key: The key to look up
  /// - Returns: The stored string value, or nil if not found
  func load(_ key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess,
          let data = result as? Data,
          let string = String(data: data, encoding: .utf8) else {
      return nil
    }
    
    return string
  }
  
  /// Deletes a value from the Keychain.
  /// - Parameter key: The key to delete
  /// - Returns: true if successful or item didn't exist, false on error
  @discardableResult
  func delete(_ key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}

// MARK: - Keychain Keys

extension KeychainService {
  /// Well-known keys for Keychain storage
  enum Key {
    static let apiKey = "openai_api_key"
  }
}
