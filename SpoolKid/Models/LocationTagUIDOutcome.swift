//
//  LocationTagUIDOutcome.swift
//  SpoolKid
//
//  Purpose: What mirroring a location tag's UID onto the backend's own location
//  row amounted to. Three outcomes, not a Bool: "this backend has no field for
//  it" is a different answer from "the field exists and the write failed", and
//  a Bool collapses one of them into a lie either way — `true` claims a write
//  two of three backends cannot perform, `false` reports a failure where there
//  was nothing to attempt.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum LocationTagUIDOutcome: Equatable, Sendable {
    /// This backend has no location-tag field. Nothing was attempted, and
    /// nothing is missing — the device-local registry is the record.
    case unsupported
    case written
    case failed(String)

    /// What to tell the user, or nil when there is nothing worth saying.
    /// `unsupported` is deliberately silent: a location tag works on every
    /// backend, and the mirror is interop for the backend's other clients.
    var note: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}
