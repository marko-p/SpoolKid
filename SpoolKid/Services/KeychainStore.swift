//
//  KeychainStore.swift
//  SpoolKid
//
//  Purpose: Minimal Keychain wrapper for credentials that must not live in
//  UserDefaults. Used for the FilaMan API key, which is unscoped and never
//  expires — possession is full account access.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Security
import os.log

/// Generic-password Keychain access, keyed by an account string. Deliberately
/// tiny: save / read / delete, no caching, no error surface beyond a Bool —
/// callers treat a failed save as "credential not stored" and re-prompt.
nonisolated enum KeychainStore {
    /// Account name for the FilaMan user API key. This is stored data — do not
    /// change the value.
    static let filaManAPIKeyAccount = "filaman_api_key"
    /// Spoolman's basic-auth password. Stored data — do not change the value.
    static let spoolmanPasswordAccount = "spoolman_auth_password"
    /// Spoolman's bearer token. Stored data — do not change the value.
    static let spoolmanTokenAccount = "spoolman_auth_token"
    /// Spoolman's OpenID Connect tokens, as one JSON value (`OIDCTokenSet`).
    /// Stored data — do not change the value.
    static let spoolmanOIDCTokensAccount = "spoolman_oidc_tokens"
    /// `PrinterCredentials` as JSON: the Moonraker tokens or API key.
    static let printerCredentialsAccount = "printer_credentials"

    /// The accounts THIS APP stores, for "Reset All Data" — which clears the
    /// `UserDefaults` persistent domain and, until 2026-08-25, left the
    /// Keychain untouched. FilaMan's API key therefore survived a reset that
    /// claims to clear everything; moving Spoolman's secrets here would have
    /// added two more.
    static let spoolKidAccounts = [
        filaManAPIKeyAccount, spoolmanPasswordAccount, spoolmanTokenAccount, spoolmanOIDCTokensAccount,
        printerCredentialsAccount
    ]

    /// Reads a secret, moving it out of `UserDefaults` the first time it is
    /// asked for after an upgrade (016 / F3.2).
    ///
    /// The Keychain always wins: once a value lives there, the legacy key is
    /// never consulted again, so a stale `UserDefaults` copy left by an
    /// interrupted migration cannot resurrect an old password over a new one.
    /// The legacy entry is removed as soon as it has been copied.
    static func migratingRead(account: String, legacyDefaultsKey: String) -> String? {
        if let stored = read(account: account) { return stored }

        let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey) ?? ""
        guard !legacy.isEmpty else { return nil }

        guard save(legacy, account: account) else {
            // Keep the legacy copy: losing the user's password to a failed
            // Keychain write would be worse than leaving it where it was.
            logger.error("Could not migrate \(legacyDefaultsKey, privacy: .public) to the Keychain; leaving it in UserDefaults.")
            return legacy
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return legacy
    }

    /// Removes the secrets SpoolKid itself stores. Used by "Reset All
    /// Data".
    ///
    /// **Scope, because the previous name (`deleteAll`) invited exactly the
    /// wrong reading:** this deletes named accounts one at a time, and every
    /// `SecItemDelete` query below carries BOTH `kSecAttrService`
    /// (`com.markopraprotnik.SpoolKid`) and `kSecAttrAccount`. It cannot match
    /// another app's items, the user's passwords, or anything else in the
    /// Keychain — only the rows in `spoolKidAccounts`. A query with no account
    /// attribute would be a wildcard delete across this service; there is
    /// deliberately no such call anywhere in this file, and
    /// `KeychainStoreTests` pins that a foreign item survives this.
    static func deleteSpoolKidSecrets() {
        for account in spoolKidAccounts {
            _ = delete(account: account)
        }
    }

    private static let service = "com.markopraprotnik.SpoolKid"
    private static let logger = Logger(subsystem: "com.markopraprotnik.SpoolKid", category: "KeychainStore")

    /// Stores `value`, replacing any existing entry. An empty string deletes
    /// instead — "no credential" has exactly one representation.
    ///
    /// Replaced in place, never deleted first: a delete followed by a failed
    /// add lost the stored secret along with the new one. `false` leaves the
    /// previous value where it was.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else {
            return delete(account: account)
        }
        guard let data = value.data(using: .utf8) else { return false }

        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let stored: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemUpdate(match as CFDictionary, stored as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(match.merging(stored) { $1 } as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain save failed for account \(account, privacy: .public): \(status)")
            return false
        }
        return true
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Deletes the entry for `account`, if any. Both "deleted" and "was already
    /// absent" are success — deleting a credential that was never stored is a
    /// legitimate no-op, not a failure.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for account \(account, privacy: .public): \(status)")
            return false
        }
        return true
    }
}
