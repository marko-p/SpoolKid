//
//  LocationTagPayloadTests.swift
//  SpoolKidTests
//
//  Purpose: The location tag's own record — deliberately outside the four
//  filament formats. Decode is strict: an unknown version or a foreign MIME
//  type is refused outright so an unrecognised tag is never mistaken for a
//  location.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationTagPayloadTests {
    private let uuid = UUID(uuidString: "6F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8")!

    @Test func roundTripsThroughItsOwnMimeType() throws {
        let payload = LocationTagPayload(uuid: uuid, name: "Shelf A")

        let data = try #require(payload.encoded())
        let decoded = try #require(LocationTagPayload.decode(payload: data, mimeType: LocationTagPayload.mimeType))

        #expect(decoded == payload)
    }

    @Test func roundTripsANonASCIIName() throws {
        let payload = LocationTagPayload(uuid: uuid, name: "Regál č. 3 — žlutý")

        let data = try #require(payload.encoded())
        let decoded = try #require(LocationTagPayload.decode(payload: data, mimeType: LocationTagPayload.mimeType))

        #expect(decoded.name == "Regál č. 3 — žlutý")
    }

    @Test func rejectsAForeignMimeType() throws {
        let data = try #require(LocationTagPayload(uuid: uuid, name: "Shelf A").encoded())

        #expect(LocationTagPayload.decode(payload: data, mimeType: "application/json") == nil)
        #expect(LocationTagPayload.decode(payload: data, mimeType: nil) == nil)
    }

    @Test func rejectsAVersionItHasNotSeen() throws {
        let json = """
        {"protocol":"spoolkid-location","version":2,"id":"\(uuid.uuidString)","name":"Shelf A"}
        """

        #expect(LocationTagPayload.decode(
            payload: Data(json.utf8), mimeType: LocationTagPayload.mimeType
        ) == nil)
    }

    @Test func rejectsAForeignProtocolAndAMalformedId() throws {
        let wrongProtocol = """
        {"protocol":"something-else","version":1,"id":"\(uuid.uuidString)","name":"Shelf A"}
        """
        let badId = """
        {"protocol":"spoolkid-location","version":1,"id":"not-a-uuid","name":"Shelf A"}
        """
        let blankName = """
        {"protocol":"spoolkid-location","version":1,"id":"\(uuid.uuidString)","name":"   "}
        """

        for json in [wrongProtocol, badId, blankName] {
            #expect(LocationTagPayload.decode(
                payload: Data(json.utf8), mimeType: LocationTagPayload.mimeType
            ) == nil)
        }
    }

    @Test func rejectsGarbageWithoutThrowing() {
        #expect(LocationTagPayload.decode(
            payload: Data([0x00, 0xFF, 0x10]), mimeType: LocationTagPayload.mimeType
        ) == nil)
    }

    @Test func theFilamentCodecDoesNotClaimALocationPayload() throws {
        let data = try #require(LocationTagPayload(uuid: uuid, name: "Shelf A").encoded())

        // Ordering in NFCManager puts the location check first, but the two
        // decoders must also be mutually exclusive on their own — otherwise a
        // reordering elsewhere silently turns a shelf into a filament.
        #expect(TagFormatService.shared.decode(payload: data, mimeType: LocationTagPayload.mimeType) == nil)
    }

    @Test func theTextRecordIsHumanReadable() {
        let payload = LocationTagPayload(uuid: uuid, name: "Shelf A")

        #expect(payload.textRecordString == "SpoolKid location: Shelf A")
    }
}
