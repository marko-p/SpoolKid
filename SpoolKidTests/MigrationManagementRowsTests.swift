//
//  MigrationManagementRowsTests.swift
//  SpoolKidTests
//
//  Purpose: Issue #24 — which Migration Management rows the Backend page
//  offers, read from capabilities and the Tag Identity targets.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct MigrationManagementRowsTests {
    @Test func spoolmanTwoStoresBothOn() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .spoolman, available: [.cardUIDs, .spoolmanTags], targets: [.cardUIDs, .spoolmanTags]
        ) == [.record, .intoCardUIDs, .intoSpoolmanTags])
    }

    @Test func spoolLinkOffHidesTheCardUIDsCopy() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .spoolman, available: [.cardUIDs, .spoolmanTags], targets: [.spoolmanTags]
        ) == [.record, .intoSpoolmanTags])
    }

    @Test func spoolmanTagsOffHidesTheNativeCopy() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .spoolman, available: [.cardUIDs, .spoolmanTags], targets: [.cardUIDs]
        ) == [.record, .intoCardUIDs])
    }

    @Test func olderSpoolmanOffersOnlyTheRecord() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .spoolman, available: [.cardUIDs], targets: [.cardUIDs]
        ) == [.record])
    }

    @Test func filamanOffersOnlyTheRecord() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .filaman, available: [.cardUIDs, .filamanTags], targets: [.cardUIDs]
        ) == [.record])
    }

    @Test func onDeviceLibraryHasNoSection() {
        #expect(SpoolmanSettingsView.migrationRows(
            capabilities: .local, available: [.cardUIDs], targets: [.cardUIDs]
        ).isEmpty)
    }
}
