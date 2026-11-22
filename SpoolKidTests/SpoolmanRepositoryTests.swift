//
//  SpoolmanRepositoryTests.swift
//  SpoolKidTests
//
//  Purpose: Verifies SpoolmanRepository faithfully forwards the SpoolDataRepository
//  surface to the wrapped SpoolmanService (reads + the synchronous UID lookup).
//  Network-backed write paths are unchanged one-line forwards of already-covered
//  service methods and are not re-tested here.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolmanRepositoryTests {
    // MARK: - cascadeStoppedMessage (Spoolman has no transaction)

    @Test func cascadeStoppedBeforeAnythingSaysNothingWasDeleted() {
        let message = SpoolmanRepository.cascadeStoppedMessage(
            target: "filament", deletedSpools: 0, totalSpools: 3, deletedFilaments: 0, totalFilaments: 0,
            reason: "Failed to delete spool, see server logs for more information."
        )
        #expect(message == "Failed to delete spool, see server logs for more information. Nothing was deleted.")
    }

    @Test func cascadeStoppedMidwaySaysWhatIsAlreadyGone() {
        let message = SpoolmanRepository.cascadeStoppedMessage(
            target: "vendor", deletedSpools: 7, totalSpools: 11, deletedFilaments: 0, totalFilaments: 4,
            reason: "Could not connect to the server"
        )
        #expect(message == "Could not connect to the server. Already deleted: 7 of 11 spools; the vendor was not deleted.")
    }

    @Test func cascadeStoppedAfterSpoolsCountsFilamentsToo() {
        let message = SpoolmanRepository.cascadeStoppedMessage(
            target: "vendor", deletedSpools: 1, totalSpools: 1, deletedFilaments: 1, totalFilaments: 4,
            reason: "Boom."
        )
        #expect(message == "Boom. Already deleted: 1 of 1 spool and 1 of 4 filaments; the vendor was not deleted.")
    }

    @Test func readAccessorsForwardToService() {
        let service = SpoolmanService()
        let repo = SpoolmanRepository(service: service)

        let vendor = Vendor(id: 1, name: "Bambu Lab")
        let filament = Filament(id: 2, name: "PLA Basic", vendor: vendor)
        let spool = Spool(id: 3, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)

        service.vendors = [vendor]
        service.filaments = [filament]
        service.spools = [spool]
        service.locations = ["Shelf A", "Shelf B"]
        service.isLoading = true
        service.errorMessage = "boom"

        #expect(repo.vendors.map(\.id) == [1])
        #expect(repo.filaments.map(\.id) == [2])
        #expect(repo.spools.map(\.id) == [3])
        #expect(repo.locations == ["Shelf A", "Shelf B"])
        #expect(repo.isLoading == true)
        #expect(repo.errorMessage == "boom")
    }

    @Test func findSpoolByCardUIDDelegatesWithNormalization() {
        let service = SpoolmanService()
        let repo = SpoolmanRepository(service: service)
        let filament = Filament(id: 1)
        let matching = Spool(id: 10, filament: filament, extra: ["card_uids": CardUIDsCodec.encode(["04A1B2C3"])], statusId: nil, externalId: nil, purchaseDate: nil)
        let other = Spool(id: 11, filament: filament, lotNr: nil, statusId: nil, externalId: nil, purchaseDate: nil)
        service.spools = [other, matching]

        // Query in a different case + separators; matching goes through
        // SpoolMappingService.normalizeUID inside the wrapped service.
        #expect(repo.findSpool(byCardUID: "04:a1:b2:c3")?.id == 10)
        #expect(repo.findSpool(byCardUID: "DEADBEEF") == nil)
    }

    // MARK: - Filament create requirements (2026-09-24)
    //
    // Probed 2026-08-27: `POST /filament` answers 422 without `density` or
    // `diameter`; name, material and vendor are optional. Migration's
    // pre-flight asks this so the review lists such a row with a Fix button
    // instead of it failing at upload.

    @Test func aFilamentWithDensityAndDiameterNeedsNothing() {
        var draft = FilamentDraft()
        draft.density = 1.24
        draft.diameter = 1.75
        #expect(SpoolmanRepository.missingRequirements(of: draft).isEmpty)
    }

    @Test func densityAndDiameterAreEachRequired() {
        var draft = FilamentDraft()
        #expect(SpoolmanRepository.missingRequirements(of: draft) == [.density, .diameter])
        draft.density = 1.24
        #expect(SpoolmanRepository.missingRequirements(of: draft) == [.diameter])
    }

    @Test func zeroIsNotADensity() {
        var draft = FilamentDraft()
        draft.density = 0
        draft.diameter = 1.75
        #expect(SpoolmanRepository.missingRequirements(of: draft) == [.density])
    }
}
