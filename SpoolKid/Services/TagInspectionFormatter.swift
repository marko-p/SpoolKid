//
//  TagInspectionFormatter.swift
//  SpoolKid
//
//  Purpose: Turn the raw facts of a `TagInspection` into what the Inspect Tag
//  screen and its share text show. Pure and testable without a tag.
//
//  Rule for every name here: a chip or maker is named only where the mapping is
//  verified. Anything else shows the raw code, because a guess in this screen
//  would be read as a reading.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

/// One labelled line of the screen.
nonisolated struct InspectorRow: Equatable, Sendable {
    let label: String
    let value: String
}

/// One NDEF record, ready to render.
nonisolated struct InspectorRecord: Equatable, Sendable {
    /// "Record 1 · application/json"
    let title: String
    /// Kind, Language (text records), ID (when present), Size.
    let rows: [InspectorRow]
    /// The payload as stored. Nil for a binary or empty payload; never
    /// reformatted, trimmed or pretty-printed.
    let text: String?
    /// `hexDump` of the payload.
    let hex: String
    /// `bareHex` of the payload: what Copy Hex puts on the clipboard.
    let bareHex: String
}

nonisolated enum TagInspectionFormatter {

    // MARK: - Chip

    static func chipRows(_ i: TagInspection) -> [InspectorRow] {
        var rows = [InspectorRow(label: "Chip", value: chipName(i))]
        if let code = manufacturerCode(i) {
            rows.append(InspectorRow(label: "Made by", value: manufacturerName(code: code)))
        }
        let facts = familyFacts(i.family)
        rows.append(InspectorRow(label: "Technology", value: facts.technology))
        if let forumType = facts.forumType {
            rows.append(InspectorRow(label: "NFC Forum type", value: forumType))
        }
        if !i.uid.isEmpty {
            rows.append(InspectorRow(label: "UID", value: hexString(i.uid, separator: "")))
        }
        if let size = memorySize(i) {
            rows.append(InspectorRow(label: "Memory size", value: size))
        }
        return rows
    }

    /// The code table is deliberately short: only verified codes are named, and
    /// any other shows as the code itself.
    static func manufacturerName(code: Int) -> String {
        switch code {
        case 0x02: "STMicroelectronics"
        case 0x04: "NXP Semiconductors"
        case 0x05: "Infineon Technologies"
        case 0x07: "Texas Instruments"
        case 0x16: "EM Microelectronic-Marin"
        default: String(format: "Code 0x%02lX", code)
        }
    }

    private struct FamilyFacts {
        let technology: String
        let forumType: String?
        let fallbackChip: String
    }

    private static func familyFacts(_ family: TagInspection.Family) -> FamilyFacts {
        switch family {
        case .mifareUltralight:
            FamilyFacts(technology: "NFC-A (ISO 14443-3A)", forumType: "Type 2", fallbackChip: "MIFARE Ultralight family")
        case .mifareDESFire:
            FamilyFacts(technology: "NFC-A (ISO 14443-4)", forumType: "Type 4", fallbackChip: "MIFARE DESFire")
        case .mifarePlus:
            FamilyFacts(technology: "NFC-A (ISO 14443-4)", forumType: nil, fallbackChip: "MIFARE Plus")
        case .mifareOther:
            FamilyFacts(technology: "NFC-A (ISO 14443-3A)", forumType: nil, fallbackChip: "ISO 14443-A tag")
        case .iso15693:
            FamilyFacts(technology: "NFC-V (ISO 15693)", forumType: "Type 5", fallbackChip: "ISO 15693 tag")
        case .iso7816:
            FamilyFacts(technology: "ISO 14443-4 (ISO 7816)", forumType: "Type 4", fallbackChip: "ISO 7816 smart card")
        case .feliCa:
            FamilyFacts(technology: "NFC-F (FeliCa)", forumType: "Type 3", fallbackChip: "FeliCa")
        }
    }

    private static func chipName(_ i: TagInspection) -> String {
        let fallback = familyFacts(i.family).fallbackChip
        switch i.family {
        case .mifareUltralight:
            guard let reply = i.chip?.getVersion, !reply.isEmpty else { return fallback }
            if let pages = TagDumpWalk.pageCount(forVersionResponse: reply),
               let name = TagDumpWalk.chipName(forPageCount: pages) {
                return name
            }
            return "\(fallback) (version \(hexString(reply, separator: " ")))"
        case .iso15693:
            if let name = TagDumpWalk.icodeName(forUID: i.uid) { return name }
            guard let reference = i.chip?.icReference else { return fallback }
            return TagDumpWalk.describeICReference(reference)
        default:
            return fallback
        }
    }

    /// The first UID byte is the maker only on a 7- or 10-byte NFC-A UID. A
    /// 4-byte UID is often random, and its first byte means nothing.
    private static func manufacturerCode(_ i: TagInspection) -> Int? {
        switch i.family {
        case .iso15693:
            return i.icManufacturerCode
        case .mifareUltralight, .mifareDESFire, .mifarePlus, .mifareOther:
            guard i.uid.count == 7 || i.uid.count == 10, let first = i.uid.first else { return nil }
            return Int(first)
        case .iso7816, .feliCa:
            return nil
        }
    }

    private static func memorySize(_ i: TagInspection) -> String? {
        switch i.family {
        case .mifareUltralight:
            guard let reply = i.chip?.getVersion,
                  let pages = TagDumpWalk.pageCount(forVersionResponse: reply) else { return nil }
            return "\(pages) pages × \(TagSnapshot.bytesPerPage) bytes"
        case .iso15693:
            guard let blocks = i.chip?.totalBlocks, let size = i.chip?.blockSize,
                  blocks > 0, size > 0 else { return nil }
            return "\(blocks) blocks × \(size) bytes"
        default:
            return nil
        }
    }

    // MARK: - Memory

    static func memoryRows(_ i: TagInspection) -> [InspectorRow] {
        guard let ndef = i.ndef else { return [] }
        if ndef.access == .notSupported {
            // An inconclusive status probe that still yielded a message: the
            // tag has records, so it is not unformatted, and the probe's
            // capacity and access are not facts to print.
            if let used = ndef.messageLength {
                return [InspectorRow(label: "Used", value: byteCount(used))]
            }
            return [InspectorRow(label: "Write access", value: "Not NDEF-formatted")]
        }
        var rows: [InspectorRow]
        if let usage = memoryUsage(i) {
            rows = [
                InspectorRow(label: "Used", value: "\(usage.used) of \(usage.capacity) bytes"),
                InspectorRow(label: "Free", value: "\(max(0, usage.capacity - usage.used)) bytes"),
            ]
        } else {
            rows = [InspectorRow(label: "Capacity", value: "\(ndef.capacity) bytes")]
        }
        let access = ndef.access == .readOnly ? "Read-only" : "Writable"
        rows.append(InspectorRow(label: "Write access", value: access))
        return rows
    }

    /// The gauge's numbers: nil unless a message was read from a tag that
    /// reports a capacity.
    static func memoryUsage(_ i: TagInspection) -> (used: Int, capacity: Int)? {
        guard let ndef = i.ndef, ndef.access != .notSupported,
              let used = ndef.messageLength, ndef.capacity > 0 else { return nil }
        return (used, ndef.capacity)
    }

    // MARK: - Content

    static func contentRows(_ i: TagInspection, formatName: String) -> [InspectorRow] {
        var rows = [InspectorRow(label: "Format", value: formatName)]
        if let layout = layout(i) {
            rows.append(InspectorRow(label: "Layout", value: layout))
        }
        return rows
    }

    static func formatName(
        format: ScanResult.DetectedFormat?,
        isLocationTag: Bool,
        undecodedNote: String?
    ) -> String {
        if isLocationTag { return "SpoolKid location" }
        if let format {
            return format == .webUrl ? "Web link" : format.displayName
        }
        return undecodedNote ?? "Unknown tag format"
    }

    private static func layout(_ i: TagInspection) -> String? {
        let recordCount = i.ndef?.records.count ?? 0
        let rawRange = rawRangeText(i)
        switch (recordCount > 0, rawRange) {
        case (true, let raw?):
            return "\(ndefLayout(recordCount)) + raw \(raw)"
        case (true, nil):
            return ndefLayout(recordCount)
        case (false, let raw?):
            return "Raw \(raw)"
        case (false, nil):
            return nil
        }
    }

    private static func ndefLayout(_ count: Int) -> String {
        "NDEF, \(count) \(count == 1 ? "record" : "records")"
    }

    /// "pages 4–35" or "blocks 0–79" (en dash); nil without raw memory.
    private static func rawRangeText(_ i: TagInspection) -> String? {
        guard let raw = i.rawMemory, raw.unitSize > 0, !raw.bytes.isEmpty else { return nil }
        let units = (raw.bytes.count + raw.unitSize - 1) / raw.unitSize
        return "\(unitNoun(i)) \(raw.firstUnit)–\(raw.firstUnit + units - 1)"
    }

    private static func unitNoun(_ i: TagInspection) -> String {
        i.family == .iso15693 ? "blocks" : "pages"
    }

    // MARK: - Records

    static func records(_ i: TagInspection) -> [InspectorRecord] {
        (i.ndef?.records ?? []).enumerated().map { index, record in
            inspectorRecord(number: index + 1, record)
        }
    }

    /// What a payload turned out to be. Decided once, so the Size row and the
    /// text cannot disagree.
    private enum Body {
        case empty
        case text(String, language: String)
        case link(String)
        case utf8(String)
        case binary
    }

    private static func inspectorRecord(number: Int, _ r: NDEFRecordSnapshot) -> InspectorRecord {
        let type = String(decoding: r.type, as: UTF8.self)
        let body = body(of: r, type: type)

        var rows = [InspectorRow(label: "Kind", value: kindName(r.typeNameFormat))]
        var text: String?
        let size: String
        let count = byteCount(r.payload.count)
        switch body {
        case .empty:
            size = count
        case .text(let string, let language):
            rows.append(InspectorRow(label: "Language", value: language))
            text = string
            size = "\(count) · text"
        case .link(let string):
            text = string
            size = "\(count) · link"
        case .utf8(let string):
            text = string
            size = "\(count) · UTF-8 text"
        case .binary:
            size = "\(count) · binary"
        }
        if !r.identifier.isEmpty {
            let id = plainText(r.identifier)
                ?? hexString([UInt8](r.identifier), separator: " ")
            rows.append(InspectorRow(label: "ID", value: id))
        }
        rows.append(InspectorRow(label: "Size", value: size))

        return InspectorRecord(
            title: "Record \(number) · \(label(of: r, type: type))",
            rows: rows,
            text: text,
            hex: hexDump([UInt8](r.payload)),
            bareHex: bareHex([UInt8](r.payload))
        )
    }

    /// A well-known `T` record goes through CoreNFC, which handles the text
    /// encodings (UTF-8 and UTF-16); a `U` record is expanded here, because
    /// CoreNFC builds a `URL` that percent-encodes the text and raises an
    /// exception on a remainder that is not UTF-8. A record neither can decode
    /// falls through to the generic rule, so its status or prefix byte then
    /// makes it binary rather than showing a half-decoded string.
    private static func body(of r: NDEFRecordSnapshot, type: String) -> Body {
        guard !r.payload.isEmpty else { return .empty }
        if r.typeNameFormat == NFCTypeNameFormat.nfcWellKnown.rawValue {
            if type == "T", let (string, locale) = textRecord(r) {
                return .text(string, language: locale.identifier)
            }
            if type == "U", let uri = uriString(r.payload) {
                return .link(uri)
            }
        }
        if let string = plainText(r.payload) { return .utf8(string) }
        return .binary
    }

    /// The URI exactly as stored: the prefix code expanded, the rest decoded as
    /// exact UTF-8. Nil for a code past the table or a remainder that is not
    /// UTF-8.
    private static func uriString(_ payload: Data) -> String? {
        guard let code = payload.first, let prefix = NDEFURIRecord.prefix(forCode: code),
              let rest = exactUTF8(payload.dropFirst()) else { return nil }
        return prefix + rest
    }

    private static func textRecord(_ r: NDEFRecordSnapshot) -> (String, Locale)? {
        let decoded = r.record().wellKnownTypeTextPayload()
        guard let string = decoded.0, let locale = decoded.1 else { return nil }
        return (string, locale)
    }

    /// The bytes as a string only if they are valid UTF-8, and then exactly:
    /// `String(data:encoding:)` drops a leading byte-order mark, which would
    /// hide the very byte that makes a parser reject the tag. Decoding with
    /// repair and checking the bytes round-trip keeps it and rejects invalid
    /// input.
    private static func exactUTF8(_ data: Data) -> String? {
        let string = String(decoding: data, as: UTF8.self)
        return Array(string.utf8) == [UInt8](data) ? string : nil
    }

    /// UTF-8 text with no control characters other than tab, CR and LF. The
    /// string is the payload unchanged. A control character is Unicode's general
    /// category Control (C0, DEL and C1), not a scalar below 0x20.
    private static func plainText(_ payload: Data) -> String? {
        guard let string = exactUTF8(payload) else { return nil }
        let allowed = string.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D: true
            default: scalar.properties.generalCategory != .control
            }
        }
        return allowed ? string : nil
    }

    private static func kindName(_ tnf: UInt8) -> String {
        switch tnf {
        case 0: "Empty"
        case 1: "Well-known"
        case 2: "MIME type"
        case 3: "Absolute URI"
        case 4: "External"
        case 5: "Unknown"
        case 6: "Unchanged"
        default: "Reserved"
        }
    }

    private static func label(of r: NDEFRecordSnapshot, type: String) -> String {
        switch r.typeNameFormat {
        case 1:
            switch type {
            case "U": return "Link"
            case "T": return "Text"
            default: return "Well-known “\(type)”"
            }
        case 2, 3, 4:
            return type.isEmpty ? kindName(r.typeNameFormat) : type
        default:
            return kindName(r.typeNameFormat)
        }
    }

    private static func byteCount(_ n: Int) -> String {
        n == 1 ? "1 byte" : "\(n) bytes"
    }

    // MARK: - Dumps

    static func rawSectionTitle(_ i: TagInspection) -> String {
        i.family == .iso15693 ? "Raw Blocks" : "Raw Pages"
    }

    /// One row per page or block: the number, the bytes, the readable column.
    static func rawDump(_ m: TagInspection.RawMemory) -> String {
        guard m.unitSize > 0 else { return "" }
        return stride(from: 0, to: m.bytes.count, by: m.unitSize).map { start in
            let unit = Array(m.bytes[start..<min(start + m.unitSize, m.bytes.count)])
            let number = String(format: "%3ld", m.firstUnit + start / m.unitSize)
            return "\(number)  \(hexString(unit, separator: " "))  \(readable(unit))"
        }
        .joined(separator: "\n")
    }

    /// Eight bytes a row: offset, hex padded to a full row, readable column.
    static func hexDump(_ bytes: [UInt8]) -> String {
        let perRow = 8
        let hexWidth = perRow * 3 - 1
        return stride(from: 0, to: bytes.count, by: perRow).map { start in
            let row = Array(bytes[start..<min(start + perRow, bytes.count)])
            let hex = hexString(row, separator: " ")
                .padding(toLength: hexWidth, withPad: " ", startingAt: 0)
            return String(format: "%04lX", start) + "  \(hex)  \(readable(row))"
        }
        .joined(separator: "\n")
    }

    /// Uppercase bytes separated by single spaces: no offsets, no readable
    /// column. What Copy Hex copies, so it pastes as bytes.
    static func bareHex(_ bytes: [UInt8]) -> String {
        hexString(bytes, separator: " ")
    }

    private static func readable(_ bytes: [UInt8]) -> String {
        String(bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
    }

    private static func hexString(_ bytes: [UInt8], separator: String) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    // MARK: - Caption and share

    static func caption(capturedAt: Date, changedSinceScan: Bool) -> String {
        if changedSinceScan {
            return "This tag was changed after this scan. Scan it again to see what's on it now."
        }
        return "As read at " + capturedAt.formatted(date: .omitted, time: .shortened)
    }

    /// The whole screen as plain text: every row, every record as text and
    /// hex, and the raw dump.
    static func shareText(_ i: TagInspection, formatName: String, appVersion: String) -> String {
        var blocks: [String] = [
            "Inspect Tag — SpoolKid \(appVersion)\n"
                + "Scanned: \(i.capturedAt.formatted(date: .abbreviated, time: .shortened))"
        ]
        blocks.append(section("Chip", chipRows(i)))
        let memory = memoryRows(i)
        if !memory.isEmpty { blocks.append(section("Memory", memory)) }
        blocks.append(section("Content", contentRows(i, formatName: formatName)))

        for record in records(i) {
            var lines = [record.title] + record.rows.map(line)
            if let text = record.text { lines.append("Text:\n\(text)") }
            if !record.hex.isEmpty { lines.append("Hex:\n\(record.hex)") }
            blocks.append(lines.joined(separator: "\n"))
        }
        if let raw = i.rawMemory, !raw.bytes.isEmpty {
            blocks.append("\(rawSectionTitle(i))\n\(rawDump(raw))")
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func section(_ title: String, _ rows: [InspectorRow]) -> String {
        ([title] + rows.map(line)).joined(separator: "\n")
    }

    private static func line(_ row: InspectorRow) -> String {
        "\(row.label): \(row.value)"
    }
}
