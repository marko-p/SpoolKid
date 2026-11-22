//
//  BLEStreamDigest.swift
//  SpoolKid
//
//  Purpose: Turn a run of captured packets into a sentence a tester can act
//  on. A scale that streams 15 bytes at 6 Hz is unreadable as hex on a phone
//  at a bench — the first owner capture came back with "the output seemed all
//  jibberish to me" (2026-09-08), which is a fair verdict on a screen that
//  shows only hex.
//
//  Everything here is derived from the bytes alone. No protocol is assumed and
//  no device is named: the analysis is which byte positions move, which one is
//  a checksum, which one counts packets, and therefore which one is the
//  reading. That is enough to tell a promising stream from a dead one without
//  knowing whose scale it is.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What one characteristic's packets add up to.
nonisolated struct BLEStreamDigest: Identifiable, Equatable {

    let characteristic: String
    let packets: Int
    /// Nil when the packets are not all the same length — nothing below can be
    /// said about byte positions that do not line up.
    let frameSize: Int?
    /// Packets per second, nil until there are two packets to time.
    let rate: Double?
    /// Set when the first and last byte never change, which is what a framed
    /// protocol looks like from outside.
    let framing: String?
    /// Set when one byte position is the running sum or XOR of the bytes
    /// before it, in EVERY packet. This is the strongest available evidence
    /// that a stream is a real protocol rather than noise.
    let checksum: String?
    /// A byte position that advances by exactly one per packet.
    let counter: String?
    /// Changing byte positions that only ever take two or three values. They
    /// are flags, not readings — the owner's scale carries a stable/unstable
    /// flag in byte 12 (2026-09-08), and counting it among the changing data
    /// bytes broke the field into fragments and hid the reading entirely.
    let flags: [Int]
    /// The byte positions that change and are neither counter nor checksum —
    /// the reading, whatever it turns out to mean.
    let dataIndices: [Int]
    /// `dataIndices` read as one big-endian number, latest packet first, when
    /// they are contiguous.
    let latest: UInt32?
    let low: UInt32?
    let high: UInt32?
    /// The handful of values each flag byte takes, rendered for `detail`.
    let flagValues: [Int: String]
    /// The reading the stream rests at — the value it was showing each time it
    /// stopped talking, most common first.
    ///
    /// This is the single most useful number in the digest and it was missing
    /// for four sessions. A scale at rest reads zero, so the resting value IS
    /// the zero, and every other reading is only meaningful *relative to it*.
    /// The owner's scale masks its weight with a constant; the digest reported
    /// a field that moved with the load and no scale factor that fitted,
    /// because it was comparing readings to nothing (2026-09-09).
    /// The constant turned out to be the empty-pan reading itself.
    let resting: UInt32?
    /// Distinct readings the stream held more than once — its plateaus. Shown
    /// against `resting` so a tester can match a column to their display.
    let plateaus: [UInt32]

    var id: String { characteristic }

    // MARK: - Verdict

    /// One line, in the tester's terms, about whether this stream is worth
    /// their time.
    var headline: String {
        guard packets > 0 else { return "Nothing received." }
        guard frameSize != nil else { return "Packets of mixed length — not a fixed frame." }
        if dataIndices.isEmpty && flags.isEmpty && checksum == nil && counter == nil {
            return "Every byte is the same in all \(packets) packets — nothing here reacts."
        }
        if dataIndices.isEmpty {
            return "A valid frame, but nothing in it changes yet."
        }
        // Adjacent changing bytes are ONE number, whatever its width — the
        // owner's scale spreads its reading over bytes 7 and 8, and calling
        // that "2 changing bytes" sends a tester looking for a second field.
        let oneNumber = latest != nil
        if checksum != nil {
            return oneNumber
                ? "A checksummed frame with one changing number. This is the one."
                : "A checksummed frame with \(dataIndices.count) changing bytes."
        }
        return oneNumber
            ? "One number changes packet to packet."
            : "\(dataIndices.count) bytes change packet to packet."
    }

    /// The supporting lines, in the order that makes the frame legible: size
    /// first, then the parts that are NOT the reading, then the reading.
    var detail: [String] {
        var lines: [String] = []
        if let frameSize {
            var size = "\(packets) packets · \(frameSize) bytes each"
            if let rate { size += String(format: " · %.1f/s", rate) }
            lines.append(size)
        } else {
            lines.append("\(packets) packets, lengths differ")
        }
        if let framing { lines.append(framing) }
        if let checksum { lines.append(checksum) }
        if let counter { lines.append(counter) }
        for index in flags {
            lines.append("Byte \(index) is a flag, not a number — \(flagValues[index] ?? "")")
        }
        if let latest, let low, let high {
            let positions = dataIndices.count == 1
                ? "Byte \(dataIndices[0])"
                : "Bytes \(dataIndices[0])–\(dataIndices[dataIndices.count - 1])"
            lines.append("\(positions) carry the reading: \(low)–\(high), now \(latest)")
            if dataIndices.count == 1 {
                // Said because it changes what the next capture has to prove:
                // a single moving byte wraps every 256 counts, so it is very
                // often the low byte of a wider field whose top bytes have not
                // moved yet. Only a weight big enough to carry will tell.
                lines.append("One byte alone only spans 256 counts — it may be the low byte of a wider number.")
            }
        } else if !dataIndices.isEmpty {
            lines.append("Changing bytes: \(dataIndices.map(String.init).joined(separator: ", "))")
        }
        lines.append(contentsOf: relativeReadings)
        return lines
    }

    /// The readings expressed against the resting value, both ways.
    ///
    /// Both, because the digest cannot tell which is right and the tester can:
    /// a scale that offsets its reading matches the subtraction column, one
    /// that masks it matches the XOR column. Showing only the raw numbers is
    /// what sent four sessions looking for a scale factor that did not exist.
    private var relativeReadings: [String] {
        guard let resting, !plateaus.isEmpty else { return [] }
        var lines = [
            "Rests at \(resting). With nothing on the scale, that IS its zero —",
            "so compare every reading below against it, not against 0."
        ]
        let loaded = plateaus.filter { $0 != resting }
        guard !loaded.isEmpty else {
            lines.append("Nothing has been on the scale yet. Put a known weight on.")
            return lines
        }
        lines.append("reading      minus rest      XOR rest")
        for value in loaded.prefix(6) {
            lines.append(String(
                format: "%-12d %-15d %d",
                Int(value), Int(value) - Int(resting), Int(value ^ resting)
            ))
        }
        lines.append("One of those two columns should be the weight on your display.")
        return lines
    }

    // MARK: - Whether a mark can be trusted

    /// This stream's reading in one frame, when the digest found a reading.
    func value(in frame: Data) -> UInt32? {
        guard latest != nil, !dataIndices.isEmpty,
              let last = dataIndices.last, frame.count > last else { return nil }
        return dataIndices.reduce(UInt32(0)) { $0 << 8 | UInt32(frame[frame.startIndex + $1]) }
    }

    /// How far the reading moved across the packets around `at`, as a fraction
    /// of how far it moved across the whole capture. 0 is rock steady; 1 swung
    /// the full range.
    ///
    /// Proximity to a packet is NOT enough on its own, which is what the
    /// owner's second capture proved: two of its three marks had a packet less
    /// than two seconds away, and both of those packets were mid-swing because
    /// the load was still being set down. Pairing a weight with a reading taken
    /// while the reading was moving produces a number that looks like evidence
    /// and is not.
    ///
    /// Nil when fewer than two packets fall in the window, or when nothing in
    /// the capture moved far enough for "steady" to mean anything.
    func spreadFraction(around at: Date, in entries: [BLELogEntry], window: TimeInterval) -> Double? {
        guard let low, let high, high > low else { return nil }
        let nearby = entries.compactMap { entry -> UInt32? in
            guard case .packet(let uuid, let data) = entry.content,
                  uuid == characteristic,
                  abs(entry.at.timeIntervalSince(at)) <= window else { return nil }
            return value(in: data)
        }
        guard nearby.count >= 2, let min = nearby.min(), let max = nearby.max() else { return nil }
        return Double(max - min) / Double(high - low)
    }

    /// Above this, the reading was still moving when the mark was taken.
    static let steadyFraction = 0.05

    // MARK: - Analysis

    /// Builds a digest from packets that arrived on one characteristic.
    ///
    /// - Parameter span: seconds between the first and last packet, for the rate.
    /// - Parameter restingFrames: the packets this stream went quiet on. A
    ///   scale bursts while a weight changes and stops when it does not, so
    ///   these are the states it was left in — and the one it is left in most
    ///   often is an empty pan.
    static func make(
        characteristic: String,
        packets frames: [Data],
        span: TimeInterval,
        restingFrames: [Data] = []
    ) -> BLEStreamDigest {
        let sizes = Set(frames.map(\.count))
        let frameSize = sizes.count == 1 ? sizes.first : nil
        let rate = span > 0 && frames.count > 1 ? Double(frames.count) / span : nil

        guard let size = frameSize, size > 0, frames.count > 1 else {
            return BLEStreamDigest(
                characteristic: characteristic, packets: frames.count, frameSize: frameSize,
                rate: rate, framing: nil, checksum: nil, counter: nil, flags: [],
                dataIndices: [], latest: nil, low: nil, high: nil, flagValues: [:],
                resting: nil, plateaus: []
            )
        }

        let columns = (0..<size).map { index in frames.map { $0[$0.startIndex + index] } }
        let changing = (0..<size).filter { Set(columns[$0]).count > 1 }

        let framing: String? = {
            guard size >= 2, !changing.contains(0), !changing.contains(size - 1) else { return nil }
            return String(format: "Frame starts %02X, ends %02X", columns[0][0], columns[size - 1][0])
        }()

        let checksumIndex = changing.first { checksumSpan(at: $0, frames: frames) != nil }
        let checksum = checksumIndex.flatMap { index in
            checksumSpan(at: index, frames: frames).map { span in
                "Byte \(index) is a checksum (\(span)) — valid in all \(frames.count) packets"
            }
        }

        let counterIndex = changing.first { $0 != checksumIndex && counterPhrase(columns[$0]) != nil }
        let counter = counterIndex.flatMap { index in
            counterPhrase(columns[index]).map { "Byte \(index) \($0)" }
        }

        // A byte with two or three values across a long capture is a flag —
        // stable/unstable, units, sign. Reported, but kept out of the reading.
        // Ten packets, not twenty: this scale hangs up every five seconds and a
        // whole connection is often only a dozen frames. At twenty, a 19-packet
        // capture reported "3 changing bytes" and lost the reading entirely
        // (owner capture B, 2026-09-08).
        let flags = changing.filter { index in
            index != checksumIndex && index != counterIndex
                && frames.count >= 10 && Set(columns[index]).count <= 3
        }
        var flagValues: [Int: String] = [:]
        for index in flags {
            let values = Set(columns[index]).sorted()
            flagValues[index] = "\(values.count) values: " + values.map { String(format: "%02X", $0) }.joined(separator: ", ")
        }

        let dataIndices = changing.filter {
            $0 != checksumIndex && $0 != counterIndex && !flags.contains($0)
        }
        let contiguous = dataIndices.count > 0
            && dataIndices.count <= 4
            && dataIndices.last! - dataIndices.first! == dataIndices.count - 1

        var latest: UInt32?, low: UInt32?, high: UInt32?
        if contiguous {
            let values = frames.map { frame -> UInt32 in
                dataIndices.reduce(UInt32(0)) { $0 << 8 | UInt32(frame[frame.startIndex + $1]) }
            }
            latest = values.last
            low = values.min()
            high = values.max()
        }

        let draft = BLEStreamDigest(
            characteristic: characteristic, packets: frames.count, frameSize: frameSize,
            rate: rate, framing: framing, checksum: checksum, counter: counter, flags: flags,
            dataIndices: dataIndices, latest: latest, low: low, high: high, flagValues: flagValues,
            resting: nil, plateaus: []
        )
        return draft.withReadings(frames: frames, restingFrames: restingFrames)
    }

    /// Fills in `resting` and `plateaus` once the reading's byte positions are
    /// known. Separate because both need `value(in:)`, which needs the digest.
    private func withReadings(frames: [Data], restingFrames: [Data]) -> BLEStreamDigest {
        guard latest != nil else { return self }
        let restingValues = restingFrames.compactMap { value(in: $0) }
        let resting = Self.mostCommon(restingValues)
        // A plateau is a reading the stream held rather than passed through.
        // Counting repeats is enough: a settling scale visits each intermediate
        // value once and sits on the final one.
        var counts: [UInt32: Int] = [:]
        for frame in frames { if let v = value(in: frame) { counts[v, default: 0] += 1 } }
        let plateaus = counts.filter { $0.value > 1 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
        return BLEStreamDigest(
            characteristic: characteristic, packets: packets, frameSize: frameSize,
            rate: rate, framing: framing, checksum: checksum, counter: counter, flags: flags,
            dataIndices: dataIndices, latest: latest, low: low, high: high, flagValues: flagValues,
            resting: resting, plateaus: plateaus
        )
    }

    private static func mostCommon(_ values: [UInt32]) -> UInt32? {
        var counts: [UInt32: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// How long a stream must be silent before the packet before it counts as
    /// a resting state. Shared with `AiLinkScaleZero` so the transcript and the
    /// live decoder cannot disagree about what "at rest" means.
    static var restingSilence: TimeInterval { AiLinkScaleZero.restingSilence }

    /// Groups a capture's packets by characteristic, in the order each was
    /// first seen, and digests each one.
    static func digests(for entries: [BLELogEntry]) -> [BLEStreamDigest] {
        var order: [String] = []
        var frames: [String: [Data]] = [:]
        var first: [String: Date] = [:]
        var last: [String: Date] = [:]
        var resting: [String: [Data]] = [:]
        var previous: [String: (Date, Data)] = [:]
        for entry in entries {
            guard case .packet(let characteristic, let data) = entry.content else { continue }
            if frames[characteristic] == nil {
                order.append(characteristic)
                first[characteristic] = entry.at
            }
            // The packet BEFORE a long gap is the state the stream was left in.
            if let (at, held) = previous[characteristic],
               entry.at.timeIntervalSince(at) > restingSilence {
                resting[characteristic, default: []].append(held)
            }
            previous[characteristic] = (entry.at, data)
            frames[characteristic, default: []].append(data)
            last[characteristic] = entry.at
        }
        // The stream is resting now, too — the last packet of a capture is the
        // state it was left in, and often the only resting state there is.
        for (characteristic, held) in previous {
            resting[characteristic, default: []].append(held.1)
        }
        return order.map { characteristic in
            make(
                characteristic: characteristic,
                packets: frames[characteristic] ?? [],
                span: (last[characteristic] ?? .distantPast)
                    .timeIntervalSince(first[characteristic] ?? .distantPast),
                restingFrames: resting[characteristic] ?? []
            )
        }
    }

    // MARK: - Detectors

    /// Describes the span `byte[index]` checksums, if it checksums one.
    ///
    /// Only spans ending at the checksum byte are tried, starting at byte 0, 1
    /// or 2 — a checksum that skips a header is common, one that skips four
    /// bytes is not, and every extra span tried is another chance for a false
    /// positive on a short capture.
    private static func checksumSpan(at index: Int, frames: [Data]) -> String? {
        guard frames.count >= 3, index >= 2 else { return nil }
        for start in 0..<min(3, index - 1) {
            let sums = frames.allSatisfy { frame in
                let base = frame.startIndex
                let total = (start..<index).reduce(0) { $0 + Int(frame[base + $1]) }
                return UInt8(total % 256) == frame[base + index]
            }
            if sums { return "sum of bytes \(start)–\(index - 1)" }
            let xors = frames.allSatisfy { frame in
                let base = frame.startIndex
                let total = (start..<index).reduce(UInt8(0)) { $0 ^ frame[base + $1] }
                return total == frame[base + index]
            }
            if xors { return "XOR of bytes \(start)–\(index - 1)" }
        }
        return nil
    }

    /// Whether a column counts packets.
    ///
    /// Steps of 1 to 16 rather than exactly 1, because a link that drops every
    /// five seconds loses the packets in between and the counter carries on
    /// regardless — the owner's second capture dropped 27 times in 154 seconds,
    /// and an exact-+1 test failed on it, which cost the whole analysis the
    /// counter AND the reading (2026-09-08). Requiring every step to be a small
    /// POSITIVE move around the ring is what keeps this safe: a data byte
    /// wanders both ways, and a hundred consecutive forward steps do not
    /// happen by accident. A majority still has to be exactly +1.
    ///
    /// `k` covers counters whose low bits arrive swapped, and `modulus` those
    /// that wrap at 128 rather than 256; both are common in these MCUs.
    private static func counterPhrase(_ column: [UInt8]) -> String? {
        guard column.count >= 8 else { return nil }
        for modulus in [256, 128] {
            for k in UInt8(0)...3 {
                let steps = (0..<(column.count - 1)).map { i -> Int in
                    let a = Int(column[i] ^ k) % modulus
                    let b = Int(column[i + 1] ^ k) % modulus
                    return (b - a + modulus) % modulus
                }
                guard steps.allSatisfy({ (1...16).contains($0) }),
                      steps.count(where: { $0 == 1 }) * 2 >= steps.count else { continue }
                let gaps = steps.contains { $0 > 1 }
                switch (k == 0, gaps) {
                case (true, false): return "counts packets"
                case (true, true): return "counts packets (with gaps — packets were lost)"
                case (false, false): return "counts packets (its low bits arrive swapped)"
                case (false, true): return "counts packets (low bits swapped; packets were lost)"
                }
            }
        }
        return nil
    }
}
