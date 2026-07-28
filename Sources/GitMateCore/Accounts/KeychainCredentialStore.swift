import Foundation
import Security

public enum CredentialStoreError: Error, Equatable, Sendable {
    case invalidTokenData
    case unexpectedStatus(OSStatus)
}

extension CredentialStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            "无法读取钥匙串中的账户令牌。"
        case let .unexpectedStatus(status):
            "钥匙串操作失败（\(status)）。"
        }
    }
}

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    public static let service = "com.gitmate.credentials"

    public init() {}

    public func save(token: String, accountID: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery(accountID: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    public func token(accountID: String) throws -> String? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidTokenData
        }
        return token
    }

    public func deleteToken(accountID: String) throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountID
        ]
    }
}
