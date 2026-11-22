//
//  LocationRegistry.swift
//  SpoolKid
//
//  Purpose: Device-local store of locations the active backend cannot hold by
//  itself, and of which physical tags carry them. Owned by `SpoolDataStore`,
//  which keeps it in step with every rename and delete.
//
//  NOT a shadow copy of the backend: an entry is *pending* until a spool is
//  assigned to it, at which point the ordinary spool save writes the name to
//  the server and the backend takes over as the source of truth.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftData
import os.log

@MainActor
final class LocationRegistry: ObservableObject {
    @Published private(set) var records: [LocationRecord] = []
    /// Why the last save failed; cleared by the next one that succeeds. Read
    /// it right after a write reports a failure.
    private(set) var errorMessage: String?

    private let context: ModelContext
    private let backendKind: BackendKind

    init(context: ModelContext, backendKind: BackendKind) {
        self.context = context
        self.backendKind = backendKind
        reload()
    }

    // MARK: - Reads

    func reload() {
        records = entries()
            .map { LocationRecord(uuid: $0.uuid, name: $0.name, tagUIDs: $0.tagUIDs) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func record(named name: String) -> LocationRecord? {
        let key = LocationName.normalizedKey(name)
        return records.first { LocationName.normalizedKey($0.name) == key }
    }

    func record(forTagUID uid: String) -> LocationRecord? {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return nil }
        return records.first { $0.tagUIDs.contains(normalized) }
    }

    // MARK: - Writes

    /// Idempotent on the normalized name — a second add of the same shelf
    /// returns the existing record rather than forking its uuid, which is what
    /// keeps a tag pointing at one location. `nil` for a blank name or a
    /// failed save.
    @discardableResult
    func add(name: String) -> LocationRecord? {
        let trimmed = LocationName.trimmed(name)
        guard !trimmed.isEmpty else { return nil }
        if let existing = record(named: trimmed) { return existing }

        context.insert(LocationRegistryEntry(name: trimmed, backendKind: backendKind.rawValue))
        guard persist() else { return nil }
        return record(named: trimmed)
    }

    /// Creates an entry under a uuid that already exists in the world — a tag
    /// written on another device, or before a reinstall. Minting a fresh uuid
    /// there (what `add(name:)` does) would leave that tag permanently
    /// unrecognised, however many times it is added.
    ///
    /// Collisions never fork: one location is one entry, so an entry already
    /// holding this NAME — or already holding this uuid under another name —
    /// wins, and the tag joins it instead. `record(named:)` must have exactly
    /// one answer, and the existing entry's uuid may already be on tags of its
    /// own, while the incoming tag is recognised from then on by its UID.
    ///
    /// `nil` for a blank name or a failed save.
    @discardableResult
    func adopt(uuid: UUID, name: String, tagUID: String? = nil) -> LocationRecord? {
        let trimmed = LocationName.trimmed(name)
        guard !trimmed.isEmpty else { return nil }

        if let existing = entry(named: trimmed) ?? entries().first(where: { $0.uuid == uuid }) {
            if attach(tagUID, to: existing), !persist() { return nil }
            return record(named: existing.name)
        }

        let entry = LocationRegistryEntry(uuid: uuid, name: trimmed, backendKind: backendKind.rawValue)
        attach(tagUID, to: entry)
        context.insert(entry)
        guard persist() else { return nil }
        return record(named: trimmed)
    }

    /// Renames in place, keeping the uuid — tags written before the rename go
    /// on resolving. `false` when there was nothing to rename, the new name
    /// is blank, or the save failed, so a caller whose whole rename IS this
    /// call can report the truth rather than a success it did not have.
    @discardableResult
    func rename(from currentName: String, to newName: String) -> Bool {
        let trimmed = LocationName.trimmed(newName)
        guard !trimmed.isEmpty, let entry = entry(named: currentName) else { return false }
        entry.name = trimmed
        return persist()
    }

    /// `false` only for a failed save: a name with no entry has nothing to
    /// remove, which is how most locations a backend holds stand.
    @discardableResult
    func remove(named name: String) -> Bool {
        guard let entry = entry(named: name) else { return true }
        context.delete(entry)
        return persist()
    }

    /// `false` when no entry has `uuid`, or the save failed.
    @discardableResult
    func attachTag(uid: String, to uuid: UUID) -> Bool {
        guard let entry = entries().first(where: { $0.uuid == uuid }) else { return false }
        guard attach(uid, to: entry) else { return true }
        return persist()
    }

    /// The one place a UID joins an entry: normalized through
    /// `SpoolMappingService`, idempotent, and unsaved — the caller persists.
    /// `false` means nothing changed.
    ///
    /// **Single-owner across locations.** The UID is taken off every other
    /// entry first, so one tag labels one shelf. Without this a tag re-written
    /// for a second location stayed on the first as well, and `record(forTagUID:)`
    /// — a `first(where:)` — would answer with whichever entry happened to sort
    /// earlier. FilaMan's own model has the same rule and clears duplicates the
    /// same way; `locations.identifier` is where that surfaces on the server.
    @discardableResult
    private func attach(_ uid: String?, to entry: LocationRegistryEntry) -> Bool {
        guard let uid else { return false }
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return false }

        var changed = false
        for other in entries() where other.uuid != entry.uuid && other.tagUIDs.contains(normalized) {
            other.tagUIDs.removeAll { $0 == normalized }
            changed = true
        }

        guard !entry.tagUIDs.contains(normalized) else { return changed }
        entry.tagUIDs.append(normalized)
        return true
    }

    /// Drops a UID from whichever record holds it. The read-side self-heal for
    /// a tag that has been rewritten as a spool tag. `false` only for a failed
    /// save, which leaves the UID where it was.
    @discardableResult
    func detachTag(uid: String) -> Bool {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return true }
        var changed = false
        for entry in entries() where entry.tagUIDs.contains(normalized) {
            entry.tagUIDs.removeAll { $0 == normalized }
            changed = true
        }
        return changed ? persist() : true
    }

    // MARK: - Storage

    /// Fetches all rows and filters in Swift rather than in a `#Predicate`:
    /// the row count is one per location, and it keeps UUID and array
    /// comparisons out of the predicate language.
    private func entries() -> [LocationRegistryEntry] {
        let rows = (try? context.fetch(FetchDescriptor<LocationRegistryEntry>())) ?? []
        return rows.filter { $0.backendKind == backendKind.rawValue }
    }

    private func entry(named name: String) -> LocationRegistryEntry? {
        let key = LocationName.normalizedKey(name)
        return entries().first { LocationName.normalizedKey($0.name) == key }
    }

    /// Every write's save. A failed one is rolled back and reported: the
    /// context is the app's main one, shared with `LocalRepository`,
    /// `EmptySpoolLibrary` and `MigrationService`, so a change left pending
    /// here would be committed by whichever of them saved next, long after
    /// this write had reported.
    private func persist() -> Bool {
        defer { reload() }
        do {
            try context.save()
            errorMessage = nil
            return true
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
            logger.error("Location registry save failed: \(error.localizedDescription)")
            return false
        }
    }
}

private let logger = Logger(subsystem: "com.spoolkid", category: "LocationRegistry")
