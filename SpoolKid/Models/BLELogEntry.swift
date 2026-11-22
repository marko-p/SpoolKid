//
//  BLELogEntry.swift
//  SpoolKid
//
//  Purpose: One line of a Bluetooth capture, and the transcript built from a
//  run of them. Pure and synchronous on purpose: the transcript is the whole
//  deliverable of a bench session with an unknown scale, and it has to be
//  testable without the scale.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A characteristic the peripheral offers, flattened for display and export.
nonisolated struct BLECharacteristicProfile: Identifiable, Equatable {
    let uuid: String
    /// CoreBluetooth's own description of what the characteristic permits —
    /// "notify", "read", "write" and so on, comma-joined.
    let properties: String
    var isNotifying: Bool
    let canNotify: Bool
    let canRead: Bool
    let canWrite: Bool

    var id: String { uuid }
}

nonisolated struct BLEServiceProfile: Identifiable, Equatable {
    let uuid: String
    var characteristics: [BLECharacteristicProfile]

    var id: String { uuid }
}

/// One entry in a capture: either bytes that arrived, or the weight the user
/// says the scale's own display was showing when they arrived.
nonisolated struct BLELogEntry: Identifiable, Equatable {

    nonisolated enum Content: Equatable {
        case packet(characteristic: String, data: Data)
        /// What the scale's display read, and — when the tester photographed
        /// it — the file that proves it.
        ///
        /// This is the reason the explorer exists rather than a generic BLE
        /// sniffer. Bytes alone are a puzzle; bytes with three known weights
        /// beside them are a format — the scaling factor, the byte order and
        /// the offset all fall out of comparing them.
        ///
        /// `photo` is the filename inside the shared bundle, nil when the
        /// tester only typed the number. Both are kept rather than the photo
        /// replacing the number: the typed figure makes the transcript
        /// readable on its own, and the photo is what makes it checkable by
        /// someone who was not in the room. A mark with no photo is still
        /// recorded — it is marked UNVERIFIED rather than refused, because a
        /// capture that argues with the tester mid-session is a capture that
        /// does not happen.
        /// `grams` is optional because the PHOTOGRAPH is the evidence and the
        /// typed figure is the convenience, not the other way round. Requiring
        /// a number before the camera would open made the tester type a weight
        /// while the scale kept interrupting them (owner, 2026-09-08).
        ///
        /// Whether a mark can be matched to a reading is NOT stored here: it
        /// is derived from the log by `BLETranscript.nearestPacketGap`, so
        /// there is one rule rather than a stored judgement that a later
        /// packet can silently falsify.
        case mark(grams: Double?, photo: String?)
        /// SpoolKid's OWN reading of the bytes, filed automatically when a
        /// recognised scale reports a settled weight.
        ///
        /// Deliberately NOT a `mark`. A mark is a human saying what the display
        /// read; this is the app saying what it decoded. Conflating them would
        /// let a transcript claim human verification it never had — and when a
        /// decoder is wrong, the two disagreeing is exactly the evidence
        /// whoever reads the capture needs.
        case decoded(grams: Int)
        /// The tester states the pan is empty. Worth more than three weight
        /// marks: an empty pan is the reading for zero, and every other reading
        /// is only meaningful relative to it.
        case panEmpty
        /// Something that happened to the link rather than on it: connected,
        /// subscribed, dropped. Recorded because the first owner capture
        /// (2026-09-08) simply stopped mid-stream, and nothing in the
        /// transcript said whether the scale had powered down, the phone had
        /// walked away, or the tester had pressed Disconnect.
        case note(String)
    }

    let id: UUID
    let at: Date
    let content: Content

    init(id: UUID = UUID(), at: Date, content: Content) {
        self.id = id
        self.at = at
        self.content = content
    }
}

nonisolated enum BLETranscript {

    /// Uppercase, space-separated, so a byte can be pointed at in a sentence.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// The printable-ASCII rendering, with everything else as `.`.
    ///
    /// Worth having beside the hex: some scales push a text protocol, and
    /// "1234 g" hiding in a byte dump is invisible until it is rendered.
    static func ascii(_ data: Data) -> String {
        String(data.map { $0 >= 0x20 && $0 < 0x7F ? Character(UnicodeScalar($0)) : "." })
    }

    /// Seconds since the first entry, so packet spacing is readable without
    /// subtracting wall-clock times by hand.
    static func offset(_ at: Date, from start: Date) -> String {
        String(format: "%+8.3f", at.timeIntervalSince(start))
    }

    /// A mark is only worth as much as the packet nearest it. Said in the
    /// transcript rather than left to be worked out, because whoever reads it
    /// will otherwise pair a weight with a reading from half a minute away.
    static let matchableWindow: TimeInterval = 3

    /// How far a mark is from the nearest packet CARRYING A READING, in either
    /// direction.
    ///
    /// Either direction, because the scale goes quiet and then resumes: a mark
    /// judged only on the silence behind it would be condemned while a perfectly
    /// good reading sits half a second after it.
    ///
    /// Reading-carrying, because counting any packet at all is how this told the
    /// owner "nearest packet 1.0s away" when no weight had arrived for 8.6
    /// seconds (2026-09-08) — the near packet was FFE3's constant hello, sent
    /// once per reconnect and carrying nothing. A stream with no changing number
    /// in it is not evidence that the scale is saying anything.
    static func nearestPacketGap(
        to mark: Date, in entries: [BLELogEntry], on stream: String? = nil
    ) -> TimeInterval? {
        let wanted = stream ?? principalStream(of: entries)?.characteristic
        return entries
            .compactMap { entry -> TimeInterval? in
                guard case .packet(let uuid, _) = entry.content else { return nil }
                guard wanted == nil || uuid == wanted else { return nil }
                return abs(entry.at.timeIntervalSince(mark))
            }
            .min()
    }

    /// The weight the scale had SETTLED at before this moment, when the
    /// capture comes from a scale SpoolKid can read.
    ///
    /// A settled reading followed by silence is the whole point of a scale:
    /// it stops talking BECAUSE nothing is changing. Judging such a mark by
    /// how long the stream has been quiet condemns exactly the marks that are
    /// worth most — the owner photographed a steady 1250 g display and was
    /// told "nearest packet 18.5s away — NOT MATCHABLE" (2026-09-08).
    ///
    /// Returns nil when the last frame was still moving, when the stream is
    /// not one we can decode, or when its zero is unknown — in all three the
    /// gap rule below is still the best answer available.
    static func settledWeight(before at: Date, in entries: [BLELogEntry]) -> Int? {
        guard let stream = principalStream(of: entries), let mask = stream.resting else { return nil }
        for entry in entries.reversed() {
            guard case .packet(let uuid, let data) = entry.content,
                  uuid == stream.characteristic, entry.at <= at else { continue }
            guard let frame = AiLinkScaleFrame.weightFrame(from: data), frame.isSettled else { return nil }
            return Int(frame.masked ^ UInt16(truncatingIfNeeded: mask))
        }
        return nil
    }

    /// What a mark is worth, in one bracket: near a packet, AND the reading
    /// steady while it was taken. Both, because either alone is a mark that
    /// cannot be paired with a weight — unless the scale had already settled,
    /// which beats both.
    static func freshness(gap: TimeInterval?, spread: Double?, settledAt: Int? = nil) -> String {
        if let settledAt {
            return "[the scale had settled at \(settledAt) g and gone quiet — MATCHABLE]"
        }
        guard let gap else { return "[no packets in this capture — NOT MATCHABLE]" }
        guard gap <= matchableWindow else {
            return String(format: "[nearest packet %.1fs away — NOT MATCHABLE]", gap)
        }
        if let spread, spread > BLEStreamDigest.steadyFraction {
            return String(
                format: "[nearest packet %.1fs away, but the reading swung %.0f%% of its range — STILL MOVING]",
                gap, spread * 100
            )
        }
        return String(format: "[nearest packet %.1fs away]", gap)
    }

    /// The stream most likely to be carrying the weight: the one with a reading
    /// and the most packets behind it.
    static func principalStream(of entries: [BLELogEntry]) -> BLEStreamDigest? {
        BLEStreamDigest.digests(for: entries)
            .filter { $0.latest != nil }
            .max { $0.packets < $1.packets }
    }

    /// The text every dropped-link note starts with. One constant, because the
    /// analysis counts them and a second spelling would silently report zero.
    static let dropPrefix = "link dropped"

    /// Marks a note as bytes this app SENT, so a reply can be told from an
    /// unprompted packet when the transcript is read somewhere else.
    static let sentPrefix = "sent"

    /// The shareable capture. Everything needed to work out a protocol from
    /// somewhere other than this phone.
    static func text(
        title: String,
        identifier: String,
        advertised: [String],
        profile: [BLEServiceProfile],
        entries: [BLELogEntry]
    ) -> String {
        var out = ["SpoolKid Bluetooth capture", "Peripheral: \(title)", "Identifier: \(identifier)"]
        if let began = entries.first?.at {
            // An absolute anchor, so photographs and anything else timestamped
            // outside this file can be lined up with it. Offsets alone cannot
            // be joined to a JPEG's creation date.
            out.append("Started: \(ISO8601DateFormatter().string(from: began))")
        }
        out.append("Advertised services: " + (advertised.isEmpty ? "(none)" : advertised.joined(separator: ", ")))

        out.append("")
        out.append("SERVICES")
        if profile.isEmpty {
            out.append("  (not discovered)")
        }
        for service in profile {
            out.append("  \(service.uuid)")
            for characteristic in service.characteristics {
                let subscribed = characteristic.isNotifying ? "  [subscribed]" : ""
                out.append("    \(characteristic.uuid)  (\(characteristic.properties))\(subscribed)")
            }
        }

        // Before the hex, not after it: whoever opens this — the tester, or
        // whoever they send it to — needs to know whether the capture is worth
        // reading before they read 2000 lines of it.
        let digests = BLEStreamDigest.digests(for: entries)
        if !digests.isEmpty {
            out.append("")
            out.append("ANALYSIS  (byte positions are 0-based)")
            for digest in digests {
                out.append("  \(digest.characteristic)")
                out.append("    \(digest.headline)")
                for line in digest.detail { out.append("    \(line)") }
            }
            let drops = entries.compactMap { entry -> Date? in
                if case .note(let text) = entry.content, text.hasPrefix(dropPrefix) { return entry.at }
                return nil
            }
            if drops.count >= 2 {
                let gaps = zip(drops.dropFirst(), drops).map { $0.timeIntervalSince($1) }
                let typical = gaps.sorted()[gaps.count / 2]
                out.append("")
                out.append(String(
                    format: "  LINK: dropped %d times, typically every %.1fs. Packets stop during each",
                    drops.count, typical
                ))
                out.append("  reconnection, so a mark taken in one of those gaps matches nothing.")
            }

            if !entries.contains(where: { if case .mark = $0.content { return true } else { return false } }) {
                out.append("")
                out.append("  NO MARKED WEIGHTS. Which byte is grams, and at what scale, cannot")
                out.append("  be worked out from one load state. Capture again with the pan empty,")
                out.append("  then with two or three known weights, marking each one.")
            }
        }

        out.append("")
        out.append("CAPTURE  (\(entries.count) entries)")
        guard let start = entries.first?.at else {
            out.append("  (nothing captured)")
            return out.joined(separator: "\n")
        }
        // Computed once: every mark is judged against the same stream.
        let principal = principalStream(of: entries)
        for entry in entries {
            let stamp = offset(entry.at, from: start)
            switch entry.content {
            case .packet(let characteristic, let data):
                out.append("\(stamp)  \(characteristic)  \(data.count)B  \(hex(data))  |\(ascii(data))|")
            case .mark(let grams, let photo):
                let reading = grams.map { "reads \(SpoolWeightMath.formatWeight($0)) g" } ?? "photographed, not typed"
                let evidence = photo.map { "photo: \($0)" } ?? "typed only — UNVERIFIED"
                let gap = nearestPacketGap(to: entry.at, in: entries, on: principal?.characteristic)
                let spread = principal?.spreadFraction(around: entry.at, in: entries, window: matchableWindow)
                let settled = settledWeight(before: entry.at, in: entries)
                out.append("\(stamp)  >>>> scale display \(reading)  [\(evidence)]  \(freshness(gap: gap, spread: spread, settledAt: settled))")
            case .decoded(let grams):
                out.append("\(stamp)  ==== SpoolKid decodes \(grams) g from these bytes")
            case .panEmpty:
                out.append("\(stamp)  >>>> PAN EMPTY — this reading is the scale's zero")
            case .note(let text):
                out.append("\(stamp)  ---- \(text)")
            }
        }
        return out.joined(separator: "\n")
    }
}
