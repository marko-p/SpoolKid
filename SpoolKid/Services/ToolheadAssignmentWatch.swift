//
//  ToolheadAssignmentWatch.swift
//  SpoolKid
//
//  Purpose: Notices when something the app put on a toolhead is gone. Stored,
//  because an unload usually happens while the app is closed. Scoped to the
//  printer's address: toolhead 1 of another printer is a different toolhead.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ToolheadNote: Equatable, Sendable {
    case clearedWhenUnloaded
    case clearedOnPrinter
    case replacedByTag
    case changedOnPrinter

    var message: String {
        switch self {
        case .clearedWhenUnloaded: "Cleared when unloaded"
        case .clearedOnPrinter: "Cleared on the printer"
        case .replacedByTag: "Replaced when its tag was read"
        case .changedOnPrinter: "Changed on the printer"
        }
    }
}

nonisolated struct ToolheadAssignmentWatch: Codable, Equatable, Sendable {
    var address: String
    var assignments: [Int: ToolheadAssignment] = [:]

    /// Nil while the toolhead still shows what was sent.
    static func note(for assignment: ToolheadAssignment, state: ToolheadState) -> ToolheadNote? {
        if !state.hasData { return state.isLoaded ? .clearedOnPrinter : .clearedWhenUnloaded }
        if PrinterCommands.confirms(assignment, state: state) { return nil }
        return state.tagUID == nil ? .changedOnPrinter : .replacedByTag
    }

    func notes(for toolheads: [ToolheadState]) -> [Int: ToolheadNote] {
        var result: [Int: ToolheadNote] = [:]
        for toolhead in toolheads {
            if let assignment = assignments[toolhead.index],
               let note = Self.note(for: assignment, state: toolhead) {
                result[toolhead.index] = note
            }
        }
        return result
    }

    static func load(address: String, defaults: UserDefaults) -> ToolheadAssignmentWatch {
        guard let data = defaults.data(forKey: AppConfig.printerAssignmentWatchKey),
              let stored = try? JSONDecoder().decode(ToolheadAssignmentWatch.self, from: data),
              stored.address == address else { return ToolheadAssignmentWatch(address: address) }
        return stored
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: AppConfig.printerAssignmentWatchKey)
    }
}
