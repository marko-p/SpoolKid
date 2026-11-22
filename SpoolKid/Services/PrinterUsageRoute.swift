//
//  PrinterUsageRoute.swift
//  SpoolKid
//
//  Purpose: Which usage counter the printer reports each print's use to,
//  when that counter is SpoolKid's own backend:
//  - Moonraker's Spoolman integration (`[spoolman] server`), which FilaMan's
//    Spoolman-compatible API also answers, so its ids are the backend's;
//  - FilaMan's Moonraker component (`[filaman] server`), built from its
//    README only (GPLv3, clean-room). Only `server` is read, never `api_key`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum PrinterUsageRoute: Equatable, Sendable {
    case spoolman, filaman

    /// Nil when the printer counts usage somewhere else, or nowhere the app
    /// can see. `connectionTarget` is the store's `kind|identity`.
    static func route(connectionTarget: String, spoolmanServer: String?, filamanServer: String?) -> PrinterUsageRoute? {
        guard let separator = connectionTarget.firstIndex(of: "|") else { return nil }
        let kind = connectionTarget[..<separator]
        let identity = connectionTarget[connectionTarget.index(after: separator)...]
        if kind == "filaman" {
            if let filamanServer, identity == ServerAddress.identity(of: filamanServer) { return .filaman }
            // FilaMan's Spoolman-compatible API is served under /spoolman.
            if let spoolmanServer, ServerAddress.identity(of: spoolmanServer) == identity + "/spoolman" { return .spoolman }
        }
        return PrinterService.sharesSpoolman(printerServer: spoolmanServer, connectionTarget: connectionTarget) ? .spoolman : nil
    }
}
