//
//  LocationOrderStore.swift
//  SpoolKid
//
//  Purpose: Persists one `LocationOrder` per backend. Holds no rules — every
//  decision about what an order means lives in `LocationOrder` itself.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import Foundation
import os.log

@MainActor
final class LocationOrderStore: ObservableObject {
    @Published private(set) var order: LocationOrder

    private let backendKind: BackendKind
    private let defaults: UserDefaults

    init(backendKind: BackendKind, defaults: UserDefaults = .standard) {
        self.backendKind = backendKind
        self.defaults = defaults
        self.order = LocationOrderStore.load(backendKind: backendKind, defaults: defaults)
    }

    func move(_ name: String, to index: Int, within visible: [String]) {
        var next = order
        next.move(name, to: index, within: visible)
        commit(next)
    }

    func rename(from currentName: String, to newName: String) {
        var next = order
        next.rename(from: currentName, to: newName)
        commit(next)
    }

    /// Called on read. A shelf deleted in the backend's own web UI drops out of
    /// the arrangement without a migration, and an unchanged order writes
    /// nothing.
    func prune(keeping names: [String]) {
        var next = order
        next.prune(keeping: names)
        commit(next)
    }

    // MARK: - Storage

    private func commit(_ next: LocationOrder) {
        guard next != order else { return }
        order = next

        var all = LocationOrderStore.decodeAll(defaults: defaults)
        all[backendKind.rawValue] = next.keys
        do {
            defaults.set(try JSONEncoder().encode(all), forKey: AppConfig.locationManualOrderKey)
        } catch {
            logger.error("Location order save failed: \(error.localizedDescription)")
        }
    }

    private static func load(backendKind: BackendKind, defaults: UserDefaults) -> LocationOrder {
        LocationOrder(keys: decodeAll(defaults: defaults)[backendKind.rawValue] ?? [])
    }

    /// Unreadable stored data is treated as no arrangement rather than as an
    /// error: the arrangement is a preference, and losing it must never stop
    /// the screen from rendering.
    private static func decodeAll(defaults: UserDefaults) -> [String: [String]] {
        guard let data = defaults.data(forKey: AppConfig.locationManualOrderKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }
}

private let logger = Logger(subsystem: "com.spoolkid", category: "LocationOrderStore")
