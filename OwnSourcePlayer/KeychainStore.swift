import Foundation
import Security

struct ProviderCredentials: Equatable {
    var username: String
    var password: String
}

enum KeychainStore {
    private static let service = "OwnSourcePlayer.ProviderCredentials"
    private static let parentalControlService = "OwnSourcePlayer.ParentalControl"
    private static let parentalPINAccount = "parental.pin"
    // Keep old services readable so users do not lose provider logins after a rename.
    private static let legacyServices = [
        "ClearStreamPlayer.ProviderCredentials"
    ]

    static func save(_ credentials: ProviderCredentials, for sourceId: UUID) throws {
        try save(credentials.username, account: account(for: sourceId, field: "username"))
        try save(credentials.password, account: account(for: sourceId, field: "password"))
    }

    static func credentials(for sourceId: UUID) throws -> ProviderCredentials? {
        let usernameAccount = account(for: sourceId, field: "username")
        let passwordAccount = account(for: sourceId, field: "password")

        if let credentials = try credentials(
            usernameAccount: usernameAccount,
            passwordAccount: passwordAccount,
            service: service
        ) {
            return credentials
        }

        for legacyService in legacyServices {
            if let credentials = try credentials(
                usernameAccount: usernameAccount,
                passwordAccount: passwordAccount,
                service: legacyService
            ) {
                // Copy legacy credentials into the current service on first successful read.
                try save(credentials, for: sourceId)
                return credentials
            }
        }

        return nil
    }

    static func deleteCredentials(for sourceId: UUID) {
        delete(account: account(for: sourceId, field: "username"))
        delete(account: account(for: sourceId, field: "password"))
        for legacyService in legacyServices {
            delete(account: account(for: sourceId, field: "username"), service: legacyService)
            delete(account: account(for: sourceId, field: "password"), service: legacyService)
        }
    }

    static func saveParentalPIN(_ pin: String) throws {
        try save(pin, account: parentalPINAccount, service: parentalControlService)
    }

    static func parentalPIN() throws -> String? {
        try read(account: parentalPINAccount, service: parentalControlService)
    }

    static func deleteParentalPIN() {
        delete(account: parentalPINAccount, service: parentalControlService)
    }

    private static func save(_ value: String, account: String, service: String = service) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw keychainError(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(addStatus)
        }
    }

    private static func credentials(
        usernameAccount: String,
        passwordAccount: String,
        service: String
    ) throws -> ProviderCredentials? {
        guard let username = try read(account: usernameAccount, service: service),
              let password = try read(account: passwordAccount, service: service) else {
            return nil
        }
        return ProviderCredentials(username: username, password: password)
    }

    private static func read(account: String, service: String = service) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }

        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func account(for sourceId: UUID, field: String) -> String {
        "\(sourceId.uuidString).\(field)"
    }

    private static func keychainError(_ status: OSStatus) -> AppError {
        AppError.importFailed("Keychain operation failed with status \(status).")
    }
}
