//
//  LocationAssignmentState.swift
//  SpoolKid
//
//  Purpose: The guided assignment session's decision surface, as a pure value.
//  No SwiftUI and no NFC, so the auto-chain and the sticky location slot are
//  testable without hardware.
//
//  Two rules earn their own tests. The location slot is STICKY — a commit
//  clears the spool and keeps the shelf, which is what makes stocking a shelf
//  one scan per spool instead of two. And the auto-chain into a location scan
//  fires only while the location slot is EMPTY, so it does the spool→location
//  chain on the first pass and then stops asking for a tag the session already
//  holds.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationAssignmentState: Equatable, Sendable {
    nonisolated struct SpoolSlot: Equatable, Sendable {
        let id: Int
        let label: String
    }

    nonisolated struct LocationSlot: Equatable, Sendable {
        let name: String
    }

    nonisolated struct Assignment: Equatable, Sendable {
        let spoolId: Int
        let spoolLabel: String
        let locationName: String
    }

    nonisolated enum Target: Equatable, Sendable {
        case spool
        case location
    }

    nonisolated enum Event: Equatable, Sendable {
        case beganScanning(Target)
        case cancelledScan
        case gotSpool(SpoolSlot)
        case gotLocation(LocationSlot)
        case clearedSpool
        case clearedLocation
        case assignmentSucceeded
        case assignmentFailed
    }

    nonisolated enum Effect: Equatable, Sendable {
        case none
        /// The auto-chain: a spool arrived and no shelf is held yet.
        case startLocationScan
        /// Both slots are filled — the caller performs the write and reports
        /// back with `.assignmentSucceeded` or `.assignmentFailed`.
        case commit(Assignment)
    }

    private(set) var spool: SpoolSlot?
    private(set) var location: LocationSlot?
    private(set) var scanning: Target?
    private(set) var assignments: [Assignment] = []

    /// The single source of guidance. Everything the sheet tells the user comes
    /// from here, so there is exactly one place where "what do I do next" is
    /// decided.
    var statusLine: String {
        if let scanning {
            return scanning == .spool
                ? "Hold your iPhone near a spool tag"
                : "Hold your iPhone near a location tag"
        }
        switch (spool, location) {
        case (nil, nil):
            return "Present a spool tag, or choose a spool"
        case (let spool?, nil):
            return "\(spool.label) · now present a location tag"
        case (nil, let location?):
            if let last = assignments.last {
                return "Assigned \(last.spoolLabel) to \(last.locationName) · present the next spool"
            }
            return "\(location.name) · present a spool tag, or choose a spool"
        case (let spool?, let location?):
            return "Assigning \(spool.label) to \(location.name)…"
        }
    }

    @discardableResult
    static func reduce(_ state: inout LocationAssignmentState, _ event: Event) -> Effect {
        switch event {
        case .beganScanning(let target):
            state.scanning = target
            return .none

        case .cancelledScan:
            state.scanning = nil
            return .none

        case .gotSpool(let slot):
            state.scanning = nil
            state.spool = slot
            guard let location = state.location else { return .startLocationScan }
            return .commit(Assignment(
                spoolId: slot.id, spoolLabel: slot.label, locationName: location.name
            ))

        case .gotLocation(let slot):
            state.scanning = nil
            state.location = slot
            guard let spool = state.spool else { return .none }
            return .commit(Assignment(
                spoolId: spool.id, spoolLabel: spool.label, locationName: slot.name
            ))

        case .clearedSpool:
            state.spool = nil
            return .none

        case .clearedLocation:
            state.location = nil
            return .none

        case .assignmentSucceeded:
            if let spool = state.spool, let location = state.location {
                state.assignments.append(Assignment(
                    spoolId: spool.id, spoolLabel: spool.label, locationName: location.name
                ))
            }
            // The shelf stays. That is the whole point.
            state.spool = nil
            return .none

        case .assignmentFailed:
            // Both slots survive so the user can simply try again — clearing
            // them would make a transient server failure cost two scans.
            return .none
        }
    }
}
