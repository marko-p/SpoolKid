//
//  NDEFURIRecordTests.swift
//  SpoolKidTests
//
//  The scan path's link reading: `NFCManager.firstURL(in:)` must not abort on
//  a corrupt URI record, and must return what CoreNFC's
//  `wellKnownTypeURIPayload()` returned for every record CoreNFC could read.
//

import Testing
import Foundation
import CoreNFC
@testable import SpoolKid

struct NDEFURIRecordTests {

    private func uriRecord(_ payload: [UInt8]) -> NFCNDEFPayload {
        NFCNDEFPayload(format: .nfcWellKnown, type: Data("U".utf8), identifier: Data(), payload: Data(payload))
    }

    private func uriRecord(code: UInt8, _ rest: String) -> NFCNDEFPayload {
        uriRecord([code] + Array(rest.utf8))
    }

    /// CoreNFC is the oracle: these records are ones it reads without raising.
    private func expectSameAsCoreNFC(_ record: NFCNDEFPayload, sourceLocation: SourceLocation = #_sourceLocation) {
        let label = [UInt8](record.payload).map { String(format: "%02X", $0) }.joined(separator: " ")
        let expected = record.wellKnownTypeURIPayload()
        let actual = NFCManager.firstURL(in: [record])
        #expect(actual == expected, "payload \(label)", sourceLocation: sourceLocation)
        #expect(actual?.absoluteString == expected?.absoluteString, "payload \(label)", sourceLocation: sourceLocation)
    }

    // MARK: - Corrupt records

    /// CoreNFC raises `-[__NSCFString appendString:]: nil argument` on this
    /// record (a known prefix code, then bytes that are not UTF-8), which
    /// aborted the app mid-scan.
    @Test func aURIRecordThatIsNotUTF8IsNoLink() {
        #expect(NFCManager.firstURL(in: [uriRecord([0x04, 0xFF, 0x61])]) == nil)
        #expect(NFCManager.firstURL(in: [uriRecord([0x00, 0xFF, 0x61])]) == nil)
        #expect(NFCManager.firstURL(in: [uriRecord([0x04, 0x61, 0xC3])]) == nil)
    }

    @Test func aCorruptURIRecordDoesNotHideALaterLink() {
        let records = [uriRecord([0x04, 0xFF, 0x61]), uriRecord(code: 0x04, "3dtag.org/s/abc")]
        #expect(NFCManager.firstURL(in: records)?.absoluteString == "https://3dtag.org/s/abc")
    }

    // MARK: - Valid links unchanged

    /// What `ndefRecords` writes for an OpenPrintTag URL comes back as CoreNFC read it.
    @Test func linksSpoolKidWritesReadAsBefore() throws {
        let mime = Data([0xA0])
        for link in [
            "https://3dtag.org/s/abc", "https://www.prusa3d.com/product/x?y=1#z",
            "http://192.168.20.31:7912/spool/show/5", "https://spoolman.local/spool/show/42",
            "https://a.com/x y", "https://example.com/grün", "https://bücher.de/x",
            "tel:+123", "mailto:a@b.c", "urn:nfc:x", "custom:thing", "HTTPS://A.COM/X",
        ] {
            let records = NFCManager.ndefRecords(mimePayload: mime, mimeType: "application/vnd.openprinttag", urlString: link)
            let uri = try #require(records.first, "\(link)")
            #expect(NFCManager.firstURL(in: records) == uri.wellKnownTypeURIPayload(), "\(link)")
            expectSameAsCoreNFC(uri)
        }
    }

    /// The link on every factory ELEGOO tag (`ElegooPayload.factoryLinkPages`).
    @Test func theElegooFactoryLink() {
        let record = uriRecord(code: 0x02, "elegoo.com")
        #expect(NFCManager.firstURL(in: [record]) == URL(string: "https://www.elegoo.com"))
        expectSameAsCoreNFC(record)
    }

    @Test func everyPrefixCodeReadsAsCoreNFCReadsIt() {
        for code in UInt8(0x00)...0x23 {
            expectSameAsCoreNFC(uriRecord(code: code, "x"))
            expectSameAsCoreNFC(uriRecord(code: code, "a.com/p?q=1#f"))
        }
    }

    /// Text `URL(string:)` percent-encodes or rejects comes back the same way.
    @Test func unusualTextReadsAsCoreNFCReadsIt() {
        for rest in [
            "a b", "a.com/x y", "a.com/%20x", "a.com/%zz", "a.com/{x}[y]", "a.com/a\\b",
            "a.com/\"<>", "a.com/\n", "a.com/\tx", "a.com\u{0}x", "a.com/🙂", "[", " ", "/",
        ] {
            expectSameAsCoreNFC(uriRecord(code: 0x04, rest))
        }
        for rest in ["grün|x", "#", "/path", ":x", " ", "\u{0}"] {
            expectSameAsCoreNFC(uriRecord(code: 0x00, rest))
        }
        expectSameAsCoreNFC(uriRecord([0x04, 0xEF, 0xBB, 0xBF] + Array("a.com".utf8)))
    }

    /// A code the NFC Forum reserves (0x24–0xFF) is read as no prefix, and a
    /// record with nothing after its code holds no link — both as CoreNFC did.
    @Test func reservedCodesAndEmptyRecordsReadAsCoreNFCReadsThem() {
        for code: UInt8 in [0x24, 0x7F, 0x99, 0xFE, 0xFF] {
            expectSameAsCoreNFC(uriRecord(code: code, "https://a.com/x"))
        }
        #expect(NFCManager.firstURL(in: [uriRecord(code: 0x24, "abc")])?.absoluteString == "abc")
        for code in UInt8(0x00)...0x23 {
            expectSameAsCoreNFC(uriRecord([code]))
        }
        expectSameAsCoreNFC(uriRecord([]))
        #expect(NFCManager.firstURL(in: [uriRecord([0x04])]) == nil)
    }

    /// Only a well-known `U` record is a link, as with CoreNFC.
    @Test func otherRecordsAreNoLink() {
        let payload = Data([0x04] + Array("a.com".utf8))
        for (format, type) in [
            (NFCTypeNameFormat.media, "U"), (.nfcExternal, "U"), (.nfcWellKnown, "u"),
            (.nfcWellKnown, "T"), (.nfcWellKnown, "Sp"), (.absoluteURI, "https://a.com"),
        ] {
            let record = NFCNDEFPayload(format: format, type: Data(type.utf8), identifier: Data(), payload: payload)
            #expect(NFCManager.firstURL(in: [record]) == nil, "\(format.rawValue) \(type)")
            expectSameAsCoreNFC(record)
        }
    }
}
