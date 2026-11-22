//
//  FilaManTagWriteWiringTests.swift
//  SpoolKidTests
//
//  Purpose: A FilaMan tag write is ONE PATCH carrying the merged custom_fields
//  and rfid_uid, through the stubbed transport.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

/// An extension of `ServerWebPageWiringTests` so it shares that suite's
/// serialization: `StubURLProtocol.handler` is one global.
extension ServerWebPageWiringTests {
    private static let spoolJSON = """
    {"id":3,"filament_id":2,"status_id":1,"lot_number":null,"rfid_uid":null,
     "external_id":null,"location_id":null,"purchase_date":null,"purchase_price":null,
     "stocked_in_at":null,"last_used_at":null,"initial_total_weight_g":1000.0,
     "empty_spool_weight_g":0.0,"remaining_weight_g":1000.0,"spool_outer_diameter_mm":null,
     "spool_width_mm":null,"spool_material":null,"low_weight_threshold_g":50,
     "created_at":"2026-08-18T00:14:00","custom_fields":{"spoolman_id":3}}
    """

    private func tagStub(log: StubRequestLog) {
        StubURLProtocol.handler = { request in
            log.record(request)
            return .init(status: 200, contentType: "application/json", body: Self.spoolJSON)
        }
    }

    @Test func patchSpoolTagsSendsOneMergedPatch() async {
        let log = StubRequestLog()
        tagStub(log: log)

        let ok = await FilaManService(session: StubURLProtocol.session()).patchSpoolTags(
            spoolId: 3, cardUIDs: ["BB"], rfid: .set("BB"), baseUrl: StubURLProtocol.baseUrl
        )

        #expect(ok)
        let patches = log.entries.filter { $0.method == "PATCH" }
        #expect(patches.count == 1)
        let body = patches.first?.body
        let fields = body?["custom_fields"] as? [String: Any]
        #expect(fields?["spoolman_id"] as? Int == 3)
        #expect(fields?["card_uids"] as? String == "BB")
        #expect(body?["rfid_uid"] as? String == "bb")
    }

    @Test func patchSpoolTagsClearSendsNullAndKeepsCustomFieldsOut() async {
        let log = StubRequestLog()
        tagStub(log: log)

        let ok = await FilaManService(session: StubURLProtocol.session()).patchSpoolTags(
            spoolId: 3, cardUIDs: nil, rfid: .clear, baseUrl: StubURLProtocol.baseUrl
        )

        #expect(ok)
        let patches = log.entries.filter { $0.method == "PATCH" }
        #expect(patches.count == 1)
        #expect(patches.first?.body?["rfid_uid"] is NSNull)
        #expect(patches.first?.body?["custom_fields"] == nil)
    }

    @Test func patchSpoolTagsWithNothingToDoSendsNothing() async {
        let log = StubRequestLog()
        tagStub(log: log)

        let ok = await FilaManService(session: StubURLProtocol.session()).patchSpoolTags(
            spoolId: 3, cardUIDs: nil, rfid: .keep, baseUrl: StubURLProtocol.baseUrl
        )

        #expect(ok)
        #expect(log.entries.isEmpty)
    }
}
