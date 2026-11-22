//
//  SpoolFormTagClaimTests.swift
//  SpoolKidTests
//
//  One tag, one owner, in the spool form's "Scan tag to link" (2026-10-11):
//  a shelf's tag is refused with a way through, another holder's tag is
//  offered as a move, and a free or own tag is simply listed.
//

import Testing
@testable import SpoolKid

struct SpoolFormTagClaimTests {
    private func decide(
        _ uid: String? = "04aa",
        shelf: String? = nil,
        owner: TagOwner = .none,
        editing: Int? = 9,
        offered: [String] = [],
        listed: [String] = []
    ) -> SpoolFormTagClaim {
        SpoolFormTagClaim.decide(
            uid: uid, payloadShelfName: shelf, owner: owner,
            editingSpoolID: editing, offeredUIDs: offered, listedUIDs: listed
        )
    }

    @Test func aFreeTagIsTakenNormalized() {
        #expect(decide() == .take(uid: "04AA"))
    }

    @Test func theSpoolsOwnTagIsTaken() {
        #expect(decide(owner: .spool(id: 9, label: "PLA Red")) == .take(uid: "04AA"))
    }

    @Test func aListedTagOrNoUIDIsIgnored() {
        #expect(decide(listed: ["04AA"]) == .ignore)
        #expect(decide(nil) == .ignore)
    }

    @Test func aShelfTagIsRefusedByPayloadOrRegistry() {
        #expect(decide(shelf: "Shelf A") == .refuseShelf(uid: "04AA", name: "Shelf A"))
        #expect(decide(owner: .location(name: "Shelf B")) == .refuseShelf(uid: "04AA", name: "Shelf B"))
    }

    @Test func anotherSpoolsTagIsOfferedAsAMove() {
        let other = TagOwner.spool(id: 4, label: "PETG Black")
        #expect(decide(owner: other) == .offerMove(uid: "04AA", holder: other))
        #expect(decide(owner: other, editing: nil) == .offerMove(uid: "04AA", holder: other))
    }

    @Test func aFilamentsTagIsOfferedAsAMove() {
        let filament = TagOwner.filament(id: 5, label: "PLA Basic")
        #expect(decide(owner: filament) == .offerMove(uid: "04AA", holder: filament))
    }

    @Test func anOfferedTagIsTickedNotAsked() {
        #expect(decide(owner: .spool(id: 4, label: "PETG Black"), editing: nil, offered: ["04AA"]) == .takeOffered(uid: "04AA"))
    }
}
