//
//  LocalModeCopy.swift
//  SpoolKid
//
//  Purpose: Single source of truth for local-mode transparency copy.
//  Shared by Settings, welcome, and Library footer surfaces (specs 057–059).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Bench-readable, factual copy explaining the on-device Library. The cap
/// number is derived from `Entitlement` so it cannot drift from the quota.
enum LocalModeCopy {
    static let storageExplanation = "Your spools, filaments, manufacturers, and locations are saved only on this iPhone."

    static let notAReplacement = "Local mode is not a replacement for Spoolman: you can't connect your printers to it."

    static let dataLossDisclaimer = "This data lives only on your device and isn't backed up. If the app is deleted, or the device is lost or reset, the library is gone — SpoolKid can't recover it. Connect a Spoolman server to keep your library on your own infrastructure."

    static let spoolmanBenefit = "Connect your own Spoolman server for more capacity and to sync with your printers."

    static var capSummary: String {
        let limit = Entitlement.current.limit(for: .spools)
        return "Your library holds up to \(limit.formatted()) of each: spools, filaments, and manufacturers."
    }
}
