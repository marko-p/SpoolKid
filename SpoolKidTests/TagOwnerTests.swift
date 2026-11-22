//
//  TagOwnerTests.swift
//  SpoolKidTests
//
//  Purpose: The global single-owner rule — a tag UID belongs to at most one
//  spool or one location, never both. `TagOwner` is where that is decided;
//  these pin the decision itself, without a store.
//

import Foundation
import Testing
@testable import SpoolKid

struct TagOwnerTests {
    private let shelf = TagOwner.location(name: "Shelf A")
    private let spool = TagOwner.spool(id: 7, label: "Spool #7 · PLA")

    /// The rule that motivates the type: the two kinds of owner are mutually
    /// exclusive, in both directions.
    @Test func aSpoolAndALocationCannotBothHoldOneTag() {
        #expect(shelf.conflicts(with: spool))
        #expect(spool.conflicts(with: shelf))
    }

    /// An unclaimed tag refuses nobody, and claiming nothing conflicts with
    /// nothing — otherwise every first scan would be a conflict.
    @Test func anUnownedTagIsNeverAConflict() {
        #expect(!TagOwner.none.conflicts(with: spool))
        #expect(!spool.conflicts(with: TagOwner.none))
        #expect(TagOwner.none.claimRefusal(attemptedBy: spool) == nil)
    }

    /// Re-scanning a spool's own tag is an ordinary thing to do and must not be
    /// refused — the rule is one owner, not one claim.
    @Test func reclaimingByTheSameOwnerIsNotAConflict() {
        #expect(!spool.conflicts(with: .spool(id: 7, label: "Spool #7 · PLA")))
        #expect(!shelf.conflicts(with: .location(name: "Shelf A")))
        #expect(spool.claimRefusal(attemptedBy: .spool(id: 7, label: "Spool #7 · PLA")) == nil)
    }

    /// Two different spools DO conflict — that is the auto-move `TagLinkService`
    /// performs, and it has to be recognised as a conflict to be performed.
    @Test func twoDifferentOwnersOfTheSameKindConflict() {
        #expect(spool.conflicts(with: .spool(id: 8, label: "Spool #8 · PETG")))
        #expect(shelf.conflicts(with: .location(name: "Shelf B")))
    }

    /// A refusal has to name what already holds the tag: "that tag is taken"
    /// with no name is not something a user can act on.
    @Test func aRefusalNamesTheCurrentOwner() throws {
        let fromShelf = try #require(shelf.claimRefusal(attemptedBy: spool))
        #expect(fromShelf.contains("Shelf A"))

        let fromSpool = try #require(spool.claimRefusal(attemptedBy: shelf))
        #expect(fromSpool.contains("Spool #7 · PLA"))
    }

    /// Spoolman 0.27 can link a tag to a filament type. That tag is the
    /// filament's: a spool or a shelf asking for it is refused by name.
    @Test func aFilamentTagIsRefusedToASpoolByName() {
        let owner = TagOwner.filament(id: 7, label: "Polymaker PLA")
        #expect(owner.claimRefusal(attemptedBy: .spool(id: 1, label: "Spool #1"))
            == "That tag identifies the filament Polymaker PLA. A tag belongs to one spool, one filament or one location.")
        #expect(owner.claimRefusal(attemptedBy: .location(name: "Shelf")) != nil)
    }
}
