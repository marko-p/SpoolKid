//
//  PrinterTagSession+Write.swift
//  SpoolKid
//
//  Purpose: The write side of a printer tag session. One write is: read the
//  tag, check with the iPhone path's own guards, build pages, write, report.
//  Every refusal and failure message comes from `NFCManager`'s existing
//  wording; nothing here decides what a format's pages contain.
//
//  `allowConfig` is never sent. No iPhone writer writes above the last user
//  page: the ACE writes pages 4-31, TigerTag 4-39, ELEGOO 4-39 and the NDEF
//  formats from page 4 (all at or below NTAG213's last user page, 39), and the
//  iPhone path never authenticates with a password either. A write that would
//  reach past the tag's user memory is refused before the plugin is asked.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

extension PrinterTagSession {

    private typealias PageWrites = [(page: Int, data: Data)]

    /// Either the pages to send or the message that refuses the write.
    private enum Plan {
        case pages(PageWrites)
        case refused(String)
    }

    private enum Kind { case filament, clear, clone }

    static let unidentifiedBlankTagMessage =
        "This tag's type could not be identified, so SpoolKid won't format it. Use the iPhone."

    func perform(_ write: NFCManager.PendingWrite, blockedUIDs: Set<String>) async -> PrinterWriteOutcome {
        let kind: String = switch write {
        case .filament(_, let format, _): "write-\(format.rawValue)"
        case .clear: "clear"
        case .clone: "clone"
        case .location: "location"
        }
        trace("\(kind).start")
        let outcome = await run(write, blockedUIDs: blockedUIDs)
        trace("\(kind).end", ["outcome": outcome.traceName])
        return outcome
    }

    private func run(_ write: NFCManager.PendingWrite, blockedUIDs: Set<String>) async -> PrinterWriteOutcome {
        if let error = notReadyError { return .failed(message: error.message(toolhead: toolhead)) }
        if case .location = write { return .refused(message: "Location tags are written with the iPhone.") }
        // The printer reaches only 7-byte-UID (Type 2) tags, and the plugin refuses
        // to read a MIFARE Classic one, so the printer's own report decides first.
        if let reportedUID = reportedToolhead?.tagUID, reportedUID.count == 8 {
            return .refused(message: unwritableTagMessage())
        }

        // 1. Read first: the tag's UID, size and current content.
        let read: PrinterTagRead
        switch await fetch() {
        case .failure(let error): return .failed(message: error.message(toolhead: toolhead))
        case .success(let tagRead): read = tagRead
        }

        // Also checked on what the plugin read, for a printer that reported no UID.
        if read.uid.count != 14 { return .refused(message: unwritableTagMessage()) }

        switch write {
        case .filament(let data, let format, _):
            return await writeFilament(data, format: format, read: read, blockedUIDs: blockedUIDs)
        case .location:
            return .refused(message: "Location tags are written with the iPhone.")
        case .clear(let expectedUID, let zeroPages):
            return await clear(expectedUID: expectedUID, zeroPages: zeroPages, read: read)
        case .clone(let snapshot, let sourceUID, let cloneBlocked, let allowedUID):
            return await clone(snapshot, sourceUID: sourceUID, blockedUIDs: cloneBlocked.union(blockedUIDs),
                               allowedUID: allowedUID, read: read)
        }
    }

    /// A 4-byte UID is MIFARE Classic, called a Snapmaker tag when the toolhead is also official.
    private func unwritableTagMessage() -> String {
        reportedToolhead?.isOfficial == true
            ? "Snapmaker tags can't be rewritten."
            : "This tag type can't be written by the printer."
    }

    // MARK: - Filament

    private func writeFilament(_ data: FilamentTagData, format: TagFormat, read: PrinterTagRead,
                               blockedUIDs: Set<String>) async -> PrinterWriteOutcome {
        guard format.canWrite else {
            return .refused(message: "SpoolKid can read \(format.displayName) tags but cannot write them.")
        }
        if let refusal = NFCManager.writeRefusal(for: data, format: format) { return .refused(message: refusal) }

        let uid = hardwareUID(of: read)
        let blocked = Set(blockedUIDs.map(SpoolMappingService.normalizeUID))
        if case .blocked(let blockedUID) = NFCManager.locationWriteDecision(uid: uid, blockedUIDs: blocked) {
            return .blocked(uid: blockedUID)
        }

        let memory = memory(of: read)
        let plan: Plan
        switch format {
        case .anycubicACE: plan = anycubicACEPlan(data, read: read, memory: memory)
        case .tigerTag: plan = rawPlan(data, format: .tigerTag, minChipPageCount: TigerTagPayload.minChipPageCount,
                                       read: read, memory: memory)
        case .elegoo: plan = rawPlan(data, format: .elegoo, minChipPageCount: ElegooPayload.minChipPageCount,
                                     read: read, memory: memory)
        case .openSpool, .openPrintTag, .openTag3D: plan = ndefPlan(data, format: format, read: read, memory: memory)
        }
        guard case .pages(let pages) = plan else {
            if case .refused(let message) = plan { return .refused(message: message) }
            return .refused(message: "Nothing to write.")
        }
        return await transmit(pages, uid: uid, kind: .filament)
    }

    /// The ACE writes pages 4-31, highest first, and asks the tag before each
    /// page lands whether it is locked or password-protected (`handleACEWrite`).
    private func anycubicACEPlan(_ data: FilamentTagData, read: PrinterTagRead, memory: [UInt8]) -> Plan {
        let name = TagFormat.anycubicACE.displayName
        let pages = NFCManager.rawWriteOrder(AnycubicACEPayload.encodePages(from: data))
        guard let lastPage = pages.first?.page else {
            return .refused(NFCManager.rawWriteRefusalMessage(.encodeFailed, formatName: name))
        }
        if lastPage > 255 { return .refused(NFCManager.pageLimitMessage(lastPage)) }
        // The iPhone lets the chip refuse; the plugin would answer protected_page.
        if lastPage > read.geometry.lastUserPage {
            return .refused(NFCManager.rawWriteRefusalMessage(.tooSmall, formatName: name))
        }
        switch writeBlock(read: read, memory: memory, throughPage: lastPage) {
        case .locked?:
            return .refused(NFCManager.rawWriteRefusalMessage(.locked, formatName: name))
        case .passwordProtected?:
            return .refused(NFCManager.aceWritePasswordMessage)
        default:
            return .pages(pages)
        }
    }

    /// TigerTag and ELEGOO: `rawFilamentWritePages` in `rawWriteOrder`, every
    /// refusal before a byte lands (`handleRawFilamentWrite`).
    private func rawPlan(_ data: FilamentTagData, format: TagFormat, minChipPageCount: Int,
                         read: PrinterTagRead, memory: [UInt8]) -> Plan {
        let name = format.displayName
        let pages = NFCManager.rawWriteOrder(NFCManager.rawFilamentWritePages(for: data, format: format) ?? [])
        guard let lastPage = pages.first?.page else {
            return .refused(NFCManager.rawWriteRefusalMessage(.encodeFailed, formatName: name))
        }
        if lastPage > 255 { return .refused(NFCManager.pageLimitMessage(lastPage)) }
        if let pageCount = knownPageCount(of: read), pageCount < minChipPageCount {
            return .refused(NFCManager.rawWriteRefusalMessage(.tooSmall, formatName: name))
        }
        if lastPage > read.geometry.lastUserPage {
            return .refused(NFCManager.rawWriteRefusalMessage(.tooSmall, formatName: name))
        }
        if let block = writeBlock(read: read, memory: memory, throughPage: lastPage) {
            return .refused(NFCManager.rawWriteRefusalMessage(block, formatName: name))
        }
        return .pages(pages)
    }

    /// OpenSpool, OpenTag3D and OpenPrintTag as one NDEF message packed onto
    /// the Type 2 pages. The iPhone path lays OpenPrintTag out to fill the
    /// tag's capacity on any NDEF tag, so the same layout is used here.
    private func ndefPlan(_ data: FilamentTagData, format: TagFormat, read: PrinterTagRead, memory: [UInt8]) -> Plan {
        guard let payload = TagFormatService.shared.encode(data: data, format: format) else {
            return .refused(NFCManager.rawWriteRefusalMessage(.encodeFailed, formatName: format.displayName))
        }
        guard let mimeType = format.mimeType else {
            return .refused("\(format.displayName) does not use NDEF.")
        }
        if let refusal = ndefRefusal(memory: memory, allowBlank: true, read: read) { return .refused(refusal) }

        let urlString = format == .openPrintTag ? data.tagURL : nil
        let capacity = ndefCapacity(read.geometry)
        var records = NFCManager.ndefRecords(mimePayload: payload, mimeType: mimeType, urlString: urlString)
        if format == .openPrintTag, capacity > 0 {
            guard let laidOut = OpenPrintTagLayout.layout(
                for: data, urlString: urlString, capacity: capacity, isSLIX2: false) else {
                let needed = Type2NDEF.messageBytes(for: records.map(NDEFRecordSnapshot.init(record:))).count
                let room = OpenPrintTagLayout.messageCeiling(capacity: capacity, isSLIX2: false)
                return .refused("Tag is too small. Needs \(needed) bytes but tag only has \(room) bytes available.")
            }
            records = NFCManager.ndefRecords(mimePayload: laidOut.payload, mimeType: mimeType, urlString: urlString)
        }

        switch ndefPages(records.map(NDEFRecordSnapshot.init(record:)), read: read, memory: memory) {
        case .refused(let message):
            return .refused(message)
        case .pages(let pages):
            if let last = pages.map(\.page).max(),
               writeBlock(read: read, memory: memory, throughPage: last) == .passwordProtected {
                return .refused(NFCManager.rawWriteRefusalMessage(.passwordProtected, formatName: format.displayName))
            }
            return .pages(pages)
        }
    }

    // MARK: - Clear

    private func clear(expectedUID: String?, zeroPages: [Int], read: PrinterTagRead) async -> PrinterWriteOutcome {
        let uid = hardwareUID(of: read)
        // A nil expectation clears whatever is presented.
        if let expectedUID, SpoolMappingService.normalizeUID(expectedUID) != SpoolMappingService.normalizeUID(uid) {
            return .wrongTag(uid: uid)
        }
        let memory = memory(of: read)

        // A raw-format tag is emptied by zeroing the pages its scan saw, behind
        // the guards a clone runs (`rawClear`).
        if !zeroPages.isEmpty {
            let pages = NFCManager.clearPagePlan(zeroPages: zeroPages)
            guard let lastPage = pages.first?.page, lastPage <= 255, lastPage <= read.geometry.lastUserPage else {
                return .failed(message: NFCManager.noErasablePagesMessage)
            }
            switch writeBlock(read: read, memory: memory, throughPage: lastPage) {
            case .locked?:
                return .failed(message: NFCManager.clearLockedMessage)
            case .passwordProtected?:
                return .failed(message: NFCManager.clearPasswordMessage)
            default:
                return await transmit(pages, uid: uid, kind: .clear)
            }
        }

        // Otherwise one empty NDEF record, the canonical erased state.
        if let refusal = ndefRefusal(memory: memory, allowBlank: false, read: read) { return .failed(message: refusal) }
        let empty = NDEFRecordSnapshot(typeNameFormat: 0, type: Data(), identifier: Data(), payload: Data())
        guard case .pages(let pages) = ndefPages([empty], read: read, memory: memory) else {
            return .failed(message: "Tag is not writable.")
        }
        if let last = pages.map(\.page).max(),
           writeBlock(read: read, memory: memory, throughPage: last) == .passwordProtected {
            return .failed(message: NFCManager.rawWriteRefusalMessage(.passwordProtected, formatName: ""))
        }
        return await transmit(pages, uid: uid, kind: .clear)
    }

    // MARK: - Clone

    private func clone(_ snapshot: TagSnapshot, sourceUID: String?, blockedUIDs: Set<String>,
                       allowedUID: String?, read: PrinterTagRead) async -> PrinterWriteOutcome {
        let uid = hardwareUID(of: read)
        switch NFCManager.cloneWriteDecision(
            targetUID: uid, sourceUID: sourceUID, blockedUIDs: blockedUIDs, allowedUID: allowedUID) {
        case .sameTag: return .sameTag
        case .blocked(let blockedUID): return .blocked(uid: blockedUID)
        case .proceed: break
        }
        let memory = memory(of: read)

        switch snapshot {
        case .ndef(let records):
            guard !records.isEmpty else { return .failed(message: "There is nothing on the scanned tag to copy.") }
            if let refusal = ndefRefusal(memory: memory, allowBlank: true, read: read) { return .failed(message: refusal) }
            switch ndefPages(records, read: read, memory: memory) {
            case .refused(let message):
                return .failed(message: message)
            case .pages(let pages):
                return await transmit(pages, uid: uid, kind: .clone)
            }
        case .rawPages(let firstPage, _):
            // Pages 0-3 hold the UID, locks and capability container; a copy never writes them.
            guard firstPage >= TagSnapshot.firstUserPage else {
                return .failed(message: "There is nothing on the scanned tag to copy.")
            }
            let pages = NFCManager.rawWriteOrder(snapshot.pageWrites)
            guard let lastPage = pages.first?.page, lastPage <= 255 else {
                return .failed(message: "There is nothing on the scanned tag to copy.")
            }
            if let header = header(of: memory), NFCManager.rawWriteHeaderAllowsWrite(header) == false {
                return .failed(message: NFCManager.cloneLockedMessage)
            }
            // The user memory ends at the last user page, six before the chip's last page.
            guard NFCManager.rawCloneFits(lastPage: lastPage, pageCount: read.geometry.lastUserPage + 6) else {
                return .failed(message: NFCManager.cloneTooSmallMessage)
            }
            if writeBlock(read: read, memory: memory, throughPage: lastPage) == .passwordProtected {
                return .failed(message: NFCManager.clonePasswordMessage)
            }
            return await transmit(pages, uid: uid, kind: .clone)
        }
    }

    // MARK: - Shared

    /// Sends the pages and reports. `.success(n)` means every page holds its
    /// bytes and was verified, whatever `n` is, so it is never compared with
    /// the page count.
    private func transmit(_ pages: PageWrites, uid: String, kind: Kind) async -> PrinterWriteOutcome {
        let result = await gateway.writeTag(toolhead: toolhead, expectedUID: uid, pages: pages,
                                            password: nil, allowConfig: false)
        switch result {
        case .success:
            return .written(uid: uid)
        case .failure(let error):
            traceFailure("write", error, pagesTotal: pages.count)
            return .failed(message: failureMessage(error, totalPages: pages.count, kind: kind))
        }
    }

    /// A partial write says how far it got, in the iPhone path's words; a lost
    /// connection cannot say, so it names a possibly partial tag.
    private func failureMessage(_ error: PrinterTagError, totalPages: Int, kind: Kind) -> String {
        let cause = error.message(toolhead: toolhead)
        switch error {
        case .writeFailed(let written), .verifyFailed(let written):
            return kind == .clone
                ? NFCManager.rawCloneFailureMessage(pagesWritten: written, totalPages: totalPages, refused: false, cause: cause)
                : NFCManager.rawWriteFailureMessage(pagesWritten: written, totalPages: totalPages, cause: cause)
        case .protectedPage, .authFailed:
            return kind == .clone
                ? NFCManager.rawCloneFailureMessage(pagesWritten: 0, totalPages: totalPages, refused: true, cause: cause)
                : cause
        default:
            return cause
        }
    }

    /// Why an NDEF write cannot go ahead on this tag, in `ndefStatusRefusal`'s
    /// words. A blank capability container is a tag waiting to be formatted, but
    /// only when the chip's type is known: page 3 is one-time programmable, and
    /// without GET_VERSION the geometry would be a zero-size container.
    private func ndefRefusal(memory: [UInt8], allowBlank: Bool, read: PrinterTagRead) -> String? {
        if let header = header(of: memory), NFCManager.rawWriteHeaderAllowsWrite(header) == false {
            return NFCManager.ndefStatusRefusal(.readOnly, preparedBlankTag: false)
        }
        guard memory.count >= 16 else { return NFCManager.ndefStatusRefusal(.notSupported, preparedBlankTag: false) }
        let container = memory[12..<16]
        if container.allSatisfy({ $0 == 0 }) {
            guard allowBlank else { return NFCManager.ndefStatusRefusal(.notSupported, preparedBlankTag: false) }
            return knownPageCount(of: read) == nil ? Self.unidentifiedBlankTagMessage : nil
        }
        if container.first != 0xE1 { return NFCManager.ndefStatusRefusal(.notSupported, preparedBlankTag: false) }
        if memory[15] & 0x0F != 0 { return NFCManager.ndefStatusRefusal(.readOnly, preparedBlankTag: false) }
        return nil
    }

    /// The pages for `records`, or the "too small" refusal. The capability
    /// container is written only to a tag whose container is blank: its bytes
    /// are one-time programmable, so a formatted tag keeps its own.
    private func ndefPages(_ records: [NDEFRecordSnapshot], read: PrinterTagRead, memory: [UInt8]) -> Plan {
        let message = Type2NDEF.messageBytes(for: records)
        let container = memory.count >= 16 ? Array(memory[12..<16]) : [0, 0, 0, 0]
        guard message.count <= ndefCapacity(read.geometry),
              let pages = Type2NDEF.pages(forMessageBytes: message, geometry: read.geometry,
                                          currentCapabilityContainer: container) else {
            return .refused("Tag is too small. Needs \(message.count) bytes but tag only has \(ndefCapacity(read.geometry)) bytes available.")
        }
        let isBlank = container.allSatisfy { $0 == 0 }
        return .pages(pages.filter { $0.page != 3 || isBlank })
    }
}
