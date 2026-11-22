//
//  PrinterTagSession+Read.swift
//  SpoolKid
//
//  Purpose: The read side of a printer tag session. Builds a `ScanResult` from
//  the plugin's pages in the order the iPhone path uses (NDEF, then ELEGOO,
//  Anycubic ACE and TigerTag raw decoders, then undecoded or blank).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

extension PrinterTagSession {

    func scan(rejectingLocationTags: Bool) async -> PrinterScanOutcome {
        trace("read.start", ["rejectsLocationTags": String(rejectingLocationTags)])
        let outcome = await readTag(rejectingLocationTags: rejectingLocationTags)
        trace("read.end", ["outcome": outcome.traceName])
        return outcome
    }

    private func readTag(rejectingLocationTags: Bool) async -> PrinterScanOutcome {
        if let error = notReadyError { return .failed(error) }

        // A Snapmaker tag or a MIFARE Classic tag (4-byte UID) is out of the
        // plugin's reach: the printer's own report is all there is.
        let reported = reportedToolhead
        if let reported, let uid = reported.tagUID, uid.count == 8 {
            return .result(reportedResult(for: reported))
        }

        switch await fetch() {
        case .failure(.unsupportedTag(let reason)):
            if let reported, reported.tagUID != nil { return .result(reportedResult(for: reported)) }
            return .failed(.unsupportedTag(reason))
        case .failure(let error):
            return .failed(error)
        case .success(let read):
            return decode(read, rejectingLocationTags: rejectingLocationTags)
        }
    }

    func dump() async -> Result<TagDump, PrinterTagError> {
        trace("dump.start")
        let result = await readDump()
        switch result {
        case .success(let dump): trace("dump.end", ["outcome": "ok", "pages": String(dump.pagesRead)])
        case .failure(let error): trace("dump.end", ["outcome": "failed", "code": error.code])
        }
        return result
    }

    private func readDump() async -> Result<TagDump, PrinterTagError> {
        if let error = notReadyError { return .failure(error) }
        switch await fetch() {
        case .failure(let error):
            return .failure(error)
        case .success(let read):
            let memory = memory(of: read)
            let pages = TagDump.hexPages(from: memory)
            guard !pages.isEmpty else { return .failure(.badRequest("Nothing could be read from this tag.")) }
            return .success(TagDump(
                capturedAt: Date(),
                uid: hardwareUID(of: read),
                tagType: "NFC Type 2, read through the printer",
                chipVersion: knownPageCount(of: read).flatMap { TagDumpWalk.chipName(forPageCount: $0) },
                pagesRead: pages.count,
                endedBy: .endOfTag,
                pages: pages,
                decodedAs: nfc.describeDump(bytes: memory),
                note: "",
                appVersion: AppConfig.versionString
            ))
        }
    }

    // MARK: - Reported by the printer

    /// What the printer already shows for the toolhead, for a tag the plugin
    /// cannot read. No snapshot: nothing was read from the tag itself.
    private func reportedResult(for state: ToolheadState) -> ScanResult {
        var result = ScanResult(
            cardUID: state.tagUID?.lowercased(),
            tagData: ToolheadTagImport.tagData(from: state),
            format: nil
        )
        result.isReportedByPrinter = true
        return result
    }

    // MARK: - Pages to result

    private func decode(_ read: PrinterTagRead, rejectingLocationTags: Bool) -> PrinterScanOutcome {
        let memory = memory(of: read)
        let uid = hardwareUID(of: read)
        var inspection = TagInspection(
            capturedAt: Date(), family: .mifareUltralight, uid: uidBytes(uid), icManufacturerCode: nil)
        let chip = read.versionReply.flatMap { $0.count >= 8 ? TagInspection.Chip(getVersion: $0) : nil }
        func finish(_ result: ScanResult) -> ScanResult {
            NFCManager.attaching(inspection, chip: chip, to: result)
        }

        if let records = ndefRecords(in: memory) {
            let messageBytes = Type2NDEF.messageBytes(for: records)
            inspection.ndef = .init(access: ndefAccess(memory), capacity: ndefCapacity(read.geometry),
                                    messageLength: messageBytes.count, records: records)
            // Every result below carries the message as read, for Clone Tag.
            let snapshot = TagSnapshot.ndef(records)

            // 0. A location tag is not filament data.
            for record in records {
                if let data = payloadData(of: record),
                   let location = LocationTagPayload.decode(payload: data, mimeType: mimeType(of: record)) {
                    let result = finish(ScanResult(cardUID: uid, tagData: nil, format: nil,
                                                   locationTag: location, tagSnapshot: snapshot))
                    return rejectingLocationTags
                        ? .refused(message: "This tag labels \(location.name).", result: result)
                        : .result(result)
                }
            }

            // 1. Structured decode first; on-tag data wins over a link.
            for record in records {
                if let data = payloadData(of: record),
                   let found = TagFormatService.shared.decodeDetectingFormat(payload: data, mimeType: mimeType(of: record)) {
                    var decoded = found.data
                    if found.format == .openPrintTag,
                       let url = NFCManager.firstURL(in: records.map { $0.record() }) {
                        decoded.tagURL = url.absoluteString
                    }
                    return .result(finish(ScanResult(cardUID: uid, tagData: decoded, format: found.format,
                                                     tagSnapshot: snapshot)))
                }
            }

            // 2. A link. The raw ELEGOO block is tried first: a real ELEGOO tag
            //    is a link on the NDEF layer and its filament block past the terminator.
            if let url = NFCManager.firstURL(in: records.map { $0.record() }) {
                if let elegoo = elegooResult(memory: memory, uid: uid, inspection: &inspection) {
                    return .result(finish(elegoo))
                }
                return .result(finish(ScanResult(cardUID: uid, tagData: nil, format: .webUrl,
                                                 url: url, tagSnapshot: snapshot)))
            }
            // 3. NDEF present but neither structured nor a link: raw reads.
        }

        return .result(finish(rawResult(memory: memory, uid: uid, inspection: &inspection)))
    }

    /// The raw chain: ELEGOO, then Anycubic ACE, then TigerTag, then undecoded or blank.
    private func rawResult(memory: [UInt8], uid: String, inspection: inout TagInspection) -> ScanResult {
        if let elegoo = elegooResult(memory: memory, uid: uid, inspection: &inspection) { return elegoo }

        var aceBuffer: [UInt8]?
        if memory.count >= AnycubicACEPayload.totalBytes {
            let aceBytes = Array(memory[0..<AnycubicACEPayload.totalBytes])
            aceBuffer = aceBytes
            if let tagData = TagFormatService.shared.decodeAnycubicACE(pages: aceBytes) {
                let snapshot = TagSnapshot.capturingPages(
                    aceBytes, firstPage: TagSnapshot.firstUserPage, lastPage: AnycubicACEPayload.totalPages - 1)
                inspection.rawMemory = TagInspection.RawMemory(snapshot: snapshot)
                return ScanResult(cardUID: uid, tagData: tagData, format: .anycubicACE, tagSnapshot: snapshot)
            }
        }

        // The TigerTag buffer, as the iPhone read builds it: pages 0-3 stay zero.
        let tigerEnd = (TigerTagPayload.readPages.max()! + 4) * TigerTagPayload.bytesPerPage
        var tigerBuffer: [UInt8]?
        if memory.count >= tigerEnd {
            let buffer = [UInt8](repeating: 0, count: TigerTagPayload.firstUserPageOffset)
                + memory[TigerTagPayload.firstUserPageOffset..<tigerEnd]
            tigerBuffer = buffer
            let tigerBytes = Array(buffer[TigerTagPayload.firstUserPageOffset...])
            let tigerMemory = TagInspection.RawMemory(
                firstUnit: TagSnapshot.firstUserPage, unitSize: TagSnapshot.bytesPerPage, bytes: tigerBytes)

            if TigerTagPayload.variant(of: tigerBytes) == .initTag {
                inspection.rawMemory = tigerMemory
                return ScanResult(cardUID: uid, tagData: nil, format: nil)
            }
            if let tagData = TagFormatService.shared.decodeTigerTag(dataFromPage4: tigerBytes) {
                inspection.rawMemory = tigerMemory
                return ScanResult(
                    cardUID: uid, tagData: tagData, format: .tigerTag,
                    tagSnapshot: TagSnapshot.capturingPages(
                        tigerBytes, firstPage: TagSnapshot.firstUserPage,
                        lastPage: TagSnapshot.firstUserPage
                            + TigerTagPayload.totalByteCount / TigerTagPayload.bytesPerPage - 1),
                    tigerTagInfo: TigerTagInfo(
                        variant: TigerTagPayload.variant(of: tigerBytes) ?? .tigerTag,
                        signature: TigerTagSignature.verify(uid: Data(uidBytes(uid)), dataBytes: tigerBytes))
                )
            }
        }

        // Undecoded. The widest raw read decides whether the tag is empty or
        // unknown; a read that did not cover it proves neither.
        let isBlank = tigerBuffer.map {
            TagDumpDecode.isBlank(in: $0, from: TigerTagPayload.firstUserPageOffset)
        } ?? false
        if let tigerBuffer {
            inspection.rawMemory = TagInspection.RawMemory(snapshot: TagSnapshot.capturingPages(
                tigerBuffer, firstPage: TagSnapshot.firstUserPage, lastPage: TigerTagPayload.readPages.max()! + 3))
        }
        return ScanResult(
            cardUID: uid, tagData: nil, format: nil,
            rawPageLogBytes: nfc.trimmedRawPageLogBytes(from: tigerBuffer.map { Data($0) })
                ?? nfc.trimmedRawPageLogBytes(from: aceBuffer.map { Data($0) }),
            isBlankTag: isBlank
        )
    }

    /// The ELEGOO block at pages 4-35, with pages 0-3 zero as the iPhone read leaves them.
    private func elegooResult(memory: [UInt8], uid: String, inspection: inout TagInspection) -> ScanResult? {
        let end = (ElegooPayload.readPages.max()! + 4) * ElegooPayload.bytesPerPage
        guard memory.count >= end else { return nil }
        let buffer = [UInt8](repeating: 0, count: 16) + memory[16..<end]
        guard let tagData = TagFormatService.shared.decodeElegoo(pages: buffer) else { return nil }
        let snapshot = TagSnapshot.capturingPages(
            buffer, firstPage: TagSnapshot.firstUserPage, lastPage: end / ElegooPayload.bytesPerPage - 1)
        inspection.rawMemory = TagInspection.RawMemory(snapshot: snapshot)
        return ScanResult(cardUID: uid, tagData: tagData, format: .elegoo, tagSnapshot: snapshot)
    }

    // MARK: - NDEF on Type 2 pages

    /// The records of the tag's NDEF message, nil when the tag has no readable
    /// one (no capability container, no message, or a message that does not parse).
    private func ndefRecords(in memory: [UInt8]) -> [NDEFRecordSnapshot]? {
        guard memory.count > 16, memory[12] == 0xE1 else { return nil }
        // Lock and memory control TLVs (0x01, 0x02) sit ahead of the message on
        // some tags; step over them.
        var start = 16
        while start + 1 < memory.count, memory[start] == 0x01 || memory[start] == 0x02 {
            start += 2 + Int(memory[start + 1])
        }
        guard let message = TagDumpDecode.ndefMessageBytes(in: memory, from: start) else { return nil }
        return Type2NDEF.records(fromMessageBytes: message)
    }

    func ndefAccess(_ memory: [UInt8]) -> TagInspection.NDEFAccess {
        guard memory.count >= 16, memory[12] == 0xE1 else { return .notSupported }
        return memory[15] & 0x0F == 0 ? .readWrite : .readOnly
    }

    private func mimeType(of record: NDEFRecordSnapshot) -> String? {
        nfc.getMimeType(from: record.record())
    }

    private func payloadData(of record: NDEFRecordSnapshot) -> Data? {
        nfc.getPayloadData(from: record.record())
    }
}
