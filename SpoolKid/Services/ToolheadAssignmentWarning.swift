//
//  ToolheadAssignmentWarning.swift
//  SpoolKid
//
//  Purpose: What will happen to an assignment when the spool is loaded or
//  unloaded, said before it is sent (Printer tab spec, owner decision 3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ToolheadAssignmentWarning {
    /// What is known about the spool's tag.
    enum SpoolTag: Equatable, Sendable {
        case none
        /// A picked spool with a link: its format is not recorded.
        case unknownFormat
        /// A scanned tag, with its data as a label when it differs from the Library.
        case scanned(format: TagFormat, differsAs: String?)
    }

    /// Any link counts, native tags included. Which format the tag is in is
    /// not recorded anywhere.
    static func pickedTag(for spool: Spool) -> SpoolTag {
        spool.mappedCardUIDs.isEmpty ? .none : .unknownFormat
    }

    /// The lines for the confirmation, most important first. `needsForce`
    /// says the write must carry `FORCE=1` and be confirmed. `spoolLinkResolves`
    /// says the printer's SpoolLink can find this spool from its tag, and then
    /// Spoolman's data wins over the tag's (U1, 2026-11-07).
    static func lines(
        toolhead: ToolheadState, tag: SpoolTag, capabilities: PrinterCapabilities, spoolLinkResolves: Bool = false
    ) -> (lines: [String], needsForce: Bool) {
        var lines: [String] = []
        let needsForce = PrinterCommands.needsForce(toolhead)
        if toolhead.isOfficial {
            lines.append(officialLine(toolhead))
        } else if toolhead.isLoaded, toolhead.hasData {
            let holds = [toolhead.vendor, toolhead.material].compactMap { $0 }.joined(separator: " ")
            lines.append("\(toolhead.name) holds \(holds). Unloading it will clear this.")
        }
        lines.append(loadLine(tag: tag, formats: capabilities.tagFormatsRead, spoolLinkResolves: spoolLinkResolves))
        lines.append("Unloading clears the toolhead.")
        return (lines, needsForce)
    }

    /// "Official" only means a tag or SpoolLink set the toolhead: an OpenSpool
    /// tag on the built-in reader does too (U1, 2026-11-07).
    private static func officialLine(_ toolhead: ToolheadState) -> String {
        if let id = toolhead.spoolID { return "Replaces Spoolman spool #\(id) on \(toolhead.name)." }
        if toolhead.tagUID != nil, toolhead.vendor?.caseInsensitiveCompare("Snapmaker") != .orderedSame {
            return "Replaces what this toolhead's tag set."
        }
        return "Replaces the Snapmaker spool's data."
    }

    private static func loadLine(tag: SpoolTag, formats: Set<TagFormat>?, spoolLinkResolves: Bool) -> String {
        let fromSpoolman = "When you load it, the printer reads its tag and uses this spool's Spoolman data."
        switch tag {
        case .none:
            return "Kept when you load this spool."
        case .unknownFormat:
            if spoolLinkResolves { return "If the printer can read this spool's tag, it uses this spool's Spoolman data when you load it." }
            return "If the printer can read this spool's tag, the tag sets this toolhead when you load it."
        case .scanned(let format, let differsAs):
            guard formats?.contains(format) ?? true else { return "Kept when you load this spool." }
            if spoolLinkResolves { return fromSpoolman }
            if let differsAs {
                return "Its tag will replace this with \(differsAs) when loaded. Rewrite the tag first?"
            }
            return "Its tag sets this toolhead when you load it."
        }
    }
}
