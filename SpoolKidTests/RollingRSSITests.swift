import Testing
import Foundation
@testable import SpoolKid

struct RollingRSSITests {

    @Test func nothingSeenHasNoStrength() async throws {
        // Not 0 dBm, which reads as "touching the phone" and would sort an
        // unseen peripheral to the top of a nearest-first list.
        #expect(RollingRSSI().average == nil)
    }

    @Test func oneSightingIsItsOwnAverage() async throws {
        var signal = RollingRSSI()
        signal.add(-62)
        #expect(signal.average == -62)
    }

    @Test func theAverageIsTheMeanOfTheWindow() async throws {
        let now = Date()
        var signal = RollingRSSI()
        signal.add(-60, at: now)
        signal.add(-70, at: now.addingTimeInterval(1))
        #expect(signal.average == -65)
    }

    @Test func aHalfIsRoundedNotTruncated() async throws {
        let now = Date()
        var signal = RollingRSSI()
        signal.add(-60, at: now)
        signal.add(-61, at: now.addingTimeInterval(1))
        // -60.5 rounds AWAY from zero, to -61. Pinned because the alternative
        // (truncation, -60) is what a plain Int division would have given.
        #expect(signal.average == -61)
    }

    @Test func samplesOlderThanTheWindowAreForgotten() async throws {
        let now = Date()
        var signal = RollingRSSI()
        signal.add(-90, at: now)
        signal.add(-50, at: now.addingTimeInterval(RollingRSSI.window + 0.1))
        // The stale -90 must not drag the average down: the phone has moved.
        #expect(signal.samples.count == 1)
        #expect(signal.average == -50)
    }

    @Test func aSampleExactlyAtTheEdgeIsKept() async throws {
        let now = Date()
        var signal = RollingRSSI()
        signal.add(-80, at: now)
        signal.add(-60, at: now.addingTimeInterval(RollingRSSI.window))
        #expect(signal.samples.count == 2)
        #expect(signal.average == -70)
    }

    @Test func smoothingSurvivesTheHopBetweenAdvertisements() async throws {
        // The defect this type exists for: two peripherals whose raw readings
        // cross on a single advertisement must not trade places in the list.
        let now = Date()
        var near = RollingRSSI()
        var far = RollingRSSI()
        for (index, pair) in [(-55, -70), (-72, -68), (-54, -71), (-56, -69)].enumerated() {
            let at = now.addingTimeInterval(Double(index) * 0.5)
            near.add(pair.0, at: at)
            far.add(pair.1, at: at)
        }
        // One reading of the near device (-72) is worse than the far one, but
        // the means keep the order.
        #expect(try #require(near.average) > #require(far.average))
    }
}
