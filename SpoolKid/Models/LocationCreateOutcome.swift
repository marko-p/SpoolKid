//
//  LocationCreateOutcome.swift
//  SpoolKid
//
//  Purpose: What `addLocation` actually did. Deliberately not a `Bool`:
//  FilaMan creates a real row, while Spoolman and the on-device Library have
//  no endpoint that can — a location exists there only while a spool names it.
//  Reporting both as `true` is the silent-success failure this codebase has
//  paid for nine times (see filaman-api.md).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum LocationCreateOutcome: Equatable, Sendable {
    /// A row now exists on the backend.
    case created
    /// The backend already had this location; nothing was written.
    case alreadyExists
    /// This backend cannot hold a location with no spools. The name lives in
    /// the device-local registry until an assignment puts it on the server.
    case registeredOnDeviceOnly
    case failed(String)

    var isSuccess: Bool {
        if case .failed = self { return false }
        return true
    }

    /// The one home for this feature's outcome copy. `storageNoun` is
    /// `BackendCapabilities.storageNoun`, which reads "Spoolman", "FilaMan" or
    /// "your library" and is written to sit mid-sentence.
    func note(locationName: String, storageNoun: String) -> String? {
        switch self {
        case .created, .alreadyExists:
            return nil
        case .registeredOnDeviceOnly:
            return "\(locationName) is saved on this device. It appears in \(storageNoun) once you assign a spool to it."
        case .failed(let reason):
            return reason
        }
    }

    /// The shared guard every backend runs before it tries to create anything:
    /// blank names are refused, known names are reported as such, and `nil`
    /// means "go ahead". Returning `nil` rather than a `.proceed` case keeps
    /// the caller's happy path un-nested.
    static func precheck(name: String, existing: [String]) -> LocationCreateOutcome? {
        let trimmed = LocationName.trimmed(name)
        guard !trimmed.isEmpty else { return .failed("A location needs a name.") }

        let key = LocationName.normalizedKey(trimmed)
        if existing.contains(where: { LocationName.normalizedKey($0) == key }) {
            return .alreadyExists
        }
        return nil
    }
}
