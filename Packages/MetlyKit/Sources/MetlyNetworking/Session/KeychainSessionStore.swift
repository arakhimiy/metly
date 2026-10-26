import Foundation
import Security
import Synchronization

/// Stores the `AuthSession` as one generic-password Keychain item (JSON).
///
/// Accessibility is `AfterFirstUnlockThisDeviceOnly`: background sync (BGTask) can read the
/// tokens after the first unlock, and they never migrate to another device via backups.
public final class KeychainSessionStore: SessionStore {
    public enum KeychainError: Error, Equatable, Sendable {
        case status(OSStatus)
        case encoding
    }

    private let service: String
    private let account: String
    private let accessGroup: String?
    /// Avoids a Keychain round trip on every request. `.some(nil)` = known empty.
    private let cache = Mutex<AuthSession??>(nil)

    public init(service: String = "app.tanishly.ios.session", account: String = "default", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func load() -> AuthSession? {
        if let cached = cache.withLock({ $0 }) { return cached }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let session: AuthSession? = if status == errSecSuccess, let data = result as? Data {
            try? MetlyJSON.makeDecoder().decode(AuthSession.self, from: data)
        } else {
            nil
        }
        // Don't cache "empty" when the Keychain is locked (pre-first-unlock) — retry next time.
        if status == errSecSuccess || status == errSecItemNotFound {
            cache.withLock { $0 = .some(session) }
        }
        return session
    }

    public func save(_ session: AuthSession) throws {
        guard let data = try? MetlyJSON.makeEncoder().encode(session) else { throw KeychainError.encoding }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { $1 }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        cache.withLock { $0 = .some(session) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        cache.withLock { $0 = .some(nil) }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
