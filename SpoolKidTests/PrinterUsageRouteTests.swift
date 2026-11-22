//
//  PrinterUsageRouteTests.swift
//  SpoolKidTests
//
//  Purpose: Which usage counter the printer reports to, against the app's
//  own backend. Only then is a printer tag offered for the Library.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct PrinterUsageRouteTests {
    private let spoolman = "http://192.168.20.31:7912"
    private let filaman = "http://192.168.20.40:8000"
    private func target(_ kind: String, _ server: String) -> String { "\(kind)|\(ServerAddress.identity(of: server))" }

    @Test func spoolmanBackendAndSameSpoolman() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("spoolman", spoolman), spoolmanServer: spoolman + "/", filamanServer: nil) == .spoolman)
    }

    @Test func differentSpoolmanIsNoRoute() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("spoolman", spoolman), spoolmanServer: "http://192.168.20.33:7912", filamanServer: nil) == nil)
    }

    @Test func localLibraryIsNoRoute() {
        #expect(PrinterUsageRoute.route(connectionTarget: "local", spoolmanServer: spoolman, filamanServer: filaman) == nil)
    }

    @Test func filamanBackendAndFilaManComponent() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("filaman", filaman), spoolmanServer: nil, filamanServer: filaman) == .filaman)
    }

    @Test func spoolmanCompatOnFilaManCountsAsSpoolman() {
        // FilaMan's Spoolman-compatible API lives under /spoolman.
        #expect(PrinterUsageRoute.route(connectionTarget: target("filaman", filaman), spoolmanServer: filaman + "/spoolman", filamanServer: nil) == .spoolman)
        #expect(PrinterUsageRoute.route(connectionTarget: target("filaman", filaman), spoolmanServer: filaman + "/spoolman/", filamanServer: nil) == .spoolman)
    }

    @Test func aSpoolmanAtSlashSpoolmanIsNotFilaMan() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("spoolman", spoolman), spoolmanServer: spoolman + "/spoolman", filamanServer: nil) == nil)
    }

    @Test func bothSectionsFollowTheBackend() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("filaman", filaman), spoolmanServer: filaman, filamanServer: filaman) == .filaman)
        #expect(PrinterUsageRoute.route(connectionTarget: target("spoolman", spoolman), spoolmanServer: spoolman, filamanServer: spoolman) == .spoolman)
    }

    @Test func aFilaManComponentOnAnotherServerIsNoRoute() {
        #expect(PrinterUsageRoute.route(connectionTarget: target("filaman", filaman), spoolmanServer: nil, filamanServer: "http://192.168.20.41:8000") == nil)
    }
}
