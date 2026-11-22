//
//  TagHolderMoveTests.swift
//  SpoolKidTests
//
//  Spec 4 §5: a tag moves between a spool and a filament, or between two
//  filaments — unlinked, then linked — and a failed relink is said, never
//  reported as a move.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct TagHolderMoveTests {
    private func libraryStore() throws -> SpoolDataStore {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(TagIdentityMode.tagLinks.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return SpoolDataStore(repository: LocalRepository(context: ModelContext(container)), defaults: defaults)
    }

    @Test func aSpoolsTagMovesToAFilament() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA"]))

        let outcome = await TagHolderMove.moveToFilament(
            uid: "04AA", from: store.owner(ofTagUID: "04AA"), to: filament, in: store
        )

        #expect(outcome == .saved)
        guard case .filament(let id, _) = store.owner(ofTagUID: "04AA") else {
            Issue.record("the tag did not move to the filament")
            return
        }
        #expect(id == filament.id)
    }

    @Test func aFilamentsTagMovesToASpool() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04AA") == .linked)

        let outcome = await TagHolderMove.moveToSpool(
            uid: "04AA", from: store.owner(ofTagUID: "04AA"), to: spool, in: store
        )

        #expect(outcome == .saved)
        guard case .spool(let id, _) = store.owner(ofTagUID: "04AA") else {
            Issue.record("the tag did not move to the spool")
            return
        }
        #expect(id == spool.id)
    }

    @Test func aFilamentsTagMovesToAnotherFilament() async throws {
        let store = try libraryStore()
        let first = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let second = try #require(await store.addFilament(draft: FilamentDraft(name: "PETG")))
        #expect(await store.linkFilamentTag(filamentId: first.id, uid: "04AA") == .linked)

        let outcome = await TagHolderMove.moveToFilament(
            uid: "04AA", from: store.owner(ofTagUID: "04AA"), to: second, in: store
        )

        #expect(outcome == .saved)
        guard case .filament(let id, _) = store.owner(ofTagUID: "04AA") else {
            Issue.record("the tag did not move")
            return
        }
        #expect(id == second.id)
    }

    /// The unlink happened; the link did not. Said as such.
    @Test func aFailedRelinkSaysTheTagWasUnlinked() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA"]))
        let gone = Filament(id: 999, name: "Gone")

        let outcome = await TagHolderMove.moveToFilament(
            uid: "04AA", from: store.owner(ofTagUID: "04AA"), to: gone, in: store
        )

        guard case .notSaved(let message) = outcome else {
            Issue.record("expected .notSaved, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("04AA was unlinked from"))
        #expect(store.owner(ofTagUID: "04AA") == .none)
    }

    /// A spool and its filament often share a name, so copy says which is
    /// which — and a spool's number.
    @Test func theHolderIsNamedByKind() {
        #expect(TagHolderMove.holderPhrase(.spool(id: 1, label: "AzureFilm Silk GOLD 18K")) == "spool #1, AzureFilm Silk GOLD 18K")
        #expect(TagHolderMove.holderPhrase(.filament(id: 7, label: "PETG Black")) == "the filament PETG Black")
    }

    @Test func theFilamentFormAsksBeforeMovingATag() {
        #expect(TagHolderMove.confirmationToFilament(uid: "048D1356C92A81", holder: .spool(id: 1, label: "AzureFilm Silk GOLD 18K"))
            == TagMoveConfirmation(
                title: "Move Tag from Spool to Filament?",
                message: "048D1356C92A81 is linked to spool #1, AzureFilm Silk GOLD 18K. Moving it unlinks it from the spool and links it to this filament."
            ))
        #expect(TagHolderMove.confirmationToFilament(uid: "04AA", holder: .filament(id: 7, label: "PETG Black"))
            == TagMoveConfirmation(
                title: "Move Tag to This Filament?",
                message: "04AA is linked to the filament PETG Black. Moving it unlinks it from that filament and links it to this one."
            ))
    }

    @Test func theSpoolFormAsksBeforeMovingATagOnSave() {
        #expect(TagHolderMove.confirmationToSpool(uid: "04AA", holder: .spool(id: 4, label: "PETG Black"))
            == TagMoveConfirmation(
                title: "Move Tag to This Spool?",
                message: "04AA is linked to spool #4, PETG Black. Saving unlinks it from that spool and links it to this one."
            ))
        #expect(TagHolderMove.confirmationToSpool(uid: "04AA", holder: .filament(id: 7, label: "PLA Basic"))
            == TagMoveConfirmation(
                title: "Move Tag from Filament to Spool?",
                message: "04AA is linked to the filament PLA Basic. Saving unlinks it from the filament and links it to this spool."
            ))
    }

    @Test func aFailedRelinkNamesBothHoldersByKind() {
        #expect(TagHolderMove.unlinkedNotRelinked("04AA", from: .spool(id: 1, label: "PLA"), to: .filament(id: 7, label: "PLA"), because: "Timed out")
            == "04AA was unlinked from spool #1, PLA, but could not be linked to the filament PLA: Timed out")
    }

    /// The spool form's save releases each moved tag before linking it.
    @Test func aSaveReleasesEachMovedTag() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04E1A0B1"]))
        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04E1A0B2") == .linked)

        let result = await TagHolderMove.releaseForSave(
            [
                (uid: "04E1A0B1", holder: store.owner(ofTagUID: "04E1A0B1")),
                (uid: "04E1A0B2", holder: store.owner(ofTagUID: "04E1A0B2")),
            ],
            in: store
        )

        #expect(result.kept.isEmpty)
        #expect(result.notes.isEmpty)
        #expect(store.owner(ofTagUID: "04E1A0B1") == .none)
        #expect(store.owner(ofTagUID: "04E1A0B2") == .none)
    }

    /// A shelf's tag never moves this way: it stays, and the save is told.
    @Test func aTagThatCannotBeReleasedIsKeptAndNamed() async throws {
        let store = try libraryStore()
        let result = await TagHolderMove.releaseForSave([(uid: "04E1A0B3", holder: .location(name: "Shelf A"))], in: store)
        #expect(result.kept == ["04E1A0B3"])
        #expect(result.notes == ["04E1A0B3 could not be unlinked from Shelf A, so it stays there."])
    }

    // MARK: - Several tags to a filament (spec 2026-10-11)

    private func filamentID(holding uid: String, in store: SpoolDataStore) -> Int? {
        if case .filament(let id, _) = store.owner(ofTagUID: uid) { return id }
        return nil
    }

    @Test func aSpoolsTickedTagsAllMoveToAFilament() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA", "04BB"]))

        let outcome = await TagHolderMove.moveToFilament(uids: ["04AA", "04BB"], to: filament, in: store)

        #expect(outcome == .saved)
        #expect(filamentID(holding: "04AA", in: store) == filament.id)
        #expect(filamentID(holding: "04BB", in: store) == filament.id)
    }

    /// One tag that cannot be linked is named; the rest still move.
    @Test func aTagThatCannotBeLinkedIsNamedAndTheRestStillMove() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA"]))

        let outcome = await TagHolderMove.moveToFilament(uids: ["04AA", " "], to: filament, in: store)

        guard case .savedWithCaveat(let note) = outcome else {
            Issue.record("expected .savedWithCaveat, got \(outcome)")
            return
        }
        #expect(note.contains("could not be linked to the filament PLA"))
        #expect(!note.contains("unlinked from ,"))
        #expect(filamentID(holding: "04AA", in: store) == filament.id)
    }

    @Test func whenNoTagMovesEveryFailureIsNamed() async throws {
        let store = try libraryStore()
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA", "04BB"]))
        let gone = Filament(id: 999, name: "Gone")

        let outcome = await TagHolderMove.moveToFilament(uids: ["04AA", "04BB"], to: gone, in: store)

        guard case .notSaved(let message) = outcome else {
            Issue.record("expected .notSaved, got \(outcome)")
            return
        }
        #expect(message.contains("04AA was unlinked from"))
        #expect(message.contains("04BB was unlinked from"))
        // Release-first: the tags are on no owner now, and the message says so.
        #expect(store.owner(ofTagUID: "04AA") == .none)
        #expect(store.owner(ofTagUID: "04BB") == .none)
    }

    /// A tag nothing held was never unlinked, so the message says only that
    /// the link failed (it used to read "was unlinked from , but").
    @Test func anUnheldTagsFailedLinkSaysOnlyThatItWasNotLinked() async throws {
        let store = try libraryStore()
        let gone = Filament(id: 999, name: "Gone")

        let outcome = await TagHolderMove.moveToFilament(uid: "04CC", from: .none, to: gone, in: store)

        guard case .notSaved(let message) = outcome else {
            Issue.record("expected .notSaved, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("04CC could not be linked to the filament Gone: "))
    }
}
