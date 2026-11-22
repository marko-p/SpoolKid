//
//  CardUIDsCodecTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct CardUIDsCodecTests {
    @Test func interopRoundTripIsByteIdentical() {
        let wireValue = "\"AABBCCDD,11223344\""
        let parsed = CardUIDsCodec.parse(wireValue)

        #expect(parsed == ["AABBCCDD", "11223344"])
        #expect(CardUIDsCodec.encode(parsed) == wireValue)
    }

    @Test func parseToleratesNil() {
        #expect(CardUIDsCodec.parse(nil) == [])
    }

    @Test func parseToleratesEmptyString() {
        #expect(CardUIDsCodec.parse("") == [])
    }

    @Test func parseToleratesQuotedEmptyString() {
        #expect(CardUIDsCodec.parse("\"\"") == [])
    }

    @Test func parseToleratesUnquotedValue() {
        let parsed = CardUIDsCodec.parse("AABBCCDD,11223344")

        #expect(parsed == ["AABBCCDD", "11223344"])
    }

    @Test func parseNormalizesToUppercase() {
        #expect(CardUIDsCodec.parse("\"aabbCCdd,1122aA33\"") == ["AABBCCDD", "1122AA33"])
    }

    @Test func parseDeduplicatesOrderPreserving() {
        let parsed = CardUIDsCodec.parse("\"AABBCCDD,AABBCCDD,11223344,AABBCCDD\"")

        #expect(parsed == ["AABBCCDD", "11223344"])
    }

    @Test func encodeDeduplicatesUppercasesAndOrdersPreserving() {
        let encoded = CardUIDsCodec.encode(["aabbccdd", "AABBCCDD", "11223344", "11223344"])

        #expect(encoded == "\"AABBCCDD,11223344\"")
    }

    @Test func encodeEmptyListReturnsQuotedEmptyString() {
        #expect(CardUIDsCodec.encode([]) == "\"\"")
    }

    @Test func acceptsThreeOrMoreUIDsWithoutCap() {
        let uids = ["11111111", "22222222", "33333333", "44444444"]
        let wireValue = "\"11111111,22222222,33333333,44444444\""

        #expect(CardUIDsCodec.parse(wireValue) == uids)
        #expect(CardUIDsCodec.encode(uids) == wireValue)
    }

    // MARK: - Bare encoding (Task 18)

    @Test func encodeBareOmitsTheJSONWrapper() {
        #expect(CardUIDsCodec.encodeBare(["AABBCCDD", "11223344"]) == "AABBCCDD,11223344")
    }

    @Test func encodeBareOfEmptyListIsEmptyString() {
        #expect(CardUIDsCodec.encodeBare([]) == "")
    }

    @Test func encodeBareNormalisesAndDeduplicates() {
        #expect(CardUIDsCodec.encodeBare(["aabbccdd", "AABBCCDD", "1122"]) == "AABBCCDD,1122")
    }

    @Test func bothEncodingsParseBackToTheSameUIDs() {
        let uids = ["AABBCCDD", "11223344"]

        #expect(CardUIDsCodec.parse(CardUIDsCodec.encode(uids)) == uids)
        #expect(CardUIDsCodec.parse(CardUIDsCodec.encodeBare(uids)) == uids)
    }

    /// The two encodings must differ in exactly one way — the wrapper — or the
    /// distinction Task 18 exists to draw is not real.
    @Test func theOnlyDifferenceBetweenTheEncodingsIsTheWrapper() {
        let uids = ["AABBCCDD", "11223344"]

        #expect(CardUIDsCodec.encode(uids) == "\"\(CardUIDsCodec.encodeBare(uids))\"")
    }

    // MARK: - Which encoding each backend's CREATE actually puts on the wire (F38)
    //
    // The test above pins that the two forms differ; until F38 nothing pinned
    // that the right one is used. A create carried `card_uids` inside
    // `SpoolDraft.extra`, already encoded by the shared spool form — so FilaMan
    // stored Spoolman's wrapped form, its compat layer wrapped it a second time
    // on read, and a SpoolLink/Snapmaker U1 client saw a double-wrapped value.
    // SpoolKid's own `parse` tolerates both, so only the other client broke.

    @Test func spoolmanCreateWritesTheWrappedForm() {
        let draft = SpoolDraft(filamentId: 1, cardUIDs: ["aabbccdd", "11223344"])
        let extra = SpoolmanPayloadBuilder.spoolPayload(from: draft)["extra"] as? [String: String]

        #expect(extra?["card_uids"] == "\"AABBCCDD,11223344\"")
    }

    @Test func filaManCreateWritesTheBareForm() {
        let draft = SpoolDraft(filamentId: 1, cardUIDs: ["aabbccdd", "11223344"])
        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: draft, location: .ignore, remainingWeight: nil
        )
        let custom = payload["custom_fields"] as? [String: String]

        #expect(custom?["card_uids"] == "AABBCCDD,11223344")
    }

    /// The point of the typed draft field: ONE draft, two wire forms, chosen by
    /// the backend rather than by whichever view built the draft.
    @Test func oneDraftReachesEachBackendInThatBackendsOwnEncoding() {
        let draft = SpoolDraft(filamentId: 1, cardUIDs: ["AABBCCDD"])

        let spoolmanValue = (SpoolmanPayloadBuilder.spoolPayload(from: draft)["extra"]
                             as? [String: String])?["card_uids"]
        let filaManValue = (FilaManPayloadBuilder.spoolCreatePayload(
            from: draft, location: .ignore, remainingWeight: nil
        )["custom_fields"] as? [String: String])?["card_uids"]

        #expect(spoolmanValue == CardUIDsCodec.encode(["AABBCCDD"]))
        #expect(filaManValue == CardUIDsCodec.encodeBare(["AABBCCDD"]))
        #expect(spoolmanValue != filaManValue)
    }

    /// A draft that names no UID list must not touch the field: `nil` means
    /// "leave whatever is there alone", never "clear it".
    @Test func aDraftWithNoCardUIDsLeavesTheFieldAlone() {
        let draft = SpoolDraft(filamentId: 1, extra: .set(["card_uids": "\"AABBCCDD\""]))

        let spoolmanValue = (SpoolmanPayloadBuilder.spoolPayload(from: draft)["extra"]
                             as? [String: String])?["card_uids"]
        let filaManValue = (FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["custom_fields"]
                            as? [String: String])?["card_uids"]

        #expect(spoolmanValue == "\"AABBCCDD\"")
        #expect(filaManValue == "\"AABBCCDD\"")
    }
}
