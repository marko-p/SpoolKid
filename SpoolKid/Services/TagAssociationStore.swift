//
//  TagAssociationStore.swift
//  SpoolKid
//
//  Purpose: A permanent, thread-safe on-device ledger of tag UID → spool id,
//  recorded as tags are written/read, KEYED BY BACKEND (kind + server URL, or
//  the Library): spool ids are only meaningful on the backend that issued them,
//  and Library and server ids both start at small integers. Feeds Home-tab
//  tag-coverage stats and a ScanResolutionService fallback. Safe to mutate
//  from NFCManager's non-@MainActor callbacks (serial queue guards the
//  dictionary + persistence).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

final class TagAssociationStore: @unchecked Sendable {
    nonisolated static let shared = TagAssociationStore()

    private let userDefaults: UserDefaults
    private let legacyKey: String
    private let scopedKey: String
    private let queue = DispatchQueue(label: "com.spoolkid.tagledger")
    /// Backend scope → (normalized UID → spool id).
    private var maps: [String: [String: Int]]
    private var backend: BackendKind = .local

    /// `key` is the legacy global map's key: on the first `activeBackend`
    /// assignment its rows are adopted into that backend's scope and the key
    /// is removed (pre-scoping ledgers were recorded against the backend in use).
    init(
        userDefaults: UserDefaults = .standard,
        key: String = AppConfig.tagLedgerKey,
        scopedKey: String = AppConfig.tagLedgerScopedKey
    ) {
        self.userDefaults = userDefaults
        self.legacyKey = key
        self.scopedKey = scopedKey
        if let data = userDefaults.data(forKey: scopedKey),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            self.maps = decoded
        } else {
            self.maps = [:]
        }
    }

    /// The backend whose rows `record`/`remove`/`snapshot` see. Set by
    /// `ContentView.init` on every (re)build; the server URL is read live from
    /// `userDefaults`, so a URL change within one kind is a new scope too.
    var activeBackend: BackendKind {
        get { queue.sync { backend } }
        set {
            queue.sync {
                backend = newValue
                adoptLegacyLocked()
            }
        }
    }

    func record(uid: String, spoolId: Int) {
        let norm = SpoolMappingService.normalizeUID(uid)
        guard !norm.isEmpty else { return }
        queue.sync {
            maps[scopeLocked(), default: [:]][norm] = spoolId
            persistLocked()
        }
    }

    func remove(uid: String) {
        let norm = SpoolMappingService.normalizeUID(uid)
        queue.sync {
            let scope = scopeLocked()
            maps[scope]?.removeValue(forKey: norm)
            if maps[scope]?.isEmpty == true { maps.removeValue(forKey: scope) }
            persistLocked()
        }
    }

    /// The active backend's rows only.
    func snapshot() -> [String: Int] {
        queue.sync { maps[scopeLocked()] ?? [:] }
    }

    /// `local` for the Library; `<kind> <server>` for a server, the server being
    /// `ServerAddress.identity(of:)`, so equivalent typings of one address share
    /// it. For an address containing "://" that is the earlier rule (trimmed,
    /// lowercased, no trailing slash) except that a trailing /api/v1 is also
    /// dropped. Rows can still change scope when a scheme-less address gains
    /// "http://" (a tag write records its spool id without contacting a server)
    /// or an address with user:pass@, now refused, loses its credentials; both
    /// heal as tags are re-scanned.
    private func scopeLocked() -> String {
        let urlKey: String
        switch backend {
        case .local: return BackendKind.local.rawValue
        case .spoolman: urlKey = AppConfig.spoolmanUrlKey
        case .filaman: urlKey = AppConfig.filamanUrlKey
        }
        return "\(backend.rawValue) \(ServerAddress.identity(of: userDefaults.string(forKey: urlKey) ?? ""))"
    }

    private func adoptLegacyLocked() {
        guard let data = userDefaults.data(forKey: legacyKey) else { return }
        if let legacy = try? JSONDecoder().decode([String: Int].self, from: data) {
            maps[scopeLocked(), default: [:]].merge(legacy) { current, _ in current }
            persistLocked()
        }
        userDefaults.removeObject(forKey: legacyKey)
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(maps) {
            userDefaults.set(data, forKey: scopedKey)
        }
    }
}
