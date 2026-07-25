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
        retrievedValue: String?,
        permitsEmpty: Bool = false
    ) -> Bool {
        let submitted = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard permitsEmpty || !submitted.isEmpty else { return false }
        return submitted
            == retrievedValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CredentialCandidateSelectionPolicy: Sendable {
    public init() {}

    public func preferredValue(
        primary: String?,
        legacyCandidates: [String]
    ) -> String? {
        let normalizedPrimary = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedPrimary, !normalizedPrimary.isEmpty {
            return normalizedPrimary
        }
        return legacyCandidates.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

public enum CredentialReadiness: Equatable, Sendable {
    case ready
    case missingGroqAPIKey
}

public struct CredentialReadinessPolicy: Sendable {
    public init() {}

    public func readiness(groqAPIKey: String) -> CredentialReadiness {
        groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .missingGroqAPIKey
            : .ready
    }
}

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "dev.interviewarc.voice") {
        self.service = service
    }

    public func value(for credential: VoiceCredential) throws -> String? {
        let primary = try primaryValue(for: credential)
        let selection = CredentialCandidateSelectionPolicy()
        if let preferred = selection.preferredValue(
            primary: primary,
            legacyCandidates: []
        ) {
            return preferred
        }

        let recovered = selection.preferredValue(
            primary: primary,
            legacyCandidates: try legacyValues(for: credential)
        )
        if let recovered {
            // Older packaged builds relied on the Keychain search list rather
            // than explicitly targeting the login Keychain. Preserve that
            // existing credential by copying it into the current canonical
            // item after a successful read.
            try set(recovered, for: credential)
        }
        return recovered
    }

    private func primaryValue(for credential: VoiceCredential) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseKeychain as String] = try defaultKeychain()
        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecParam {
            // Some current macOS runtimes reject the legacy kSecUseKeychain
            // scope even though SecKeychainCopyDefault succeeds. The ordinary
            // search list still resolves the same canonical service/account
            // item and preserves the existing packaged-app credential.
            query.removeValue(forKey: kSecUseKeychain as String)
            item = nil
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    private func legacyValues(for credential: VoiceCredential) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        if let data = items as? Data {
            return String(data: data, encoding: .utf8).map { [$0] } ?? []
        }
        return (items as? [Data] ?? []).compactMap {
            String(data: $0, encoding: .utf8)
        }
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
        var updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            updateAttributes as CFDictionary
        )
        if updateStatus == errSecParam {
            lookup.removeValue(forKey: kSecUseKeychain as String)
            updateStatus = SecItemUpdate(
                lookup as CFDictionary,
                updateAttributes as CFDictionary
            )
        }
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
        var status = SecItemDelete(query as CFDictionary)
        if status == errSecParam {
            query.removeValue(forKey: kSecUseKeychain as String)
            status = SecItemDelete(query as CFDictionary)
        }
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
