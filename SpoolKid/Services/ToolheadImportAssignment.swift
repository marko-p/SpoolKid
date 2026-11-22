//
//  ToolheadImportAssignment.swift
//  SpoolKid
//
//  Purpose: The one way a Library spool reaches a toolhead, for Assign Spool
//  and for a spool just added or linked from a printer tag. The spool id
//  goes where the printer counts usage: Moonraker's Spoolman takes it in the
//  command, FilaMan's Moonraker component through its own endpoint.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum ToolheadImportAssignment {
    enum Step: Equatable {
        case send(ToolheadAssignment, filamanSpoolID: Int?)
        /// A forced write replaces what the toolhead holds; the user confirms
        /// it first, always (`AssignSpoolView`).
        case confirmFirst
        /// Nothing is queued: the user assigns it after the print.
        case waitForPrint
    }

    static func step(spool: Spool, toolhead: ToolheadState, route: PrinterUsageRoute?, printing: Bool, assignsSpoolID: Bool) -> Step {
        if printing { return .waitForPrint }
        if PrinterCommands.needsForce(toolhead) { return .confirmFirst }
        return send(spool: spool, route: route, assignsSpoolID: assignsSpoolID)
    }

    /// What is sent, once any confirmation is behind it.
    static func send(spool: Spool, route: PrinterUsageRoute?, assignsSpoolID: Bool) -> Step {
        .send(
            ToolheadAssignment(spool: spool, sendsSpoolID: route == .spoolman && assignsSpoolID),
            filamanSpoolID: route == .filaman ? spool.id : nil
        )
    }

    static let tagNotLinkedText = "The tag isn't linked to this spool."

    /// Said after Add Spool when the spool saved but its tag didn't land on it.
    static func tagNote(linkedSpoolID: Int?, savedSpoolID: Int) -> String? {
        linkedSpoolID == savedSpoolID ? nil : tagNotLinkedText
    }

    /// The text after an import, nil when there is nothing to add (the
    /// spool is on the toolhead, or a confirmation is up). `tagNote` is what
    /// the link left to say; it is never dropped.
    static func message(saved: Bool, outcome: ToolheadWriteOutcome?, step: Step, toolhead: String, tagNote: String?) -> String? {
        guard saved else { return tagNote }
        var assignment: String?
        if step == .waitForPrint {
            assignment = "Saved to the Library. Assign it to \(toolhead) once the print ends."
        } else if let reason = outcome?.message {
            assignment = "Saved to the Library, but not assigned to \(toolhead): \(reason)"
        }
        return SaveOutcome.combinedNote([tagNote, assignment])
    }

    /// Sends a `.send` step. The FilaMan component hears of the spool only
    /// once the toolhead shows the filament; either failure is the outcome.
    static func perform(_ step: Step, toolhead: Int, force: Bool, printer: PrinterService) async -> ToolheadWriteOutcome? {
        guard case .send(let assignment, let filamanSpoolID) = step else { return nil }
        let outcome = await printer.assign(assignment, toolhead: toolhead, force: force)
        guard outcome == .confirmed, let filamanSpoolID else { return outcome }
        return await printer.assignFilaManSpool(filamanSpoolID, toolhead: toolhead)
    }
}
