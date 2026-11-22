//
//  LocationRegistryTests.swift
//  SpoolKidTests
//
//  Purpose: The device-local location registry — the only home for a location
//  no spool references yet, and for the uuid⇄name map that survives renames.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct LocationRegistryTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func addStoresATrimmedNameAndPublishesIt() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)

        let added = try #require(registry.add(name: "  Shelf A  "))

        #expect(added.name == "Shelf A")
        #expect(added.tagUIDs.isEmpty)
        #expect(registry.records.map(\.name) == ["Shelf A"])
    }

    @Test func addIsIdempotentOnNameIgnoringCaseAndWhitespace() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)

        let first = try #require(registry.add(name: "Shelf A"))
        let second = try #require(registry.add(name: " shelf a "))

        #expect(first.uuid == second.uuid)
        #expect(registry.records.count == 1)
    }

    @Test func addRejectsABlankName() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .local)

        #expect(registry.add(name: "   ") == nil)
        #expect(registry.records.isEmpty)
    }

    @Test func recordsAreScopedToTheBackendKind() throws {
        let context = try makeContext()
        let spoolman = LocationRegistry(context: context, backendKind: .spoolman)
        let filaman = LocationRegistry(context: context, backendKind: .filaman)

        spoolman.add(name: "Shelf A")
        filaman.reload()

        #expect(spoolman.records.map(\.name) == ["Shelf A"])
        #expect(filaman.records.isEmpty)
    }

    @Test func adoptCreatesTheEntryUnderTheTagsOwnUUID() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let uuid = UUID()

        let adopted = try #require(registry.adopt(uuid: uuid, name: " Shelf A ", tagUID: "aabbccdd"))

        // Without this the tag stays unrecognised however often it is added:
        // the registry would mint a fresh uuid every time.
        #expect(adopted.uuid == uuid)
        #expect(adopted.name == "Shelf A")
        #expect(adopted.tagUIDs == ["AABBCCDD"])
        #expect(registry.records.count == 1)
    }

    @Test func adoptIsIdempotentForTheSameTag() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let uuid = UUID()

        registry.adopt(uuid: uuid, name: "Shelf A", tagUID: "AABBCCDD")
        let second = try #require(registry.adopt(uuid: uuid, name: "Shelf A", tagUID: "aabbccdd"))

        #expect(second.uuid == uuid)
        #expect(second.tagUIDs == ["AABBCCDD"])
        #expect(registry.records.count == 1)
    }

    /// The name collision: one location is one entry, so the entry that already
    /// holds the name wins and the incoming tag joins it. Forking a second
    /// entry under one name would give `record(named:)` two answers, and the
    /// existing uuid may already be on tags of its own.
    @Test func adoptMergesIntoAnEntryThatAlreadyHoldsTheNameKeepingItsUUID() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let existing = try #require(registry.add(name: "Shelf A"))
        registry.attachTag(uid: "11223344", to: existing.uuid)

        let adopted = try #require(registry.adopt(uuid: UUID(), name: "shelf a", tagUID: "AABBCCDD"))

        #expect(registry.records.count == 1)
        #expect(adopted.uuid == existing.uuid)
        #expect(adopted.name == "Shelf A")
        #expect(adopted.tagUIDs == ["11223344", "AABBCCDD"])
    }

    /// The mirror collision: this uuid is already registered under a name the
    /// user has since changed. The registry's name wins over the tag's cached
    /// one, and the tag is recorded so a rename can offer to rewrite it.
    @Test func adoptUnderAKnownUUIDKeepsTheRegistrysNameAndRecordsTheTag() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let existing = try #require(registry.add(name: "Shelf A"))
        registry.rename(from: "Shelf A", to: "Shelf Alpha")

        let adopted = try #require(registry.adopt(uuid: existing.uuid, name: "Shelf A", tagUID: "AABBCCDD"))

        #expect(registry.records.count == 1)
        #expect(adopted.name == "Shelf Alpha")
        #expect(adopted.tagUIDs == ["AABBCCDD"])
    }

    @Test func adoptRejectsABlankName() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .local)

        #expect(registry.adopt(uuid: UUID(), name: "  ", tagUID: "AABBCCDD") == nil)
        #expect(registry.records.isEmpty)
    }

    @Test func adoptWithoutATagUIDStillCreatesTheEntry() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let uuid = UUID()

        let adopted = try #require(registry.adopt(uuid: uuid, name: "Shelf A"))

        #expect(adopted.uuid == uuid)
        #expect(adopted.tagUIDs.isEmpty)
    }

    @Test func renameReportsWhetherThereWasAnythingToRename() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        registry.add(name: "Shelf A")

        #expect(registry.rename(from: "Shelf A", to: "Shelf Alpha"))
        #expect(registry.rename(from: "Shelf A", to: "Shelf Beta") == false)
        #expect(registry.rename(from: "Shelf Alpha", to: "   ") == false)
        #expect(registry.records.map(\.name) == ["Shelf Alpha"])
    }

    @Test func renameKeepsTheUUIDSoWrittenTagsStillResolve() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let original = try #require(registry.add(name: "Shelf A"))

        registry.rename(from: "Shelf A", to: "Shelf Alpha")

        let renamed = try #require(registry.records.first)
        #expect(renamed.uuid == original.uuid)
        #expect(renamed.name == "Shelf Alpha")
    }

    @Test func removeDropsOnlyTheNamedRecord() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        registry.add(name: "Shelf A")
        registry.add(name: "Shelf B")

        registry.remove(named: "shelf a")

        #expect(registry.records.map(\.name) == ["Shelf B"])
    }

    @Test func attachTagNormalizesTheUIDAndIsIdempotent() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let record = try #require(registry.add(name: "Shelf A"))

        registry.attachTag(uid: "aabbccdd", to: record.uuid)
        registry.attachTag(uid: "AABBCCDD", to: record.uuid)

        #expect(registry.records.first?.tagUIDs == ["AABBCCDD"])
        #expect(registry.records.first?.isTagged == true)
    }

    @Test func recordForTagUIDFindsTheOwningLocation() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let a = try #require(registry.add(name: "Shelf A"))
        registry.add(name: "Shelf B")
        registry.attachTag(uid: "AABBCCDD", to: a.uuid)

        #expect(registry.record(forTagUID: "aabbccdd")?.uuid == a.uuid)
        #expect(registry.record(forTagUID: "11223344") == nil)
    }

    @Test func detachTagRemovesTheUIDFromWhicheverRecordHeldIt() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let a = try #require(registry.add(name: "Shelf A"))
        registry.attachTag(uid: "AABBCCDD", to: a.uuid)

        registry.detachTag(uid: "AABBCCDD")

        #expect(registry.records.first?.tagUIDs.isEmpty == true)
        #expect(registry.records.first?.isTagged == false)
    }


    // MARK: - One tag, one shelf

    /// A tag labels ONE location. Re-tagging a second shelf with the same
    /// physical tag moves it, rather than leaving both entries claiming it —
    /// `record(forTagUID:)` is a `first(where:)` and would otherwise answer
    /// with whichever entry happened to sort earlier.
    @Test func attachingATagToASecondLocationMovesItOffTheFirst() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let first = try #require(registry.add(name: "Shelf A"))
        let second = try #require(registry.add(name: "Shelf B"))

        registry.attachTag(uid: "04A1B2C3", to: first.uuid)
        registry.attachTag(uid: "04A1B2C3", to: second.uuid)

        #expect(registry.record(named: "Shelf A")?.tagUIDs.isEmpty == true)
        #expect(registry.record(named: "Shelf B")?.tagUIDs == ["04A1B2C3"])
        #expect(registry.record(forTagUID: "04A1B2C3")?.name == "Shelf B")
    }

    /// The move is by NORMALIZED UID, so the separators and casing a tag's UID
    /// arrived in cannot let one physical tag hold two entries.
    @Test func theMoveNormalizesBeforeComparing() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let first = try #require(registry.add(name: "Shelf A"))
        let second = try #require(registry.add(name: "Shelf B"))

        registry.attachTag(uid: "04:a1:b2:c3", to: first.uuid)
        registry.attachTag(uid: "04-A1-B2-C3", to: second.uuid)

        #expect(registry.record(named: "Shelf A")?.tagUIDs.isEmpty == true)
        #expect(registry.record(named: "Shelf B")?.tagUIDs == ["04A1B2C3"])
    }

    /// Re-attaching a shelf's own tag is not a move and must not disturb the
    /// other tags it holds.
    @Test func reattachingATagToItsOwnLocationChangesNothing() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let shelf = try #require(registry.add(name: "Shelf A"))

        registry.attachTag(uid: "04A1B2C3", to: shelf.uuid)
        registry.attachTag(uid: "DEADBEEF", to: shelf.uuid)
        registry.attachTag(uid: "04A1B2C3", to: shelf.uuid)

        #expect(registry.record(named: "Shelf A")?.tagUIDs == ["04A1B2C3", "DEADBEEF"])
    }

    /// `adopt` shares the one attach point, so a tag written on another device
    /// for a shelf this device already tagged differently lands on one entry.
    @Test func adoptingATagAlsoTakesItOffItsPreviousLocation() throws {
        let registry = LocationRegistry(context: try makeContext(), backendKind: .spoolman)
        let first = try #require(registry.add(name: "Shelf A"))
        registry.attachTag(uid: "04A1B2C3", to: first.uuid)

        registry.adopt(uuid: UUID(), name: "Shelf B", tagUID: "04A1B2C3")

        #expect(registry.record(named: "Shelf A")?.tagUIDs.isEmpty == true)
        #expect(registry.record(forTagUID: "04A1B2C3")?.name == "Shelf B")
    }
}
