//
//  MigrationPlannerTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the M3 migration planning rules: empty server → auto-create,
//  vendor name matching (trimmed/case-insensitive), filament matching on the
//  normalized five-field key (diameter/weight bucketed), nil vs empty string
//  normalization, spool matching by carried filament key, and the create/conflict
//  counts.
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
struct MigrationPlannerTests {

    // MARK: - Empty server

    @Test func emptyServerProducesAllCreateActions() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let localFilaments = [localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)]
        let key = FilamentMatchKey(localFilaments[0], localVendors: localVendors)
        let localSpools = [localSpool(id: 1, filamentId: 1, key: key)]

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: localFilaments,
            localSpools: localSpools,
            serverVendors: [],
            serverFilaments: [],
            serverSpools: []
        )

        #expect(plan.vendors.count == 1)
        #expect(plan.vendors[0].candidates.isEmpty)
        #expect(plan.vendors[0].resolution == .create)
        #expect(plan.filaments[0].resolution == .create)
        #expect(plan.spools[0].resolution == .create)
        #expect(plan.conflictCount == 0)
        #expect(plan.createCount == 3)
    }

    // MARK: - Vendor matching

    @Test func vendorNameMatchIsCaseAndWhitespaceInsensitive() {
        let local = localVendor(id: 1, name: "  Bambu Lab  ")
        let server = vendor(id: 10, name: "bambu lab")

        let plan = MigrationPlanner.plan(
            localVendors: [local],
            localFilaments: [],
            localSpools: [],
            serverVendors: [server],
            serverFilaments: [],
            serverSpools: []
        )

        #expect(plan.vendors[0].candidates.count == 1)
        #expect(plan.vendors[0].candidates[0].id == 10)
        #expect(plan.vendors[0].resolution == .reuse(serverId: 10))
        #expect(plan.conflictCount == 1)
        #expect(plan.createCount == 0)
    }

    @Test func differingVendorNameIsCreate() {
        let plan = MigrationPlanner.plan(
            localVendors: [localVendor(id: 1, name: "Bambu Lab")],
            localFilaments: [],
            localSpools: [],
            serverVendors: [vendor(id: 10, name: "Polymaker")],
            serverFilaments: [],
            serverSpools: []
        )

        #expect(plan.vendors[0].candidates.isEmpty)
        #expect(plan.vendors[0].resolution == .create)
        #expect(plan.conflictCount == 0)
    }

    // MARK: - Filament matching

    @Test func filamentEqualOnAllFiveKeysIsConflict() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.count == 1)
        #expect(plan.filaments[0].candidates[0].id == 20)
        #expect(plan.filaments[0].resolution == .reuse(serverId: 20))
    }

    @Test func differingMaterialPreventsFilamentMatch() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PETG", diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.isEmpty)
        #expect(plan.filaments[0].resolution == .create)
    }

    @Test func differingDiameterAtSecondDecimalPreventsMatch() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PLA", diameter: 1.76, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.isEmpty)
    }

    @Test func differingWeightAtGramPreventsMatch() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1001)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.isEmpty)
    }

    @Test func nilAndEmptyMaterialCompareEqual() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localNilMaterial = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: nil, diameter: 1.75, weight: 1000)
        let localEmptyMaterial = localFilament(id: 2, vendorId: 1, name: "PLA Basic", material: "", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: nil, diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localNilMaterial, localEmptyMaterial],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.count == 1)
        #expect(plan.filaments[1].candidates.count == 1)
    }

    @Test func nilMaterialVersusValueComparesNotEqual() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: nil, diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.isEmpty)
    }

    @Test func missingLocalVendorYieldsEmptyManufacturer() {
        // A local filament whose vendorLocalId points nowhere matches a server
        // filament whose vendor is nil, all other fields equal.
        let localFilament = localFilament(id: 1, vendorId: 999, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: nil, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: [],
            localFilaments: [localFilament],
            localSpools: [],
            serverVendors: [],
            serverFilaments: [serverFilament],
            serverSpools: []
        )

        #expect(plan.filaments[0].candidates.count == 1)
        #expect(plan.filaments[0].candidates[0].id == 20)
    }

    // MARK: - Spool matching

    @Test func spoolMatchesServerSpoolByFilamentKey() {
        let key = FilamentMatchKey(manufacturer: "Bambu Lab", name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let localSpool = localSpool(id: 1, filamentId: 1, key: key)
        let serverFilament = filament(id: 20, vendor: vendor(id: 10, name: "Bambu Lab"), name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverSpool = spool(id: 30, filament: serverFilament)

        let plan = MigrationPlanner.plan(
            localVendors: [],
            localFilaments: [],
            localSpools: [localSpool],
            serverVendors: [vendor(id: 10, name: "Bambu Lab")],
            serverFilaments: [serverFilament],
            serverSpools: [serverSpool]
        )

        #expect(plan.spools[0].candidates.count == 1)
        #expect(plan.spools[0].candidates[0].id == 30)
        #expect(plan.spools[0].resolution == .reuse(serverId: 30))
    }

    @Test func multipleMatchingServerSpoolsDefaultToFirst() {
        let key = FilamentMatchKey(manufacturer: "Bambu Lab", name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let localSpool = localSpool(id: 1, filamentId: 1, key: key)
        let serverFilament = filament(id: 20, vendor: vendor(id: 10, name: "Bambu Lab"), name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverSpool1 = spool(id: 30, filament: serverFilament)
        let serverSpool2 = spool(id: 31, filament: serverFilament)

        let plan = MigrationPlanner.plan(
            localVendors: [],
            localFilaments: [],
            localSpools: [localSpool],
            serverVendors: [],
            serverFilaments: [],
            serverSpools: [serverSpool1, serverSpool2]
        )

        #expect(plan.spools[0].candidates.count == 2)
        #expect(plan.spools[0].resolution == .reuse(serverId: 30))
    }

    @Test @MainActor func nonMatchingFilamentKeyProducesSpoolCreate() {
        let key = FilamentMatchKey(manufacturer: "Bambu Lab", name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let localSpool = localSpool(id: 1, filamentId: 1, key: key)
        let serverFilament = filament(id: 20, vendor: vendor(id: 10, name: "Polymaker"), name: "PolyTerra", material: "PLA", diameter: 1.75, weight: 1000)

        let plan = MigrationPlanner.plan(
            localVendors: [],
            localFilaments: [],
            localSpools: [localSpool],
            serverVendors: [],
            serverFilaments: [],
            serverSpools: [spool(id: 30, filament: serverFilament)]
        )

        #expect(plan.spools[0].candidates.isEmpty)
        #expect(plan.spools[0].resolution == .create)
    }

    // MARK: - Counts

    @Test func countsPartitionEveryRow() {
        let localVendors = [localVendor(id: 1, name: "Bambu Lab")]
        let serverVendor = vendor(id: 10, name: "bambu lab")
        let localFilament = localFilament(id: 1, vendorId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let serverFilament = filament(id: 20, vendor: serverVendor, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000)
        let key = FilamentMatchKey(localFilament, localVendors: localVendors)
        let localSpool = localSpool(id: 1, filamentId: 1, key: key)
        let serverSpool = spool(id: 30, filament: serverFilament)

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [localFilament],
            localSpools: [localSpool],
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: [serverSpool]
        )

        #expect(plan.conflictCount == 3)
        #expect(plan.createCount == 0)
        #expect(plan.conflictCount + plan.createCount == 3)
    }

    @Test func countsWithMixedCreateAndConflict() {
        let localVendors = [
            localVendor(id: 1, name: "Bambu Lab"),
            localVendor(id: 2, name: "Polymaker")
        ]
        let serverVendor = vendor(id: 10, name: "Bambu Lab")

        let plan = MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: [],
            localSpools: [],
            serverVendors: [serverVendor],
            serverFilaments: [],
            serverSpools: []
        )

        #expect(plan.conflictCount == 1)
        #expect(plan.createCount == 1)
        #expect(plan.conflictCount + plan.createCount == 2)
    }

    @Test func aConflictFlippedToCreateCountsAsACreate() {
        // `createCount` used to be `total - conflictCount`, so a conflict the
        // user flipped to Create was still counted as a reuse — and the review
        // screen under-reported what it was about to upload.
        var plan = MigrationPlanner.plan(
            localVendors: [localVendor(id: 1, name: "Bambu Lab")],
            localFilaments: [],
            localSpools: [],
            serverVendors: [vendor(id: 10, name: "Bambu Lab")],
            serverFilaments: [],
            serverSpools: []
        )
        #expect(plan.createCount == 0)
        #expect(plan.reuseCount == 1)

        plan.vendors[0].resolution = .create

        #expect(plan.createCount == 1)
        #expect(plan.reuseCount == 0)
        // The conflict is still a conflict — it is a match that EXISTS, not a
        // decision about it.
        #expect(plan.conflictCount == 1)
    }

    // MARK: - Helpers

    private func localVendor(id: Int, name: String) -> MigrationLocalVendor {
        MigrationLocalVendor(localId: id, name: name)
    }

    private func localFilament(
        id: Int,
        vendorId: Int? = nil,
        name: String? = nil,
        material: String? = nil,
        diameter: Double? = nil,
        weight: Double? = nil
    ) -> MigrationLocalFilament {
        MigrationLocalFilament(
            localId: id,
            vendorLocalId: vendorId,
            name: name,
            material: material,
            diameter: diameter,
            weight: weight
        )
    }

    private func localSpool(id: Int, filamentId: Int, key: FilamentMatchKey) -> MigrationLocalSpool {
        MigrationLocalSpool(localId: id, filamentLocalId: filamentId, filamentKey: key)
    }

    private func vendor(id: Int, name: String) -> Vendor {
        Vendor(id: id, name: name)
    }

    private func filament(
        id: Int,
        vendor: Vendor? = nil,
        name: String? = nil,
        material: String? = nil,
        diameter: Double? = nil,
        weight: Double? = nil
    ) -> Filament {
        Filament(
            id: id,
            name: name,
            material: material,
            vendor: vendor,
            diameter: diameter,
            weight: weight
        )
    }

    private func spool(id: Int, filament: Filament) -> Spool {
        Spool(id: id, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)
    }
}
