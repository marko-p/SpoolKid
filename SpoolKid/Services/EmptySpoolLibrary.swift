//
//  EmptySpoolLibrary.swift
//  SpoolKid
//
//  Purpose: The device-local library of empty-spool weights. Created once by
//  `ContentView` and injected through the environment; deliberately NOT
//  behind `SpoolDataStore`, because it has no backend — it is the same list
//  whichever backend is active.
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

/// What a screen shows of one entry: a value copy, so a view never holds a
/// live SwiftData object across a save.
nonisolated struct EmptySpoolRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Blank when there is none.
    let manufacturer: String
    let name: String
    let weight: Double
    let photo: Data?
    let isDefault: Bool
    /// The default for its manufacturer's spools; at most one per brand.
    let isManufacturerDefault: Bool
    let createdAt: Date

    /// Manufacturer and name, the way the other list rows title themselves
    /// (`Filament.listTitle`); the name alone when there is no manufacturer.
    var listTitle: String {
        manufacturer.isEmpty ? name : "\(manufacturer) \(name)"
    }
}

@MainActor
final class EmptySpoolLibrary: ObservableObject {
    /// Default first, then manufacturer and name A–Z (`listTitle`), then oldest first.
    @Published private(set) var entries: [EmptySpoolRecord] = []

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    var defaultEntry: EmptySpoolRecord? {
        entries.first { $0.isDefault }
    }

    func prefillEntry(forManufacturer manufacturer: String?) -> EmptySpoolRecord? {
        Self.prefillEntry(forManufacturer: manufacturer, in: entries)
    }

    // MARK: - Brand resolution

    /// The entry a new spool of this brand starts with, first match wins: the
    /// one marked as the brand's default; the brand's only entry; the general
    /// default. Nil when none applies — the caller then keeps the last value
    /// saved. A nil or blank manufacturer has no brand.
    nonisolated static func prefillEntry(
        forManufacturer manufacturer: String?, in entries: [EmptySpoolRecord]
    ) -> EmptySpoolRecord? {
        let brand = brandEntries(forManufacturer: manufacturer, in: entries)
        if let marked = brand.first(where: { $0.isManufacturerDefault }) { return marked }
        if brand.count == 1 { return brand[0] }
        return entries.first { $0.isDefault }
    }

    /// The brand's entries for the picker's top section — its default first,
    /// then in `entries`' order — and the rest, in `entries`' order. `brand`
    /// is empty for a nil or blank manufacturer, or a brand with no entries.
    nonisolated static func pickerSections(
        forManufacturer manufacturer: String?, in entries: [EmptySpoolRecord]
    ) -> (brand: [EmptySpoolRecord], other: [EmptySpoolRecord]) {
        let brand = brandEntries(forManufacturer: manufacturer, in: entries)
        let brandIDs = Set(brand.map(\.id))
        let ordered = brand.filter(\.isManufacturerDefault) + brand.filter { !$0.isManufacturerDefault }
        return (ordered, entries.filter { !brandIDs.contains($0.id) })
    }

    nonisolated private static func brandEntries(
        forManufacturer manufacturer: String?, in entries: [EmptySpoolRecord]
    ) -> [EmptySpoolRecord] {
        let key = ManufacturerName.key(manufacturer ?? "")
        guard !key.isEmpty else { return [] }
        return entries.filter { ManufacturerName.key($0.manufacturer) == key }
    }

    // MARK: - Validation

    /// The one rule for what may be stored, shared by every write and by the
    /// editor's Save button: a non-blank name and a finite weight ≥ 0.
    static func isValid(name: String, weight: Double?) -> Bool {
        guard let weight, weight.isFinite, weight >= 0 else { return false }
        return !trimmed(name).isEmpty
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Writes

    /// `false` when the input is invalid, the library could not be read, or
    /// the save failed; nothing is stored then.
    ///
    /// A blank manufacturer stores `isManufacturerDefault` as `false`; a
    /// brand default clears the brand's previous one in the same save.
    func add(
        manufacturer: String = "", name: String, weight: Double, photo: Data?,
        isDefault: Bool, isManufacturerDefault: Bool = false
    ) -> Bool {
        guard Self.isValid(name: name, weight: weight), let all = rows() else { return false }
        if isDefault { clearDefault(in: all, except: nil) }
        let key = ManufacturerName.key(manufacturer)
        let holdsBrand = isManufacturerDefault && !key.isEmpty
        if holdsBrand { clearManufacturerDefault(in: all, key: key, except: nil) }
        context.insert(EmptySpoolEntry(
            manufacturer: Self.trimmed(manufacturer),
            name: Self.trimmed(name), weight: weight, photo: photo, isDefault: isDefault,
            isManufacturerDefault: holdsBrand
        ))
        return persist()
    }

    /// As `add`; a brand default follows the entry to a new manufacturer, and
    /// clearing the manufacturer drops it.
    func update(
        _ id: UUID, manufacturer: String, name: String, weight: Double, photo: Data?,
        isDefault: Bool, isManufacturerDefault: Bool
    ) -> Bool {
        guard Self.isValid(name: name, weight: weight),
              let all = rows(),
              let row = all.first(where: { $0.uuid == id }) else { return false }
        if isDefault { clearDefault(in: all, except: id) }
        let key = ManufacturerName.key(manufacturer)
        let holdsBrand = isManufacturerDefault && !key.isEmpty
        if holdsBrand { clearManufacturerDefault(in: all, key: key, except: id) }
        row.manufacturer = Self.trimmed(manufacturer)
        row.name = Self.trimmed(name)
        row.weight = weight
        row.photo = photo
        row.isDefault = isDefault
        row.isManufacturerDefault = holdsBrand
        return persist()
    }

    /// `false` for an id the library does not hold, or when it could not be
    /// read.
    func delete(_ id: UUID) -> Bool {
        guard let row = rows()?.first(where: { $0.uuid == id }) else { return false }
        context.delete(row)
        return persist()
    }

    /// Marks one entry as the default and clears every other; `nil` clears
    /// the default. `false` for an id the library does not hold, or when it
    /// could not be read.
    func setDefault(_ id: UUID?) -> Bool {
        guard let all = rows() else { return false }
        if let id, !all.contains(where: { $0.uuid == id }) { return false }
        for row in all {
            row.isDefault = row.uuid == id
        }
        return persist()
    }

    /// Marks one entry as its manufacturer's default, clearing that brand's
    /// previous one, or unmarks it. `false` for an id the library does not
    /// hold, for marking an entry with no manufacturer, or when the library
    /// could not be read.
    func setManufacturerDefault(_ id: UUID, _ isOn: Bool) -> Bool {
        guard let all = rows(), let row = all.first(where: { $0.uuid == id }) else { return false }
        if isOn {
            let key = ManufacturerName.key(row.manufacturer)
            guard !key.isEmpty else { return false }
            clearManufacturerDefault(in: all, key: key, except: id)
        }
        row.isManufacturerDefault = isOn
        return persist()
    }

    // MARK: - Storage

    /// A failed read keeps the last snapshot rather than emptying it.
    private func reload() {
        guard let all = rows() else { return }
        entries = all
            .map {
                EmptySpoolRecord(
                    id: $0.uuid, manufacturer: $0.manufacturer, name: $0.name, weight: $0.weight,
                    photo: $0.photo, isDefault: $0.isDefault,
                    isManufacturerDefault: $0.isManufacturerDefault, createdAt: $0.createdAt
                )
            }
            .sorted { a, b in
                if a.isDefault != b.isDefault { return a.isDefault }
                let order = a.listTitle.localizedCaseInsensitiveCompare(b.listTitle)
                if order != .orderedSame { return order == .orderedAscending }
                return a.createdAt < b.createdAt
            }
    }

    /// Fetches all rows and filters in Swift rather than in a `#Predicate`:
    /// a library is a handful of rows, and it keeps UUID comparisons out of
    /// the predicate language (same call as `LocationRegistry`). Nil when the
    /// fetch throws, so a write can refuse instead of acting on an empty
    /// library that is only empty because it could not be read.
    private func rows() -> [EmptySpoolEntry]? {
        do {
            return try context.fetch(FetchDescriptor<EmptySpoolEntry>())
        } catch {
            logger.error("Empty spool library fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func clearDefault(in all: [EmptySpoolEntry], except id: UUID?) {
        for row in all where row.isDefault && row.uuid != id {
            row.isDefault = false
        }
    }

    private func clearManufacturerDefault(in all: [EmptySpoolEntry], key: String, except id: UUID?) {
        for row in all where row.isManufacturerDefault && row.uuid != id
            && ManufacturerName.key(row.manufacturer) == key {
            row.isManufacturerDefault = false
        }
    }

    /// Saves, or rolls the unsaved changes back so the snapshot matches what
    /// is actually stored.
    private func persist() -> Bool {
        do {
            try context.save()
            reload()
            return true
        } catch {
            logger.error("Empty spool library save failed: \(error.localizedDescription)")
            context.rollback()
            reload()
            return false
        }
    }
}

private let logger = Logger(subsystem: "com.spoolkid", category: "EmptySpoolLibrary")
