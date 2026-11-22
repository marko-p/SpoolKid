//
//  ToolheadImportAssignmentTests.swift
//  SpoolKidTests
//
//  Purpose: How a spool reaches a toolhead after Assign Spool or a printer
//  tag import, and what the user is told when the spool is saved but not
//  assigned. Never "assigned" for an assignment that didn't happen.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

@MainActor
struct ToolheadImportAssignmentTests {
    private let spool = Spool(
        id: 42,
        filament: Filament(id: 5, name: "PETG Transparent", material: "PETG", vendor: Vendor(id: 1, name: "AzureFilm"), colorHex: "257298"),
        remainingWeight: 1000, extra: nil, rfidUID: nil, statusId: nil, externalId: nil, purchaseDate: nil
    )

    private func toolhead(official: Bool = false, spoolID: Int? = nil) -> ToolheadState {
        ToolheadState(index: 0, material: "PETG", colorHexes: ["257298"], alpha: 6, isLoaded: true, isOfficial: official, spoolID: spoolID)
    }

    @Test func printingWaits() {
        let step = ToolheadImportAssignment.step(spool: spool, toolhead: toolhead(official: true), route: .spoolman, printing: true, assignsSpoolID: true)
        #expect(step == .waitForPrint)
    }

    @Test func anOfficialToolheadIsConfirmedFirst() {
        #expect(ToolheadImportAssignment.step(spool: spool, toolhead: toolhead(official: true), route: .spoolman, printing: false, assignsSpoolID: true) == .confirmFirst)
        #expect(ToolheadImportAssignment.step(spool: spool, toolhead: toolhead(spoolID: 3), route: .spoolman, printing: false, assignsSpoolID: true) == .confirmFirst)
    }

    @Test func spoolmanSendsTheID() {
        guard case .send(let assignment, let filamanID) = ToolheadImportAssignment.step(
            spool: spool, toolhead: toolhead(), route: .spoolman, printing: false, assignsSpoolID: true
        ) else { Issue.record("expected a send"); return }
        #expect(assignment.spoolID == 42)
        #expect(filamanID == nil)
    }

    @Test func noSpoolIDWhereThePrinterTakesNone() {
        guard case .send(let assignment, _) = ToolheadImportAssignment.step(
            spool: spool, toolhead: toolhead(), route: .spoolman, printing: false, assignsSpoolID: false
        ) else { Issue.record("expected a send"); return }
        #expect(assignment.spoolID == nil)
    }

    @Test func filamanSendsThroughTheComponent() {
        guard case .send(let assignment, let filamanID) = ToolheadImportAssignment.step(
            spool: spool, toolhead: toolhead(), route: .filaman, printing: false, assignsSpoolID: true
        ) else { Issue.record("expected a send"); return }
        #expect(assignment.spoolID == nil)
        #expect(filamanID == 42)
    }

    @Test func noRouteSendsOnlyTheFilament() {
        guard case .send(let assignment, let filamanID) = ToolheadImportAssignment.step(
            spool: spool, toolhead: toolhead(), route: nil, printing: false, assignsSpoolID: true
        ) else { Issue.record("expected a send"); return }
        #expect(assignment.spoolID == nil)
        #expect(filamanID == nil)
    }

    @Test func aFailedAssignmentStillSaysTheSpoolIsSaved() throws {
        let step = ToolheadImportAssignment.Step.send(ToolheadAssignment(spool: spool, sendsSpoolID: true), filamanSpoolID: nil)
        let text = try #require(ToolheadImportAssignment.message(saved: true, outcome: .failed("x"), step: step, toolhead: "T1", tagNote: nil))
        #expect(text == "Saved to the Library, but not assigned to T1: x")
        #expect(text.contains("saved") || text.contains("Saved"))
        #expect(!text.contains("assigned to T1.") && !text.hasPrefix("Assigned"))
        let unconfirmed = try #require(ToolheadImportAssignment.message(saved: true, outcome: .notConfirmed, step: step, toolhead: "T1", tagNote: nil))
        #expect(unconfirmed.hasPrefix("Saved to the Library, but not assigned to T1: "))
    }

    @Test func waitingSaysAfterThePrint() {
        #expect(ToolheadImportAssignment.message(saved: true, outcome: nil, step: .waitForPrint, toolhead: "T1", tagNote: nil)
            == "Saved to the Library. Assign it to T1 once the print ends.")
    }

    @Test func aConfirmedAssignmentNeedsNoText() {
        let step = ToolheadImportAssignment.Step.send(ToolheadAssignment(spool: spool, sendsSpoolID: true), filamanSpoolID: nil)
        #expect(ToolheadImportAssignment.message(saved: true, outcome: .confirmed, step: step, toolhead: "T1", tagNote: nil) == nil)
    }

    @Test func aLinkCaveatIsKeptBesideTheAssignment() throws {
        let step = ToolheadImportAssignment.Step.send(ToolheadAssignment(spool: spool, sendsSpoolID: true), filamanSpoolID: nil)
        #expect(ToolheadImportAssignment.message(saved: true, outcome: .confirmed, step: step, toolhead: "T1", tagNote: "Still mapped to #12.")
            == "Still mapped to #12.")
        let failed = try #require(ToolheadImportAssignment.message(saved: true, outcome: .failed("x"), step: step, toolhead: "T1", tagNote: "Still mapped to #12."))
        #expect(failed.contains("Still mapped to #12."))
        #expect(failed.contains("not assigned to T1: x"))
        let waiting = try #require(ToolheadImportAssignment.message(saved: true, outcome: nil, step: .waitForPrint, toolhead: "T1", tagNote: "Still mapped to #12."))
        #expect(waiting.contains("Still mapped to #12.") && waiting.contains("once the print ends"))
    }

    @Test func aSpoolSavedWithoutItsTagSaysSo() {
        #expect(ToolheadImportAssignment.tagNote(linkedSpoolID: nil, savedSpoolID: 42) == ToolheadImportAssignment.tagNotLinkedText)
        #expect(ToolheadImportAssignment.tagNote(linkedSpoolID: 12, savedSpoolID: 42) == ToolheadImportAssignment.tagNotLinkedText)
        #expect(ToolheadImportAssignment.tagNote(linkedSpoolID: 42, savedSpoolID: 42) == nil)
    }
}
