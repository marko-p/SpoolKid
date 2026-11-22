//
//  DeletionImpactTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

struct DeletionImpactTests {

    private func vendor(_ id: Int) -> Vendor { Vendor(id: id, name: "V\(id)") }

    private func filament(_ id: Int, vendor vendorID: Int? = nil) -> Filament {
        Filament(id: id, name: "F\(id)", material: "PLA", vendor: vendorID.map(vendor))
    }

    private func spool(_ id: Int, filament: Filament, archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: filament, archived: archived, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    // MARK: - Filaments

    @Test func filamentWithoutSpoolsHasNoImpact() {
        let impact = DeletionImpact.forFilaments([1], spools: [spool(10, filament: filament(2))])
        #expect(impact.isEmpty)
    }

    @Test func filamentImpactCountsItsSpoolsIncludingArchived() {
        let f1 = filament(1)
        let impact = DeletionImpact.forFilaments([1], spools: [
            spool(10, filament: f1),
            spool(11, filament: f1, archived: true),
            spool(12, filament: filament(2)),
        ])
        #expect(impact.filamentIDs.isEmpty)
        #expect(impact.spoolIDs == [10, 11])
        #expect(impact.archivedSpoolCount == 1)
        #expect(!impact.isEmpty)
    }

    @Test func filamentSelectionUnionsEverySelectedFilamentsSpools() {
        let impact = DeletionImpact.forFilaments([1, 2], spools: [
            spool(10, filament: filament(1)),
            spool(11, filament: filament(2)),
            spool(12, filament: filament(3)),
        ])
        #expect(impact.spoolIDs == [10, 11])
    }

    // MARK: - Vendors

    @Test func vendorWithoutFilamentsHasNoImpact() {
        let impact = DeletionImpact.forVendors([1], filaments: [filament(5, vendor: 2)], spools: [])
        #expect(impact.isEmpty)
    }

    @Test func vendorImpactChainsFilamentsToTheirSpools() {
        let f5 = filament(5, vendor: 1)
        let f6 = filament(6, vendor: 1)
        let other = filament(7, vendor: 2)
        let impact = DeletionImpact.forVendors([1], filaments: [f5, f6, other], spools: [
            spool(20, filament: f5),
            spool(21, filament: f6, archived: true),
            spool(22, filament: other),
        ])
        #expect(impact.filamentIDs == [5, 6])
        #expect(impact.spoolIDs == [20, 21])
        #expect(impact.archivedSpoolCount == 1)
    }

    @Test func vendorWithFilamentsButNoSpoolsStillHasImpact() {
        let impact = DeletionImpact.forVendors([1], filaments: [filament(5, vendor: 1)], spools: [])
        #expect(impact.filamentIDs == [5])
        #expect(impact.spoolIDs.isEmpty)
        #expect(!impact.isEmpty)
    }

    @Test func filamentWithoutVendorBelongsToNoVendor() {
        let impact = DeletionImpact.forVendors([1], filaments: [filament(5)], spools: [])
        #expect(impact.isEmpty)
    }

    // MARK: - Wording

    @Test func dependentsPhraseForAFilament() {
        let one = DeletionImpact(filamentIDs: [], spoolIDs: [10], archivedSpoolCount: 0)
        #expect(one.dependentsPhrase == "1 spool")
        let many = DeletionImpact(filamentIDs: [], spoolIDs: [10, 11, 12], archivedSpoolCount: 2)
        #expect(many.dependentsPhrase == "3 spools (2 archived)")
    }

    @Test func dependentsPhraseForAVendor() {
        let noSpools = DeletionImpact(filamentIDs: [5], spoolIDs: [], archivedSpoolCount: 0)
        #expect(noSpools.dependentsPhrase == "1 filament")
        let both = DeletionImpact(filamentIDs: [5, 6, 7, 8], spoolIDs: Set(20...30), archivedSpoolCount: 1)
        #expect(both.dependentsPhrase == "4 filaments and 11 spools (1 archived)")
    }

    @Test func refusalMessageNamesTheDependents() {
        let impact = DeletionImpact(filamentIDs: [5, 6], spoolIDs: [20], archivedSpoolCount: 0)
        #expect(impact.refusalMessage(for: "vendor") == "This vendor still has 2 filaments and 1 spool, so it was not deleted.")
    }

    @Test func totalItemCountAddsTheSelectionItself() {
        let impact = DeletionImpact(filamentIDs: [5, 6, 7, 8], spoolIDs: Set(20...30), archivedSpoolCount: 0)
        #expect(impact.totalItemCount(selected: 1) == 16)
        #expect(impact.totalItemCount(selected: 3) == 18)
    }
}
