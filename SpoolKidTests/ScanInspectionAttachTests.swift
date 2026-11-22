//
//  ScanInspectionAttachTests.swift
//  SpoolKidTests
//
//  Purpose: Every unified-read result leaves `NFCManager` through one funnel,
//  which attaches what the scan learned about the tag. CoreNFC cannot run
//  here, so these pin the one part of the funnel that can: attaching the
//  inspection changes nothing else about the result. The hub routes on that
//  result, so a failed chip query has to publish exactly what it published
//  before Inspect Tag existed.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing

@testable import SpoolKid

struct ScanInspectionAttachTests {

    // MARK: - Fixtures

    private let record = NDEFRecordSnapshot(
        typeNameFormat: 2,
        type: Data("application/json".utf8),
        identifier: Data(),
        payload: Data(#"{"protocol":"openspool"}"#.utf8)
    )

    private func inspection(
        family: TagInspection.Family = .mifareUltralight,
        records: [NDEFRecordSnapshot] = [],
        rawMemory: TagInspection.RawMemory? = nil
    ) -> TagInspection {
        TagInspection(
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            family: family,
            uid: [0x04, 0xA2, 0x3F, 0x1A, 0xB2, 0x5C, 0x80],
            icManufacturerCode: nil,
            ndef: .init(access: .readWrite, capacity: 496, messageLength: 212, records: records),
            rawMemory: rawMemory
        )
    }

    private var openSpoolResult: ScanResult {
        ScanResult(
            cardUID: "04a23f1ab25c80",
            tagData: FilamentTagData(
                material: "PLA", brand: "Generic", colorHex: "FF0000",
                minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 60, maxBedTemp: 60
            ),
            format: .openSpool,
            url: URL(string: "https://x.test"),
            tagSnapshot: .ndef([record])
        )
    }

    // MARK: - Tests

    @Test func nilInspectionLeavesResultUnchanged() {
        let out = NFCManager.attaching(nil, chip: nil, to: openSpoolResult)
        #expect(out.inspection == nil)
    }

    @Test func aFailedChipQueryChangesOnlyTheInspection() {
        let r = openSpoolResult
        let insp = inspection(records: [record])

        let out = NFCManager.attaching(insp, chip: nil, to: r)

        #expect(out.cardUID == r.cardUID)
        #expect(out.format == r.format)
        #expect(out.url == r.url)
        #expect(out.tagSnapshot == r.tagSnapshot)
        #expect(out.isBlankTag == r.isBlankTag)
        #expect(out.locationTag == r.locationTag)
        #expect(out.inspection == insp)
        #expect(out.inspection?.chip == nil)
    }

    @Test func chipReplyIsKept() {
        let chip = TagInspection.Chip(getVersion: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03])

        let out = NFCManager.attaching(inspection(), chip: chip, to: openSpoolResult)

        #expect(out.inspection?.chip == chip)
    }

    @Test func iso15693BlockSizeSetsRawUnitSize() {
        let memory = TagInspection.RawMemory(firstUnit: 0, unitSize: 4, bytes: [UInt8](repeating: 0, count: 16))
        let chip = TagInspection.Chip(icReference: 0x01, blockSize: 8, totalBlocks: 80)
        let result = ScanResult(cardUID: "e004010812a9c3f1", tagData: nil, format: nil)

        let iso = NFCManager.attaching(
            inspection(family: .iso15693, rawMemory: memory), chip: chip, to: result
        )
        let ntag = NFCManager.attaching(
            inspection(family: .mifareUltralight, rawMemory: memory), chip: chip, to: result
        )

        #expect(iso.inspection?.rawMemory?.unitSize == 8)
        #expect(ntag.inspection?.rawMemory?.unitSize == 4)
    }

    @Test func unrecognisedRecordsTravelWithoutASnapshot() {
        let r = ScanResult(cardUID: "04aa", tagData: nil, format: nil)

        let out = NFCManager.attaching(inspection(records: [record]), chip: nil, to: r)

        #expect(out.tagSnapshot == nil)
        #expect(out.inspection?.ndef?.records.count == 1)
    }
}
