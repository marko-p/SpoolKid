//
//  LocationAssignmentStateTests.swift
//  SpoolKidTests
//
//  Purpose: The guided assignment session's whole decision surface, testable
//  without NFC hardware — including the auto-chain that disables itself and
//  the sticky location slot that makes shelf-stocking cheap.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationAssignmentStateTests {
    private let spool = LocationAssignmentState.SpoolSlot(id: 12, label: "Spool #12")
    private let shelf = LocationAssignmentState.LocationSlot(name: "Shelf A")

    @Test func aFreshSessionAsksForEitherHalf() {
        let state = LocationAssignmentState()

        #expect(state.spool == nil)
        #expect(state.location == nil)
        #expect(state.statusLine == "Present a spool tag, or choose a spool")
    }

    @Test func aSpoolWithNoLocationYetChainsIntoTheLocationScan() {
        var state = LocationAssignmentState()

        let effect = LocationAssignmentState.reduce(&state, .gotSpool(spool))

        #expect(effect == .startLocationScan)
        #expect(state.spool == spool)
        #expect(state.statusLine == "Spool #12 · now present a location tag")
    }

    @Test func aSpoolWithALocationAlreadyHeldCommitsInsteadOfChaining() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotLocation(shelf))

        let effect = LocationAssignmentState.reduce(&state, .gotSpool(spool))

        #expect(effect == .commit(.init(spoolId: 12, spoolLabel: "Spool #12", locationName: "Shelf A")))
    }

    @Test func fillingTheLocationSecondAlsoCommits() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotSpool(spool))

        let effect = LocationAssignmentState.reduce(&state, .gotLocation(shelf))

        #expect(effect == .commit(.init(spoolId: 12, spoolLabel: "Spool #12", locationName: "Shelf A")))
    }

    @Test func aLocationAloneJustWaitsForSpools() {
        var state = LocationAssignmentState()

        let effect = LocationAssignmentState.reduce(&state, .gotLocation(shelf))

        #expect(effect == .none)
        #expect(state.statusLine == "Shelf A · present a spool tag, or choose a spool")
    }

    @Test func aSuccessfulAssignmentClearsTheSpoolAndKeepsTheLocation() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotLocation(shelf))
        LocationAssignmentState.reduce(&state, .gotSpool(spool))

        LocationAssignmentState.reduce(&state, .assignmentSucceeded)

        #expect(state.spool == nil)
        #expect(state.location == shelf)
        #expect(state.assignments.map(\.spoolId) == [12])
        #expect(state.statusLine == "Assigned Spool #12 to Shelf A · present the next spool")
    }

    @Test func theChainDoesNotFireOnceAShelfIsHeld() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotLocation(shelf))
        LocationAssignmentState.reduce(&state, .gotSpool(spool))
        LocationAssignmentState.reduce(&state, .assignmentSucceeded)

        let effect = LocationAssignmentState.reduce(
            &state, .gotSpool(.init(id: 13, label: "Spool #13"))
        )

        #expect(effect == .commit(.init(spoolId: 13, spoolLabel: "Spool #13", locationName: "Shelf A")))
    }

    @Test func aFailedAssignmentKeepsBothSlotsSoItCanBeRetried() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotLocation(shelf))
        LocationAssignmentState.reduce(&state, .gotSpool(spool))

        LocationAssignmentState.reduce(&state, .assignmentFailed)

        #expect(state.spool == spool)
        #expect(state.location == shelf)
        #expect(state.assignments.isEmpty)
    }

    @Test func changingTheLocationMidSessionDoesNotDiscardTheHeldSpool() {
        var state = LocationAssignmentState()
        LocationAssignmentState.reduce(&state, .gotSpool(spool))
        LocationAssignmentState.reduce(&state, .clearedLocation)

        #expect(state.spool == spool)
        #expect(state.location == nil)
    }

    @Test func scanningStatesSayWhichTagToPresent() {
        var state = LocationAssignmentState()

        LocationAssignmentState.reduce(&state, .beganScanning(.spool))
        #expect(state.statusLine == "Hold your iPhone near a spool tag")

        LocationAssignmentState.reduce(&state, .beganScanning(.location))
        #expect(state.statusLine == "Hold your iPhone near a location tag")

        LocationAssignmentState.reduce(&state, .cancelledScan)
        #expect(state.statusLine == "Present a spool tag, or choose a spool")
    }

    // MARK: - Linking an unlinked spool tag (2026-09-24)
    //
    // A spool tag that matches no spool sends the user to pick the spool by
    // hand. Afterwards the screen offers to link the tag to it — only where the
    // tag identity mode writes links.

    @Test func anUnlinkedTagIsOfferedForLinkingWhereLinksAreWritten() {
        #expect(LocationAssignmentView.linkOfferUID(unresolvedUID: "04AABB", writesLinks: true) == "04AABB")
    }

    @Test func noLinkOfferWhereLinksAreNotWritten() {
        #expect(LocationAssignmentView.linkOfferUID(unresolvedUID: "04AABB", writesLinks: false) == nil)
    }

    @Test func noLinkOfferWhenNoTagWasScanned() {
        #expect(LocationAssignmentView.linkOfferUID(unresolvedUID: nil, writesLinks: true) == nil)
    }
}
