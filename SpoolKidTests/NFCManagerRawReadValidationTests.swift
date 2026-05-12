import Foundation
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
