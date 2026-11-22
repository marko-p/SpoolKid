//
//  LocationTagWriteCopyTests.swift
//  SpoolKidTests
//
//  Purpose: The rename-offers-rewrite copy. The registry records WHICH tags
//  carry a location, so the offer can name the count instead of guessing.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationTagWriteCopyTests {
    @Test func noTagsMeansNoOffer() {
        #expect(LocationDetailView.tagPromptCopy(tagCount: 0) == nil)
    }

    @Test func oneTagReadsSingular() {
        #expect(LocationDetailView.tagPromptCopy(tagCount: 1) ==
                "This location is on 1 tag. Write the new name to it?")
    }

    @Test func severalTagsReadPlural() {
        #expect(LocationDetailView.tagPromptCopy(tagCount: 3) ==
                "This location is on 3 tags. Write the new name to them?")
    }

    /// A spool's claim can be unlinked from here; a filament's is released
    /// from the filament, so the alert offers no unlink here.
    @Test func aFilamentsTagIsRefusedWithoutAnUnlink() {
        let filament = TagOwner.filament(id: 7, label: "Silk PLA")
        #expect(LocationDetailView.blockedTitle(owner: filament) == "Tag Belongs to a Filament")
        #expect(LocationDetailView.canUnlinkBlockedTag(owner: filament) == false)
        #expect(LocationDetailView.blockedTitle(owner: .spool(id: 1, label: "A")) == "Tag Is Linked to a Spool")
        #expect(LocationDetailView.canUnlinkBlockedTag(owner: .spool(id: 1, label: "A")))
    }
}
