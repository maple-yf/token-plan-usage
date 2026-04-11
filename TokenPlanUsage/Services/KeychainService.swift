import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.tokenplan.usage"

    func save(_ config: ProviderConfig) throws {
        guard let data = try JSONEncoder().encode(config) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: config.id,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.additionFailed(status)
        }
    }

    func load(providerId: String) -> ProviderConfig? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }

    func delete(providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: providerId
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deletionFailed(status)
        }
    }

    enum KeychainError: LocalizedError {
        case encodingFailed
        case additionFailed(OSStatus)
        case deletionFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "编码失败"
            case .additionFailed(let status): return "添加 Keychain 项失败: \(status)"
            case .deletionFailed(let status): return "删除 Keychain 项失败: \(status)"
            }
        }
    }
}
