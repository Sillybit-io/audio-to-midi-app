import Foundation
import Security

struct KeychainStore: Sendable {
    var service = "io.sillybit.sillymiditools.huggingface"
    private let account = "token"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
