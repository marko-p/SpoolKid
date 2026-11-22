import Foundation
import CoreNFC
import Testing
@testable import SpoolKid

struct NFCManagerRawReadValidationTests {
    @Test func rawReadOrderPrefersElegooBeforeAnycubicACE() {
        let order = NFCManager.rawReadAttemptOrder
        #expect(order.count == 2)
        #expect(isElegoo(order[0]))
        #expect(isAnycubicACE(order[1]))
    }

    @Test func fallsBackToACEAfterElegooFailure() {
        #expect(NFCManager.shouldTryACEFallback(afterElegooFailure: true))
        #expect(!NFCManager.shouldTryACEFallback(afterElegooFailure: false))
    }

    @Test func stopsAfterElegooSuccess() {
        let action = NFCManager.rawReadFollowupAction(
            elegooReadSucceeded: true,
            shouldTryACEFallback: true
        )
        #expect(isStop(action))
    }

    @Test func followsACEPathAfterElegooFailure() {
        let action = NFCManager.rawReadFollowupAction(
            elegooReadSucceeded: false,
            shouldTryACEFallback: true
        )
        #expect(isTryAnycubicACE(action))
    }

    @Test func emitsUIDOnlyWhenNoFallbackPathRemains() {
        let action = NFCManager.rawReadFollowupAction(
            elegooReadSucceeded: false,
            shouldTryACEFallback: false
        )
        #expect(isEmitUIDOnly(action))
    }

    @Test func acceptsExact16ByteMifareReadPayload() {
        let payload = Data(repeating: 0xAA, count: 16)
        #expect(NFCManager.isValidRawReadResponse(payload))
    }

    @Test func rejectsShortMifareReadPayload() {
        let nakLikePayload = Data([0x00])
        #expect(!NFCManager.isValidRawReadResponse(nakLikePayload))
    }

    @Test func rejectsLongMifareReadPayload() {
        let payload = Data(repeating: 0xAA, count: 17)
        #expect(!NFCManager.isValidRawReadResponse(payload))
    }

    /// A real ELEGOO tag is two things at once: an ordinary NDEF message whose
    /// only record is a link to elegoo.com, and a filament block at page 16,
    /// past that message's terminator. A reader that accepts the link first
    /// never reaches the block — which is what every scan of a real ELEGOO
    /// spool did until 2026-09-14. Tester dump, Elegoo PLA dark blue,
    /// 2026-09-10 (the same bytes as `ElegooPayloadTests`' fixture, which
    /// that file keeps private).
    @Test func aRealElegooTagIsALinkOnTheNDEFLayerAndABlockOnRawPages() throws {
        let hex = "53CC7A6D0530000431480000E11012000103A00C34030FD1010B5502656C65676F6F2E636F6DFE0000000000000000000000000000000000000000000000000036EEEEEEEE0000000080766500000000106DD7FF00BE00E60000000000AF03E80036C800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000BD040000FF000500000000000000000000"
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }

        // Page 3 is a standard NDEF capability container, so iOS reads the message.
        #expect(Array(bytes[12..<16]) == [0xE1, 0x10, 0x12, 0x00])

        // Page 4: lock-control TLV (5 bytes), then NDEF TLV 03 0F holding 15 bytes.
        #expect(Array(bytes[16..<21]) == [0x01, 0x03, 0xA0, 0x0C, 0x34])
        #expect(Array(bytes[21..<23]) == [0x03, 0x0F])
        let message = try #require(NFCNDEFMessage(data: Data(bytes[23..<38])))
        #expect(message.records.count == 1)
        #expect(message.records.first?.wellKnownTypeURIPayload()?.host == "www.elegoo.com")

        // The block sits past the message's terminator.
        #expect(bytes[38] == 0xFE)

        // The same tag decodes as ELEGOO from exactly the buffer `tryElegooRead`
        // builds: pages 4-35, indexed from page 0, pages 0-3 left zero.
        var readWindow = [UInt8](repeating: 0, count: 36 * ElegooPayload.bytesPerPage)
        readWindow.replaceSubrange(16..<144, with: bytes[16..<144])
        let decoded = try #require(ElegooPayload.decode(from: readWindow))
        #expect(decoded.material == "PLA")
    }
}

private func isElegoo(_ attempt: NFCManager.RawReadFormatAttempt) -> Bool {
    switch attempt {
    case .elegoo: return true
    case .anycubicACE: return false
    }
}

private func isAnycubicACE(_ attempt: NFCManager.RawReadFormatAttempt) -> Bool {
    switch attempt {
    case .anycubicACE: return true
    case .elegoo: return false
    }
}

private func isStop(_ action: NFCManager.RawReadFollowupAction) -> Bool {
    switch action {
    case .stop: return true
    case .tryAnycubicACE, .emitUIDOnly: return false
    }
}

private func isTryAnycubicACE(_ action: NFCManager.RawReadFollowupAction) -> Bool {
    switch action {
    case .tryAnycubicACE: return true
    case .stop, .emitUIDOnly: return false
    }
}

private func isEmitUIDOnly(_ action: NFCManager.RawReadFollowupAction) -> Bool {
    switch action {
    case .emitUIDOnly: return true
    case .stop, .tryAnycubicACE: return false
    }
}
