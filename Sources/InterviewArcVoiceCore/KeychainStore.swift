import Foundation
import Security

public enum VoiceCredential: String, CaseIterable, Sendable {
    case interviewArcToken = "interview-arc-token"
    case groqAPIKey = "groq-api-key"

    public var label: String {
        switch self {
        case .interviewArcToken: "Interview Arc connection token"
        case .groqAPIKey: "Groq API key"
        }
    }
}

public struct CredentialSaveVerificationPolicy: Sendable {
    public init() {}

    public func isVerified(
        submittedValue: String,
        retrievedValue: String?
    ) -> Bool {
        submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            == retrievedValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "dev.interviewarc.voice") {
        self.service = service
    }

    public func value(for credential: VoiceCredential) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseKeychain as String] = try defaultKeychain()
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for credential: VoiceCredential) throws {
        let data = Data(value.utf8)
        var lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
        ]
        lookup[kSecUseKeychain as String] = try defaultKeychain()
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            updateAttributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = lookup
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecAttrLabel as String] = credential.label
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    public func remove(_ credential: VoiceCredential) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
        ]
        query[kSecUseKeychain as String] = try defaultKeychain()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func defaultKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        let status = SecKeychainCopyDefault(&keychain)
        guard status == errSecSuccess, let keychain else {
            throw KeychainError(status: status)
        }
        return keychain
    }
}

public struct KeychainError: LocalizedError, Sendable {
    public let status: OSStatus

    public var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

public struct CredentialPersistenceError: LocalizedError, Sendable {
    public let credential: VoiceCredential

    public init(credential: VoiceCredential) {
        self.credential = credential
    }

    public var errorDescription: String? {
        "Voice could not verify the saved \(credential.label) in Keychain."
    }
}
