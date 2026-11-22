//
//  BLEStreamDigestTests.swift
//  SpoolKidTests
//
//  The digest is what a tester reads at the bench instead of hex. If it calls
//  a dead stream promising, or misses the one byte that carries the reading,
//  the tester spends their session on the wrong characteristic and the scale
//  goes back in its box.
//
//  The main fixture is REAL: fifteen frames from the owner's AiLink scale,
//  captured 2026-09-08. Anything the digest claims about them can be checked
//  against the bytes by hand.
//

import Testing
import Foundation
@testable import SpoolKid

struct BLEStreamDigestTests {

    /// The owner's scale, verbatim. Frame layout, for reference:
    /// `A7 | 00 6C 09 EB | seq | 03 82 xx | 6D EA 42 | 02 | checksum | 7A`
    private static let ailink: [Data] = [
        "A7006C09EB7E0382F66DEA4202F47A", "A7006C09EB7F0382F26DEA4202F17A",
        "A7006C09EB7C0382F86DEA4202F47A", "A7006C09EB7D0382E06DEA4202DD7A",
        "A7006C09EB020382E96DEA42026B7A", "A7006C09EB030382D46DEA4202577A",
        "A7006C09EB000382D06DEA4202507A", "A7006C09EB010382DD6DEA42025E7A",
        "A7006C09EB060382DE6DEA4202647A", "A7006C09EB070382D16DEA4202587A",
        "A7006C09EB040382D36DEA4202577A", "A7006C09EB050382D26DEA4202577A",
        "A7006C09EB0A0382DF6DEA4202697A", "A7006C09EB0B0382DE6DEA4202697A",
        "A7006C09EB080382DD6DEA4202657A",
    ].map(Self.bytes)

    private static func bytes(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    private func digest(_ frames: [Data], span: TimeInterval = 2.31) -> BLEStreamDigest {
        BLEStreamDigest.make(characteristic: "0000FFE2", packets: frames, span: span)
    }

    // MARK: - The real scale

    @Test func theRealScaleIsRecognisedAsAFrame() {
        let d = digest(Self.ailink)
        #expect(d.packets == 15)
        #expect(d.frameSize == 15)
        #expect(d.framing == "Frame starts A7, ends 7A")
    }

    /// The checksum is the evidence that this is a protocol and not noise, so
    /// it has to be found without being told where to look.
    @Test func theChecksumByteIsFound() {
        #expect(digest(Self.ailink).checksum == "Byte 13 is a checksum (sum of bytes 1–12) — valid in all 15 packets")
    }

    /// This scale's counter arrives with two bits swapped, so a naive
    /// "increments by one" test misses it and the byte is reported as a second
    /// changing field — which would send a tester looking for two numbers.
    @Test func theSequenceCounterIsFoundEvenWithItsBitsSwapped() {
        #expect(digest(Self.ailink).counter == "Byte 5 counts packets (its low bits arrive swapped)")
    }

    /// Everything above exists to get to this: of fifteen bytes, exactly one
    /// carries the reading.
    @Test func onlyTheReadingIsLeftOver() {
        let d = digest(Self.ailink)
        #expect(d.dataIndices == [8])
        #expect(d.latest == 221)
        #expect(d.low == 208)
        #expect(d.high == 248)
        #expect(d.headline == "A checksummed frame with one changing number. This is the one.")
    }

    @Test func aSingleChangingByteIsFlaggedAsPossiblyTruncated() {
        let d = digest(Self.ailink)
        #expect(d.detail.contains { $0.contains("low byte of a wider number") })
    }

    @Test func theDetailReportsHowMuchWasCapturedAndHowFast() {
        #expect(digest(Self.ailink, span: 2.5).detail.first == "15 packets · 15 bytes each · 6.0/s")
    }

    // MARK: - Streams that are not the weight

    /// The failure this protects against is a tester spending a session on a
    /// heartbeat characteristic because hex looked busy.
    @Test func aStreamWhereNothingMovesSaysSo() {
        let d = digest(Array(repeating: Self.bytes("AA00BB"), count: 5))
        #expect(d.dataIndices.isEmpty)
        #expect(d.headline == "Every byte is the same in all 5 packets — nothing here reacts.")
    }

    @Test func mixedLengthsAreNotAnalysedByBytePosition() {
        let d = digest([Self.bytes("AABB"), Self.bytes("AABBCC")])
        #expect(d.frameSize == nil)
        #expect(d.headline == "Packets of mixed length — not a fixed frame.")
        #expect(d.detail.first == "2 packets, lengths differ")
    }

    @Test func nothingReceivedIsNotAVerdict() {
        #expect(digest([]).headline == "Nothing received.")
    }

    // MARK: - Other shapes of frame

    @Test func aPlainCounterIsNotDescribedAsSwapped() {
        // header, counter, then a reading. Ten packets because a counter is
        // only claimed once there are enough steps for the claim to mean
        // something.
        let frames = (0..<10).map { i in Data([0x5A, UInt8(i), 0x01, UInt8(0x10 + i)]) }
        let d = digest(frames)
        #expect(d.counter == "Byte 1 counts packets")
        #expect(d.dataIndices == [3])
    }

    @Test func anXORChecksumIsRecognisedToo() {
        let frames = (0..<5).map { i -> Data in
            let body: [UInt8] = [0x02, 0x30, UInt8(0x40 + i)]
            return Data(body + [body.reduce(0, ^)])
        }
        #expect(digest(frames).checksum == "Byte 3 is a checksum (XOR of bytes 0–2) — valid in all 5 packets")
    }

    /// Two adjacent changing bytes are one number, not two fields — read
    /// big-endian, which is what these frames use.
    @Test func adjacentChangingBytesAreReadAsOneNumber() {
        let frames: [Data] = [
            Data([0xAA, 0x01, 0x00]), Data([0xAA, 0x01, 0xF4]), Data([0xAA, 0x02, 0x58]),
        ]
        let d = digest(frames)
        #expect(d.dataIndices == [1, 2])
        #expect(d.latest == 600)
        #expect(d.low == 256)
        #expect(d.high == 600)
        #expect(d.detail.contains { $0 == "Bytes 1–2 carry the reading: 256–600, now 600" })
    }

    // MARK: - Grouping

    @Test func eachCharacteristicIsDigestedSeparatelyInTheOrderItAppeared() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let entries: [BLELogEntry] = [
            BLELogEntry(at: start, content: .packet(characteristic: "FFE3", data: Data([0, 0]))),
            BLELogEntry(at: start.addingTimeInterval(1), content: .packet(characteristic: "FFE2", data: Data([1, 2]))),
            BLELogEntry(at: start.addingTimeInterval(2), content: .packet(characteristic: "FFE2", data: Data([1, 3]))),
            BLELogEntry(at: start.addingTimeInterval(3), content: .mark(grams: 100, photo: nil)),
        ]
        let digests = BLEStreamDigest.digests(for: entries)
        #expect(digests.map(\.characteristic) == ["FFE3", "FFE2"])
        #expect(digests[1].packets == 2)
        #expect(digests[1].dataIndices == [1])
    }
}

/// The transcript is what leaves the phone. Everything the digest worked out
/// has to survive the trip, and a capture that cannot be decoded has to say
/// why while the tester can still do something about it.
struct BLETranscriptAnalysisTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func transcript(_ entries: [BLELogEntry]) -> String {
        BLETranscript.text(
            title: "AiLink_2EEB", identifier: "ID", advertised: ["FFE0"], profile: [], entries: entries
        )
    }

    private var packets: [BLELogEntry] {
        (0..<4).map { i in
            BLELogEntry(
                at: start.addingTimeInterval(Double(i) * 0.15),
                content: .packet(characteristic: "FFE2", data: Data([0xA7, UInt8(i), 0x7A]))
            )
        }
    }

    @Test func theAnalysisIsAboveTheHex() throws {
        let text = transcript(packets)
        let analysis = try #require(text.range(of: "ANALYSIS"))
        let capture = try #require(text.range(of: "CAPTURE"))
        #expect(analysis.lowerBound < capture.lowerBound)
    }

    /// The single most useful thing the transcript can say to whoever reads it
    /// next: this capture cannot be decoded, and here is what to do instead.
    @Test func aCaptureWithNoMarksSaysItCannotBeDecoded() {
        #expect(transcript(packets).contains("NO MARKED WEIGHTS"))
    }

    @Test func oneMarkIsEnoughToDropTheWarning() {
        let marked = packets + [BLELogEntry(at: start.addingTimeInterval(1), content: .mark(grams: 160, photo: "mark-01.jpg"))]
        #expect(!transcript(marked).contains("NO MARKED WEIGHTS"))
    }

    /// A capture that simply stops has to say whether the scale went to sleep
    /// or the tester pressed Disconnect — the first owner capture said neither.
    @Test func linkEventsAreRecordedInLine() {
        let entries = [
            BLELogEntry(at: start, content: .note("connected to AiLink_2EEB")),
            BLELogEntry(at: start.addingTimeInterval(0.5), content: .note("subscribed to 0000FFE2")),
            BLELogEntry(at: start.addingTimeInterval(12), content: .note("link dropped — The specified device has disconnected from us.")),
        ]
        let text = transcript(entries)
        #expect(text.contains("---- connected to AiLink_2EEB"))
        #expect(text.contains("---- subscribed to 0000FFE2"))
        #expect(text.contains("---- link dropped — The specified device has disconnected from us."))
    }

    @Test func anEmptyCaptureHasNoAnalysisSection() {
        #expect(!transcript([]).contains("ANALYSIS"))
    }
}

/// The owner's SECOND capture (2026-09-08) — the one where the link dropped 27
/// times in 154 seconds and three photographed marks all landed in silences.
/// It broke the digest in two ways at once: the counter stopped being detected
/// because packets were lost between reconnects, and byte 12's stable/unstable
/// flag was counted as data, which split the reading into fragments and left
/// the tester with "4 changing bytes" and no live number at all.
struct BLEStreamDigestSecondCaptureTests {

    private static let frames: [Data] = [
        "A7006C09EB430383A56DEA4202697A", "A7006C09EB400383366DEA4202F77A",
        "A7006C09EB410382676DEA4202287A", "A7006C09EB460380156DEA4202D97A",
        "A7006C09EB470387786DEA4202447A", "A7006C09EB440387546DEA42021D7A",
        "A7006C09EB450387516DEA42021B7A", "A7006C09EB4B0387506DEA4202207A",
        "A7006C09EB4803875B6DEA4202287A", "A7006C09EB490387536DEA4202217A",
        "A7006C09EB4E0387F46DEA4202C77A", "A7006C09EB4F0381C96DEA4202977A",
        "A7006C09EB4C0383016DEA4202CE7A", "A7006C09EB4D0383B76DEA4202857A",
        "A7006C09EB520383B46DEA4202877A", "A7006C09EB530383B56DEA4202897A",
        "A7006C09EB510383946DEA4202667A", "A7006C09EB560383456DEA42021C7A",
        "A7006C09EB570382E46DEA4202BB7A", "A7006C09EB540382D46DEA4202A87A",
        "A7006C09EB550382D46DEA4201A87A", "A7006C09EB5B0382276DEA4202027A",
        "A7006C09EB580382166DEA4202EE7A", "A7006C09EB5903823A6DEA4202137A",
    ].map(hex)

    /// Duplicated rather than shared: this fixture is evidence, and a helper
    /// that both suites depend on is a helper that gets changed for one of them.
    private static func hex(_ text: String) -> Data {
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            data.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    private var digest: BLEStreamDigest {
        BLEStreamDigest.make(characteristic: "0000FFE2", packets: Self.frames, span: 13.4)
    }

    /// Packets 43, 44… 47, then 49 — the 48th was lost while the link was down.
    /// An exact-+1 rule rejects that, and rejecting it costs the analysis both
    /// the counter and, because the counter then counts as data, the reading.
    @Test func theCounterSurvivesPacketsLostToADroppedLink() {
        #expect(digest.counter == "Byte 5 counts packets (low bits swapped; packets were lost)")
    }

    /// Two values across two dozen packets is a flag, not a measurement. This
    /// one is the scale's settled/unsettled indicator — the single most useful
    /// byte in the frame after the reading itself.
    @Test func theTwoValuedByteIsReportedAsAFlagNotAsData() {
        let d = digest
        #expect(d.flags == [12])
        #expect(d.flagValues[12] == "2 values: 01, 02")
        #expect(!d.dataIndices.contains(12))
        #expect(d.detail.contains { $0 == "Byte 12 is a flag, not a number — 2 values: 01, 02" })
    }

    /// With the counter and the flag accounted for, what is left is one number
    /// spread over two adjacent bytes — and the screen gets its live reading back.
    @Test func whatRemainsIsOneTwoByteReading() {
        let d = digest
        #expect(d.dataIndices == [7, 8])
        #expect(d.latest == 33338)
        #expect(d.low == 32789)
        #expect(d.high == 34804)
        #expect(d.headline == "A checksummed frame with one changing number. This is the one.")
    }

    @Test func theChecksumStillHoldsAcrossTheReconnects() {
        #expect(digest.checksum == "Byte 13 is a checksum (sum of bytes 1–12) — valid in all 24 packets")
    }
}

/// A mark is worth what the reading beside it is worth. In the owner's second
/// capture two of the three marks had a packet less than two seconds away and
/// were STILL useless, because the load was still being set down and the value
/// was mid-swing; the third had no packet within twenty seconds. Both failures
/// have to be named, and named while the scale is still on the bench.
struct BLEMarkMatchabilityTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func transcript(_ entries: [BLELogEntry]) -> String {
        BLETranscript.text(title: "S", identifier: "I", advertised: [], profile: [], entries: entries)
    }

    /// A steady reading: the value barely moves across the window, so the
    /// mark pairs with it.
    private func packet(_ offset: TimeInterval, _ value: UInt8 = 0x40) -> BLELogEntry {
        BLELogEntry(
            at: start.addingTimeInterval(offset),
            content: .packet(characteristic: "FFE2", data: Data([0xA7, value, 0x7A]))
        )
    }

    private func mark(_ offset: TimeInterval, grams: Double? = 355, photo: String? = "mark-01.jpg") -> BLELogEntry {
        BLELogEntry(at: start.addingTimeInterval(offset), content: .mark(grams: grams, photo: photo))
    }

    /// Packets spanning the capture's full range, far from any mark, so the
    /// range against which steadiness is measured is well defined.
    private var context: [BLELogEntry] {
        [packet(100, 0x00), packet(101, 0xFF)]
    }

    @Test func aMarkTakenWhileTheReadingWasSteadyIsNotFlagged() {
        let text = transcript(context + [packet(0, 0x40), mark(0.4), packet(0.6, 0x41)])
        #expect(text.contains("nearest packet 0.2s away"))
        #expect(!text.contains("NOT MATCHABLE"))
        #expect(!text.contains("STILL MOVING"))
    }

    @Test func aMarkTakenDuringASilenceSaysItMatchesNothing() {
        let text = transcript(context + [packet(0), mark(20.1)])
        #expect(text.contains("20.1s away — NOT MATCHABLE"))
    }

    /// The reason the gap is measured in BOTH directions: this scale goes
    /// quiet for twenty seconds and then resumes. A mark judged only on the
    /// silence behind it would be condemned while a perfectly good reading
    /// sits half a second after it.
    @Test func aPacketArrivingJustAfterAMarkStillRedeemsIt() {
        let text = transcript(context + [packet(0, 0x40), mark(20.1), packet(20.6, 0x40)])
        #expect(text.contains("nearest packet 0.5s away"))
        #expect(!text.contains("NOT MATCHABLE"))
    }

    /// Proximity alone is not enough, and this is the case that proves it:
    /// both of the owner's close marks (0.9s and 1.7s from a packet) were taken
    /// while the load was still being set down. A weight paired with a reading
    /// in motion looks like evidence and is not.
    @Test func aMarkTakenWhileTheReadingWasMovingIsCalledOut() {
        let entries = context + [
            packet(0, 0x10), mark(1.0), packet(1.5, 0x90), packet(2.0, 0x30),
        ]
        let text = transcript(entries)
        #expect(text.contains("STILL MOVING"))
        #expect(text.contains("% of its range"))
    }

    @Test func aCaptureWithNoPacketsAtAllCannotMatchAnything() {
        #expect(transcript([mark(1)]).contains("no packets in this capture — NOT MATCHABLE"))
    }

    /// The photograph is the evidence; typing the number is a convenience.
    /// Requiring the number before the camera would open is what made the
    /// tester fight the keyboard.
    @Test func aPhotographWithNoTypedWeightIsStillARecord() {
        let text = transcript(context + [packet(0), mark(0.2, grams: nil, photo: "mark-02.jpg")])
        #expect(text.contains("scale display photographed, not typed"))
        #expect(text.contains("photo: mark-02.jpg"))
    }

    /// Offsets alone cannot be joined to a photograph's creation date, which is
    /// how the owner's three marks had to be located by hand.
    @Test func theTranscriptCarriesAnAbsoluteStartTime() {
        let text = transcript([BLELogEntry(at: start, content: .note("connected"))])
        #expect(text.contains("Started: "))
        #expect(text.contains("1970-01-12"))
    }

    /// A link that hangs up on a fixed cycle is a property of the capture, not
    /// of any one packet, and it is the reason marks and readings never meet.
    @Test func repeatedDropsAreReportedWithTheirCadence() {
        var entries: [BLELogEntry] = [BLELogEntry(at: start, content: .packet(characteristic: "FFE2", data: Data([1, 2])))]
        for i in 0..<5 {
            entries.append(BLELogEntry(
                at: start.addingTimeInterval(Double(i) * 5.3),
                content: .note("\(BLETranscript.dropPrefix) — The specified device has disconnected from us.")
            ))
        }
        let text = transcript(entries)
        #expect(text.contains("LINK: dropped 5 times, typically every 5.3s"))
    }

    @Test func aSingleDropIsNotACadence() {
        let entries = [
            BLELogEntry(at: start, content: .packet(characteristic: "FFE2", data: Data([1, 2]))),
            BLELogEntry(at: start.addingTimeInterval(4), content: .note("\(BLETranscript.dropPrefix) — closed by the app")),
        ]
        #expect(!transcript(entries).contains("LINK: dropped"))
    }
}

/// Ranking, not filtering. The owner asked to see only scales; the device that
/// matters is the one no rule knows about yet, so rows are promoted and
/// labelled and nothing is hidden.
struct BLEScaleHeuristicTests {

    @Test func aStandardWeighingServiceIsTheStrongestSignal() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "Unknown", advertised: ["181D"])
        #expect(level == .likely)
        #expect(reason == "advertises a weighing service (181D)")
    }

    @Test func theFullLengthFormOfAShortUUIDCountsToo() {
        let (level, _) = BLEScaleHeuristic.rank(
            name: "Unknown", advertised: ["0000181D-0000-1000-8000-00805F9B34FB"]
        )
        #expect(level == .likely)
    }

    /// The owner's own scale. It advertises no weighing service — but the pair
    /// FFE0+FEE0 is the AiLink signature, and that family is one SpoolKid
    /// decodes outright, which is a stronger promise than "probably a scale".
    @Test func theOwnersScaleIsRecognisedAsAFamilyWeCanRead() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "AiLink_2EEB", advertised: ["FFE0", "FEE0"])
        #expect(level == .likely)
        #expect(reason == "looks like an AiLink scale — SpoolKid can read these")
    }

    /// The signature is the PAIR. One serial bridge is on everything from LED
    /// strips to thermometers and must not claim a family we can read.
    @Test func oneAiLinkServiceAloneIsNotTheSignature() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "BT05", advertised: ["FEE0"])
        #expect(level == .possible)
        #expect(reason?.contains("AiLink") != true)
    }

    @Test func aScaleByNameIsStillPromotedWithoutTheSignature() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "Kitchen Scale", advertised: [])
        #expect(level == .likely)
        #expect(reason == "its name looks like a scale")
    }

    @Test func aSerialBridgeAloneIsOnlyWorthAMaybe() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "BT05", advertised: ["FFE0"])
        #expect(level == .possible)
        #expect(reason == "speaks over FFE0, which cheap scales use")
    }

    @Test func anythingElseIsUnrankedRatherThanRuledOut() {
        let (level, reason) = BLEScaleHeuristic.rank(name: "(unnamed)", advertised: [])
        #expect(level == .unlikely)
        #expect(reason == nil)
    }

    @Test func aNonStandardUUIDIsLeftAlone() {
        #expect(BLEScaleHeuristic.short("6E400001-B5A3-F393-E0A9-E50E24DCCA9E") == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    }
}

/// The owner asked for guidance on what to do when. One line, from the state.
struct BLEExplorerGuidanceTests {

    @Test func itWalksTheWholeSessionInOrder() {
        func step(
            _ hasDevice: Bool, _ scanning: Bool, _ found: Bool,
            _ packets: Int, _ marks: Int, zero: Bool = true, decode: Bool = false
        ) -> String {
            BLEScaleExplorerView.nextStep(
                hasDevice: hasDevice, isScanning: scanning, foundAny: found,
                knowsZero: zero, canDecode: decode, packets: packets, marks: marks
            )
        }
        #expect(step(false, false, false, 0, 0).hasPrefix("1."))
        #expect(step(false, true, false, 0, 0).hasPrefix("2."))
        #expect(step(false, true, true, 0, 0).hasPrefix("2."))
        #expect(step(true, false, true, 0, 0).hasPrefix("3."))
        #expect(step(true, false, true, 40, 0).hasPrefix("5."))
        #expect(step(true, false, true, 40, 1).hasPrefix("6."))
        #expect(step(true, false, true, 40, 3).hasPrefix("7."))
    }

    /// The empty pan is asked for BEFORE any weight, and it is the one step
    /// the wording insists on. Four of the owner's eight captures never had
    /// one, and none of them could yield the scale's zero.
    @Test func theEmptyPanIsAskedForBeforeAnyWeight() {
        let step = BLEScaleExplorerView.nextStep(
            hasDevice: true, isScanning: false, foundAny: true,
            knowsZero: false, canDecode: false, packets: 40, marks: 0
        )
        #expect(step.hasPrefix("4."))
        #expect(step.contains("EMPTY"))
    }

    /// A scale we already read should not be walked through a byte capture.
    @Test func aReadableScaleSkipsStraightToChecking() {
        let step = BLEScaleExplorerView.nextStep(
            hasDevice: true, isScanning: false, foundAny: true,
            knowsZero: true, canDecode: true, packets: 40, marks: 0
        )
        #expect(step.contains("SpoolKid can read this scale"))
    }

    /// When the bytes will not give it up, the advice must not be "capture
    /// more" — that is what cost four sessions.
    @Test func theDeadEndAdviceIsNotMoreCapturing() {
        #expect(BLEScaleExplorerView.unreadableAdvice.contains("manufacturer"))
        #expect(BLEScaleExplorerView.unreadableAdvice.contains("will not"))
    }

    /// Every mark unmatchable is the failure that wasted a whole session, so
    /// the screen has to say it while the scale is still on the bench.
    @Test func unmatchableMarksAreCalledOutOnScreen() {
        let all = BLEScaleExplorerView.markSummary(verified: 3, unverified: 0, unmatchable: 3)
        #expect(all.contains("None of them can be matched"))
        let some = BLEScaleExplorerView.markSummary(verified: 3, unverified: 0, unmatchable: 1)
        #expect(some.contains("1 of them cannot be matched"))
        #expect(!BLEScaleExplorerView.markSummary(verified: 3, unverified: 0, unmatchable: 0).contains("matched"))
    }
}

/// The owner's THIRD capture (2026-09-08) exposed two failures that both
/// produced confident, wrong output rather than a gap — the worse kind.
struct BLEMarkEvidenceIntegrityTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func transcript(_ entries: [BLELogEntry]) -> String {
        BLETranscript.text(title: "S", identifier: "I", advertised: [], profile: [], entries: entries)
    }

    /// A stream carrying a reading, spread wide enough for steadiness to mean
    /// something.
    private func reading(_ offset: TimeInterval, _ value: UInt8) -> BLELogEntry {
        BLELogEntry(
            at: start.addingTimeInterval(offset),
            content: .packet(characteristic: "FFE2", data: Data([0xA7, value, 0x7A]))
        )
    }

    /// FFE3's hello: one constant frame per reconnect, carrying nothing.
    private func hello(_ offset: TimeInterval) -> BLELogEntry {
        BLELogEntry(
            at: start.addingTimeInterval(offset),
            content: .packet(characteristic: "FFE3", data: Data([0xA6, 0x04, 0x6A]))
        )
    }

    private func mark(_ offset: TimeInterval) -> BLELogEntry {
        BLELogEntry(at: start.addingTimeInterval(offset), content: .mark(grams: nil, photo: "mark-01.jpg"))
    }

    /// The capture said "nearest packet 1.0s away" — green, mark now — when no
    /// weight had arrived for 8.6 seconds. The near packet was FFE3's hello.
    /// A stream with no changing number in it is not evidence that the scale
    /// is saying anything.
    @Test func aConstantStreamDoesNotCountAsTheScaleTalking() {
        let entries = [
            reading(0, 0x10), reading(1, 0x11), reading(2, 0xF0),
            mark(30), hello(29.5),
        ]
        let text = transcript(entries)
        #expect(text.contains("NOT MATCHABLE"))
    }

    @Test func theReadingStreamIsWhatTheGapIsMeasuredAgainst() {
        let entries = [
            reading(0, 0x10), reading(1, 0x11), reading(2, 0xF0),
            hello(29.5), mark(30), reading(30.4, 0x11),
        ]
        let gap = BLETranscript.nearestPacketGap(
            to: start.addingTimeInterval(30),
            in: entries,
            on: BLETranscript.principalStream(of: entries)?.characteristic
        )
        #expect(gap != nil)
        #expect(abs((gap ?? 0) - 0.4) < 0.001)
    }

    @Test func theBusiestStreamCarryingAReadingIsThePrincipalOne() {
        let entries = [
            hello(0), hello(1), hello(2), hello(3),
            reading(4, 0x10), reading(5, 0xF0),
        ]
        #expect(BLETranscript.principalStream(of: entries)?.characteristic == "FFE2")
    }

    /// A photographed mark carries the photograph and nothing else. The tester
    /// reads the display, photographs it, and types the number AFTERWARDS — so
    /// whatever sits in the field at shutter time belongs to the previous
    /// weight. Three photographs reading 1254, 1377 and 267 were filed as
    /// nothing, 1254 and 1377.
    @Test func aPhotographedMarkCarriesNoTypedFigure() {
        let text = transcript([reading(0, 0x10), reading(1, 0xF0), mark(0.5)])
        #expect(text.contains("scale display photographed, not typed"))
        #expect(!text.contains("reads"))
    }
}

/// Switching a characteristic off has to mean it stays off. This scale hangs
/// up every five seconds, and auto-subscribe runs on every reconnect.
@MainActor
struct BLESubscriptionOptOutTests {

    @Test func switchingOneOffIsRemembered() {
        let service = BLEScaleService()
        #expect(!service.hasOptOuts)
        service.setNotifying(false, characteristicUUID: "0000FEE2-0000-1000-8000-00805F9B34FB")
        #expect(service.hasOptOuts)
    }

    @Test func switchingItBackOnForgetsIt() {
        let service = BLEScaleService()
        service.setNotifying(false, characteristicUUID: "0000FEE2-0000-1000-8000-00805F9B34FB")
        service.setNotifying(true, characteristicUUID: "0000FEE2-0000-1000-8000-00805F9B34FB")
        #expect(!service.hasOptOuts)
    }
}

/// Bytes a tester types have to become exactly the bytes that leave the phone.
/// Half a command sent to an unknown device is the one thing in this screen
/// worth being strict about.
struct BLECommandTests {

    @Test func plainHexBecomesBytes() {
        #expect(BLECommand.parse("A6042C") == Data([0xA6, 0x04, 0x2C]))
    }

    /// A frame pasted straight out of a transcript, separators and all.
    @Test func separatorsAreIgnored() {
        #expect(BLECommand.parse("A6 04 2C") == Data([0xA6, 0x04, 0x2C]))
        #expect(BLECommand.parse("a6:04-2c") == Data([0xA6, 0x04, 0x2C]))
    }

    @Test func anOddNumberOfDigitsIsRefusedRatherThanPadded() {
        #expect(BLECommand.parse("A604C") == nil)
    }

    @Test func nonHexIsRefused() {
        #expect(BLECommand.parse("A6ZZ") == nil)
    }

    @Test func nothingIsNotACommand() {
        #expect(BLECommand.parse("") == nil)
        #expect(BLECommand.parse("   ") == nil)
    }

    /// The framing is the device's own, verified on every packet of every
    /// capture: header, payload, one-byte sum of the payload, trailer.
    @Test func framingMatchesTheScalesOwnFrames() {
        let framed = BLECommand.framed(payload: Data([0x04, 0x2C, 0x08, 0x00, 0xCD]), header: 0xA6, trailer: 0x6A)
        #expect(framed == Data([0xA6, 0x04, 0x2C, 0x08, 0x00, 0xCD, 0x05, 0x6A]))
    }

    /// Checked against the scale's own hello frame, byte for byte — if this
    /// disagrees, the framing rule is wrong and nothing built on it will be
    /// answered.
    @Test func theScalesOwnHelloFrameRebuildsExactly() {
        let hello = Data([0xA6, 0x04, 0x2C, 0x08, 0x00, 0xCD, 0x05, 0x6A])
        let rebuilt = BLECommand.framed(payload: hello.dropFirst().dropLast(2), header: 0xA6, trailer: 0x6A)
        #expect(rebuilt == hello)
    }

    @Test func theSumWrapsAtOneByte() {
        let framed = BLECommand.framed(payload: Data([0xFF, 0xFF]), header: 0xA7, trailer: 0x7A)
        #expect(framed == Data([0xA7, 0xFF, 0xFF, 0xFE, 0x7A]))
    }
}

/// A 19-packet connection is normal on a scale that hangs up every five
/// seconds. The flag detector used to need twenty, so capture B reported
/// "3 changing bytes" and lost the reading it had already found in capture A.
struct BLEShortConnectionDigestTests {

    @Test func aFlagIsStillRecognisedInASingleShortConnection() {
        // Twelve packets: a counter, a two-byte reading, and a settled flag.
        let frames: [Data] = (0..<12).map { i in
            let counter = UInt8(i)
            let high = UInt8(0x80 + i / 2)   // six values: a reading, not a flag
            let low = UInt8(i * 7)
            let flag: UInt8 = i == 11 ? 0x01 : 0x02
            return Data([0xA7, counter, 0x03, high, low, flag, 0x7A])
        }
        let digest = BLEStreamDigest.make(characteristic: "FFE2", packets: frames, span: 4.0)
        #expect(digest.flags == [5])
        #expect(digest.dataIndices == [3, 4])
        #expect(digest.latest != nil)
    }
}
