import Foundation
import Security
import os

/// Secrets kept in the keychain, on this device only: an API key typed in, and
/// the tokens of a ChatGPT sign-in. Never in UserDefaults, nor in backups that
/// leave the device.
enum Keychain {
  private static let service = "aube-reader"
  private static let log = Logger(subsystem: "aube-reader", category: "keychain")

  static func read(_ account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var found: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess else { return nil }
    return found as? Data
  }

  /// Keeps `data` under `account`, or forgets it if `data` is nil. What was
  /// kept before stays until the new value is in its place. False, and logged,
  /// if the keychain refused.
  @discardableResult
  static func write(_ data: Data?, _ account: String) -> Bool {
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    guard let data else {
      let status = SecItemDelete(item as CFDictionary)
      return check(status == errSecSuccess || status == errSecItemNotFound, status, "delete")
    }
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(item as CFDictionary, update as CFDictionary)
    guard status == errSecItemNotFound else { return check(status == errSecSuccess, status, "update") }
    let added = SecItemAdd(item.merging(update) { $1 } as CFDictionary, nil)
    return check(added == errSecSuccess, added, "add")
  }

  private static func check(_ ok: Bool, _ status: OSStatus, _ what: String) -> Bool {
    if !ok { log.error("Keychain \(what, privacy: .public) failed: \(status, privacy: .public)") }
    return ok
  }

  static func string(_ account: String) -> String? {
    read(account).flatMap { String(data: $0, encoding: .utf8) }
  }

  static func setString(_ value: String?, _ account: String) {
    write(value.map { Data($0.utf8) }, account)
  }
}
