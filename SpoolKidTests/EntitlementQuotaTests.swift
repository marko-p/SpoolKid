//
//  EntitlementQuotaTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the local-store quota policy — free-tier is the current
//  entitlement, the single shared cap across the capped entities (spools,
//  filaments, manufacturers; locations are uncapped), premium reserved values,
//  and the at-limit error copy.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct EntitlementQuotaTests {
    @Test func currentEntitlementIsFree() {
        #expect(Entitlement.current == .free)
    }

    @Test func freeTierCapsEveryEntityAtTheSharedLimit() {
        // The capped entities all share the single build-time knob. Locations are
        // uncapped and deliberately not a `QuotaEntity`.
        for entity in [QuotaEntity.spools, .filaments, .vendors] {
            #expect(Entitlement.free.limit(for: entity) == Entitlement.localCapacity)
        }
    }

    @Test func onDeviceLibraryHoldsThousands() {
        #expect(Entitlement.localCapacity == 5000)
    }

    @Test func capSummaryGroupsTheLimitsDigits() {
        #expect(LocalModeCopy.capSummary.contains(5000.formatted()))
    }

    @Test func premiumTierUsesReservedLimits() {
        #expect(Entitlement.premium.limit(for: .spools) == 1000)
        #expect(Entitlement.premium.limit(for: .filaments) == 30000)
        #expect(Entitlement.premium.limit(for: .vendors) == 1000)
    }

    @Test func vendorsAreNamedManufacturers() {
        #expect(QuotaEntity.vendors.displayName == "manufacturers")
    }

    @Test func quotaErrorDescribesLimitAndEntity() {
        let error = QuotaError(entity: .spools, limit: 5000)
        let message = error.errorDescription ?? ""
        #expect(message.contains(5000.formatted()))
        #expect(message.contains("spools"))
    }

    @Test func quotaErrorNamesBothRemedies() {
        // The at-limit message must offer both ways out: delete an existing
        // item, or connect Spoolman for more capacity (spec 060).
        let message = QuotaError(entity: .vendors, limit: 15).errorDescription ?? ""
        #expect(message.lowercased().contains("delete"))
        #expect(message.contains("Spoolman"))
        #expect(message.contains("manufacturers"))
    }
}
