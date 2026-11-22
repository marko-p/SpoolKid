//
//  KeychainStoreTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
import Security
@testable import SpoolKid

/// `.serialized` because two of these tests share ONE mutable store — the
/// simulator's real Keychain, under SpoolKid's three FIXED account names.
/// Swift Testing runs a suite in parallel by default, so
/// `deletingSpoolKidSecretsClearsEveryStoredSecret` (which writes all three,
/// then deletes them) and `aForeignKeychainItemSurvivesAReset` (which deletes
/// them again mid-flight) raced, and the first failed intermittently.
///
/// `uniqueAccount()` isolates every test that can be isolated. These two
/// cannot be: what they assert IS the behaviour of the real account names.
@Suite(.serialized)
struct KeychainStoreTests {
    private func uniqueAccount() -> String {
        "test.\(UUID().uuidString)"
    }

    @Test func savesAndReadsBack() {
        let account = uniqueAccount()
        defer { KeychainStore.delete(account: account) }

        #expect(KeychainStore.save("uak.1.secret", account: account))
        #expect(KeychainStore.read(account: account) == "uak.1.secret")
    }

    @Test func readsNilForUnknownAccount() {
        #expect(KeychainStore.read(account: uniqueAccount()) == nil)
    }

    @Test func saveOverwritesExistingValue() {
        let account = uniqueAccount()
        defer { KeychainStore.delete(account: account) }

        #expect(KeychainStore.save("first", account: account))
        #expect(KeychainStore.save("second", account: account))
        #expect(KeychainStore.read(account: account) == "second")
    }

    @Test func deleteRemovesTheValue() {
        let account = uniqueAccount()

        #expect(KeychainStore.save("value", account: account))
        KeychainStore.delete(account: account)

        #expect(KeychainStore.read(account: account) == nil)
    }

    @Test func deleteIsIdempotent() {
        let account = uniqueAccount()

        KeychainStore.delete(account: account)
        KeychainStore.delete(account: account)

        #expect(KeychainStore.read(account: account) == nil)
    }

    @Test func savingEmptyStringDeletesInstead() {
        let account = uniqueAccount()
        defer { KeychainStore.delete(account: account) }

        #expect(KeychainStore.save("value", account: account))
        #expect(KeychainStore.save("", account: account))
        #expect(KeychainStore.read(account: account) == nil)
    }

    @Test func deletingOneAccountLeavesTheOtherIntact() {
        let accountA = uniqueAccount()
        let accountB = uniqueAccount()
        defer {
            KeychainStore.delete(account: accountA)
            KeychainStore.delete(account: accountB)
        }

        #expect(KeychainStore.save("a-value", account: accountA))
        #expect(KeychainStore.save("b-value", account: accountB))

        KeychainStore.delete(account: accountA)

        #expect(KeychainStore.read(account: accountA) == nil)
        #expect(KeychainStore.read(account: accountB) == "b-value")
    }

    @Test func savingOneAccountLeavesTheOtherIntact() {
        let accountA = uniqueAccount()
        let accountB = uniqueAccount()
        defer {
            KeychainStore.delete(account: accountA)
            KeychainStore.delete(account: accountB)
        }

        #expect(KeychainStore.save("a-value", account: accountA))
        #expect(KeychainStore.save("b-value", account: accountB))
        #expect(KeychainStore.save("a-value-updated", account: accountA))

        #expect(KeychainStore.read(account: accountA) == "a-value-updated")
        #expect(KeychainStore.read(account: accountB) == "b-value")
    }

    // MARK: - migratingRead (016 / F3.2)

    private func uniqueDefaultsKey() -> String {
        "test_legacy_\(UUID().uuidString)"
    }

    @Test func migratesALegacyUserDefaultsValueIntoTheKeychain() {
        let account = uniqueAccount()
        let legacyKey = uniqueDefaultsKey()
        UserDefaults.standard.set("hunter2", forKey: legacyKey)
        defer { KeychainStore.delete(account: account); UserDefaults.standard.removeObject(forKey: legacyKey) }

        let value = KeychainStore.migratingRead(account: account, legacyDefaultsKey: legacyKey)

        #expect(value == "hunter2")
        #expect(KeychainStore.read(account: account) == "hunter2")
        // …and the plaintext copy is gone, which is the entire point.
        #expect(UserDefaults.standard.string(forKey: legacyKey) == nil)
    }

    /// The Keychain always wins. A stale `UserDefaults` copy — left by an
    /// interrupted migration, or by an older build — must never resurrect an
    /// old password over the current one.
    @Test func anExistingKeychainValueIsNeverOverwrittenByALegacyOne() {
        let account = uniqueAccount()
        let legacyKey = uniqueDefaultsKey()
        KeychainStore.save("current", account: account)
        UserDefaults.standard.set("stale", forKey: legacyKey)
        defer { KeychainStore.delete(account: account); UserDefaults.standard.removeObject(forKey: legacyKey) }

        #expect(KeychainStore.migratingRead(account: account, legacyDefaultsKey: legacyKey) == "current")
        #expect(KeychainStore.read(account: account) == "current")
    }

    @Test func nothingToMigrateReadsNil() {
        let account = uniqueAccount()

        #expect(KeychainStore.migratingRead(account: account, legacyDefaultsKey: uniqueDefaultsKey()) == nil)
    }

    /// An empty legacy value is "no credential", not a credential of "".
    @Test func anEmptyLegacyValueIsNotMigrated() {
        let account = uniqueAccount()
        let legacyKey = uniqueDefaultsKey()
        UserDefaults.standard.set("", forKey: legacyKey)
        defer { UserDefaults.standard.removeObject(forKey: legacyKey) }

        #expect(KeychainStore.migratingRead(account: account, legacyDefaultsKey: legacyKey) == nil)
        #expect(KeychainStore.read(account: account) == nil)
    }

    @Test func migrationIsIdempotent() {
        let account = uniqueAccount()
        let legacyKey = uniqueDefaultsKey()
        UserDefaults.standard.set("hunter2", forKey: legacyKey)
        defer { KeychainStore.delete(account: account); UserDefaults.standard.removeObject(forKey: legacyKey) }

        _ = KeychainStore.migratingRead(account: account, legacyDefaultsKey: legacyKey)

        #expect(KeychainStore.migratingRead(account: account, legacyDefaultsKey: legacyKey) == "hunter2")
    }

    // MARK: - deleteSpoolKidSecrets (Reset All Data)

    /// "Reset All Data" clears the `UserDefaults` persistent domain, which the
    /// Keychain is not part of — so FilaMan's API key outlived a reset that
    /// claims to clear everything, and Spoolman's secrets would have joined it.
    @Test func deletingSpoolKidSecretsClearsEveryStoredSecret() {
        for account in KeychainStore.spoolKidAccounts {
            KeychainStore.save("secret-\(account)", account: account)
        }

        KeychainStore.deleteSpoolKidSecrets()

        for account in KeychainStore.spoolKidAccounts {
            #expect(KeychainStore.read(account: account) == nil, "\(account) survived the reset")
        }
    }

    /// Every account the app stores must be in `spoolKidAccounts`, or a reset
    /// silently misses it.
    @Test func spoolKidAccountsCoversEveryNamedAccount() {
        #expect(KeychainStore.spoolKidAccounts.contains(KeychainStore.filaManAPIKeyAccount))
        #expect(KeychainStore.spoolKidAccounts.contains(KeychainStore.spoolmanPasswordAccount))
        #expect(KeychainStore.spoolKidAccounts.contains(KeychainStore.spoolmanTokenAccount))
        #expect(Set(KeychainStore.spoolKidAccounts).count == KeychainStore.spoolKidAccounts.count)
    }

    /// The safety property behind the rename: a reset must touch SpoolKid's
    /// own three accounts and NOTHING else in the Keychain.
    ///
    /// Writes a generic-password item under a DIFFERENT service — standing in
    /// for another app's credential, or one of the user's own — using
    /// `SecItemAdd` directly, because `KeychainStore` cannot produce one.
    /// If `deleteSpoolKidSecrets` ever grew into a wildcard delete (a query
    /// with no `kSecAttrAccount`, or none with `kSecAttrService`), this fails.
    @Test func aForeignKeychainItemSurvivesAReset() {
        let foreignService = "com.example.NotSpoolKid.\(UUID().uuidString)"
        let foreignAccount = "someone_elses_password"
        let secret = Data("do-not-touch".utf8)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: foreignService,
            kSecAttrAccount as String: foreignAccount,
            kSecValueData as String: secret
        ]
        SecItemDelete(add as CFDictionary)
        #expect(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: foreignService,
                kSecAttrAccount as String: foreignAccount
            ] as CFDictionary)
        }

        for account in KeychainStore.spoolKidAccounts {
            KeychainStore.save("secret-\(account)", account: account)
        }

        KeychainStore.deleteSpoolKidSecrets()

        var found: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: foreignService,
            kSecAttrAccount as String: foreignAccount,
            kSecReturnData as String: true
        ] as CFDictionary, &found)

        #expect(status == errSecSuccess, "a foreign Keychain item was destroyed by the reset")
        #expect(found as? Data == secret)
    }
}
