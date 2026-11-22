//
//  FilamentTagsTests.swift
//  SpoolKidTests
//
//  Spec 4: a tag can identify a filament type — Spoolman 0.27's own filament
//  tags, or the Library's `card_uids` on a filament.
//

import Foundation
import Testing
@testable import SpoolKid

struct FilamentTagPolicyTests {
    @Test func filamentLinksAreWrittenOnlyToATargetStore() {
        let tagLinks = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs])
        #expect(tagLinks.writesFilamentLinks(store: .cardUIDs))

        let spoolmanBoth = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.spoolmanTags, .cardUIDs])
        #expect(spoolmanBoth.writesFilamentLinks(store: .spoolmanTags))

        // Spoolman Tags switched off: `card_uids` is spool-only on a server.
        #expect(!tagLinks.writesFilamentLinks(store: .spoolmanTags))

        // No filament store (FilaMan, Spoolman before 0.27).
        #expect(!tagLinks.writesFilamentLinks(store: nil))

        // Spool ID and Neither write no links of any kind.
        #expect(!TagIdentityPolicy(mode: .spoolID, linkTargets: []).writesFilamentLinks(store: .cardUIDs))
        #expect(!TagIdentityPolicy(mode: .neither, linkTargets: []).writesFilamentLinks(store: .spoolmanTags))
    }
}

struct FilamentTagReadingTests {
    @Test func aLibraryFilamentsLinksAreReadFromCardUIDs() {
        let filament = Filament(id: 1, extra: ["card_uids": CardUIDsCodec.encode(["04aa", "04BB"])])
        #expect(filament.cardUIDs == ["04AA", "04BB"])
        #expect(filament.mappedTagUIDs == ["04AA", "04BB"])
    }

    @Test func nativeTagsComeFirstAndADuplicateOnce() {
        let filament = Filament(
            id: 1, extra: ["card_uids": CardUIDsCodec.encode(["04BB", "04AA"])], nativeTagUIDs: ["04AA"]
        )
        #expect(filament.mappedTagUIDs == ["04AA", "04BB"])
    }
}

@MainActor
struct FilamentTagOwnerTests {
    private func store(spools: [Spool] = [], filaments: [Filament]) -> SpoolDataStore {
        let writer = MockMigrationWriter(serverFilaments: filaments, serverSpools: spools)
        return SpoolDataStore(repository: writer, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func aLibraryFilamentLinkOwnsTheTag() {
        let store = store(filaments: [
            Filament(id: 5, name: "PLA Basic", extra: ["card_uids": CardUIDsCodec.encode(["04AA"])])
        ])
        guard case .filament(let id, _) = store.owner(ofTagUID: "04aa") else {
            Issue.record("the tag has no filament owner")
            return
        }
        #expect(id == 5)
        #expect(store.filamentTagUIDs == ["04AA"])
    }

    /// A spool's claim comes first: it is what a printer resolves.
    @Test func aSpoolClaimWinsOverAFilamentLink() {
        let filament = Filament(id: 5, name: "PLA", extra: ["card_uids": CardUIDsCodec.encode(["04AA"])])
        let spool = Spool(
            id: 9, filament: filament, extra: ["card_uids": CardUIDsCodec.encode(["04AA"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        let store = store(spools: [spool], filaments: [filament])
        guard case .spool(let id, _) = store.owner(ofTagUID: "04AA") else {
            Issue.record("the tag has no spool owner")
            return
        }
        #expect(id == 9)
    }

    @Test func anOwnerIsNamedByItsLabel() {
        #expect(TagOwner.filament(id: 1, label: "PLA Basic").label == "PLA Basic")
        #expect(TagOwner.spool(id: 2, label: "Spool #2").label == "Spool #2")
        #expect(TagOwner.location(name: "Shelf A").label == "Shelf A")
        #expect(TagOwner.none.label == "")
    }
}
