//
//  NFCManager.swift
//  SpoolKid
//
//  Purpose: Core logic for interacting with CoreNFC.
//  Responsibilities:
//  - Managing NFCTagReaderSession for every read and every write. The NDEF
//    session type is deliberately unused: it cannot report a tag's UID, so a
//    write over it can never be linked back to the spool it came from.
//  - Reading NDEF messages and decoding them into `FilamentTagData`.
//  - Auto-detecting the tag format on read.
//  - Encoding `FilamentTagData` and writing to NFC tags in the selected format.
//  - Emitting a structured `ScanResult` for the Scan Result Hub.
//  - Handling errors and session invalidation.
//
//  Scan flow:
//  - `startScanning()`: unified scan via NFCTagReaderSession (iso14443).
//    Detects MIFARE Ultralight/NTAG (NDEF).
//    Order: NDEF (location, then structured formats, then a link — on MIFARE the
//    raw ELEGOO block is tried before a link is accepted); otherwise raw ELEGOO,
//    then raw ACE, then UID-only.
//    For MIFARE Classic tags: emits UID-only result (data encrypted on iOS).
//  - `writeTag(data:)`: tag session for every format; NDEF formats write an
//    NDEF message through the detected tag, ACE writes raw pages.
//  - `cloneTag(_:sourceUID:blockedUIDs:allowedUID:)`: writes what a scan read
//    (`TagSnapshot`) verbatim — NDEF records, or raw pages highest first.
//
//  Important for Contributors:
//  - iOS requires a valid provisioning profile with "NFC Tag Reading" capability.
//  - NFC only works on physical devices, not the simulator.
//  - The `Info.plist` must contain `NFCReaderUsageDescription`.
//  - The entitlements must include the `TAG` format for raw tag access.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC
import Combine
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "NFCManager")

// Note: NFCManager intentionally does NOT use @MainActor on the class level.
// CoreNFC invokes delegate callbacks on background threads,
// so the delegate methods must remain callable off the main thread. Instead,
// @Published property updates are explicitly dispatched to the main queue.
// Internal mutable state (isWriting, tagDataToWrite) is protected by a serial queue.
class NFCManager: NSObject, ObservableObject, NFCTagReaderSessionDelegate {

    enum RawReadFormatAttempt: Equatable {
        case elegoo
        case anycubicACE
    }

    enum RawReadFollowupAction: Equatable {
        case stop
        case tryAnycubicACE
        case emitUIDOnly
    }

    static let rawReadAttemptOrder: [RawReadFormatAttempt] = [.elegoo, .anycubicACE]

    /// The printer the toolhead readers belong to, set once from `ContentView`.
    static weak var printerTagGateway: PrinterTagGateway?

    @Published var alertMessage = ""
    @Published var isScanning = false
    /// Structured result of the most recent scan. Emitted for every completed read.
    @Published var scanResult: ScanResult?
    /// The last completed raw dump. Diagnostics only — no normal scan path
    /// reads this.
    @Published var tagDumpResult: TagDump?
    @Published var tagDumpError: String?
    @Published var lastWriteSucceeded = false
    /// The hardware UID of the tag the last successful filament write landed
    /// on. Callers use it to link the tag to the spool they wrote it from —
    /// which is only possible because writes run on the tag session.
    /// `nil` while no write has succeeded, and cleared at the start of each one.
    @Published var lastWrittenTagUID: String?

    /// What a location write did. `blocked` carries the UID so the caller can
    /// offer to unlink it and try again — see Task 14.
    nonisolated enum LocationWriteResult: Equatable, Sendable {
        case written(uid: String?)
        case blocked(uid: String)
        case failed(String)
    }

    @Published private(set) var lastLocationWrite: LocationWriteResult?

    /// What an erase did. `wrongTag` means a DIFFERENT tag was presented than
    /// the one the caller meant to clear — refused rather than wiped, because
    /// an erase the user did not ask for is not recoverable from this screen.
    nonisolated enum TagClearResult: Equatable, Sendable {
        case cleared(uid: String?)
        case wrongTag(uid: String?)
        case failed(String)
    }

    @Published private(set) var lastTagClear: TagClearResult?

    /// What a clone did. `blocked` carries the UID so the caller can offer to
    /// unlink its owner and try again with that one tag allowed.
    nonisolated enum CloneWriteResult: Equatable, Sendable {
        case written(uid: String?)
        case blocked(uid: String)
        case sameTag
        case failed(String)
    }

    @Published private(set) var lastClone: CloneWriteResult?

    nonisolated enum LocationWriteDecision: Equatable, Sendable {
        case proceed
        case blocked(uid: String)
    }

    /// Whether a location write may overwrite the presented tag.
    ///
    /// A `nil` UID proceeds: ISO 15693 tags can arrive without one, and
    /// refusing every such write would make location tags unwritable on Type 5
    /// hardware. The read-side heal still covers that rarer case.
    ///
    /// `blockedUIDs` arrives already normalized from the caller.
    nonisolated static func locationWriteDecision(
        uid: String?, blockedUIDs: Set<String>
    ) -> LocationWriteDecision {
        guard let uid else { return .proceed }
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard blockedUIDs.contains(normalized) else { return .proceed }
        return .blocked(uid: normalized)
    }

    /// Whether an OpenPrintTag write should tell the user the printer countdown
    /// did not fit: the tag got no aux region, and the data had something to
    /// count (a consumed weight, or a length computable from its net weight,
    /// density and diameter).
    nonisolated static func countdownDidNotFit(data: FilamentTagData, auxWritten: Bool) -> Bool {
        guard !auxWritten else { return false }
        if FilamentTagData.statedMeasurement(data.consumedWeight) != nil { return true }
        return OpenPrintTagLayout.fullLength(
            netWeight: data.nominalNetWeight, density: data.density, diameter: data.diameter) != nil
    }

    nonisolated enum CloneWriteDecision: Equatable, Sendable {
        case proceed
        case sameTag
        case blocked(uid: String)
    }

    /// Whether a clone may be written onto the presented tag.
    ///
    /// The source tag is refused first, whenever both UIDs are known: copying a tag onto
    /// itself is never what the user meant. `blockedUIDs` are tags owned by
    /// something other than the source's owner — writing one would leave that
    /// spool or shelf claiming a tag that no longer carries its data.
    /// `allowedUID` is the one blocked tag the user agreed to take.
    ///
    /// A `nil` UID proceeds: ISO 15693 tags can arrive without one, as in
    /// `locationWriteDecision`.
    nonisolated static func cloneWriteDecision(
        targetUID: String?,
        sourceUID: String?,
        blockedUIDs: Set<String>,
        allowedUID: String?
    ) -> CloneWriteDecision {
        guard let targetUID else { return .proceed }
        let target = SpoolMappingService.normalizeUID(targetUID)
        guard !target.isEmpty else { return .proceed }

        if let sourceUID, SpoolMappingService.normalizeUID(sourceUID) == target {
            return .sameTag
        }
        if let allowedUID, SpoolMappingService.normalizeUID(allowedUID) == target {
            return .proceed
        }
        let blocked = Set(blockedUIDs.map(SpoolMappingService.normalizeUID))
        return blocked.contains(target) ? .blocked(uid: target) : .proceed
    }

    /// Whether a raw copy ending at `lastPage` stays in the chip's user memory.
    ///
    /// On NTAG213, 215 and 216 user memory ends six pages before the last: a
    /// dynamic lock page, then CFG0, CFG1, PWD and PACK (see `configPage`). An
    /// unknown page count proceeds only because a clone writes its highest page
    /// first (`rawWriteOrder`): a chip without that page refuses the first
    /// WRITE, before anything lands. The ACK check alone would not be enough —
    /// Ultralight EV1 48-byte and NTAG210 keep CFG0, CFG1, PWD and PACK at pages
    /// 16-19, and accept writes there.
    nonisolated static func rawCloneFits(lastPage: Int, pageCount: Int?) -> Bool {
        guard let pageCount else { return true }
        return lastPage <= pageCount - 6
    }

    /// The order every raw page write goes out in — a clone's and the ACE
    /// write's: highest first. A chip smaller than the write then refuses the
    /// very first WRITE, so nothing lands on it, and a write interrupted
    /// part-way leaves its lowest pages — the ACE header at page 4 — unwritten,
    /// so on a blank target it cannot read as a whole spool.
    nonisolated static func rawWriteOrder(_ pages: [(page: Int, data: Data)]) -> [(page: Int, data: Data)] {
        pages.sorted { $0.page > $1.page }
    }

    /// Whether a raw page write (a clone, or the ACE write) may go ahead, from
    /// the READ reply at page 0 (pages 0-3).
    ///
    /// False when static lock bits cover any of pages 4-15 (byte 10's upper
    /// nibble, byte 11) or the capability container's write-access nibble is not
    /// 0 — the NDEF path honours a read-only capability container, so a raw write
    /// must too. Nil when the reply is not a full READ; the write then proceeds,
    /// protected by writing its highest page first. Dynamic lock bits are not read.
    static func rawWriteHeaderAllowsWrite(_ headerRead: Data) -> Bool? {
        guard isValidRawReadResponse(headerRead) else { return nil }
        let bytes = [UInt8](headerRead)
        let locksPages4To7 = (bytes[10] & 0xF0) != 0
        let locksPages8To15 = bytes[11] != 0
        let capabilityReadOnly = (bytes[15] & 0x0F) != 0
        return !(locksPages4To7 || locksPages8To15 || capabilityReadOnly)
    }

    /// What a raw clone's failure tells the user. Pages go highest first, so a
    /// refusal before any page landed means the chip turned the copy down, and
    /// any page landed means the copy was cut short. A lost connection on the
    /// first page cannot say whether that page landed, so it keeps its cause.
    nonisolated static func rawCloneFailureMessage(pagesWritten: Int, totalPages: Int, refused: Bool, cause: String) -> String {
        if pagesWritten > 0 {
            return "The copy was cut short after \(pagesWritten) of \(totalPages) pages, so the tag is only partly written. Clone it again."
        }
        if refused {
            return "The tag refused the copy before anything was written. It may be too small or protected — use a blank NTAG213 or larger."
        }
        return "The tag was lost before the copy could be confirmed (\(cause)). Hold it still and clone again."
    }

    /// What a stopped raw-page write (ACE, TigerTag, ELEGOO) tells the user. Any page landed means the tag
    /// now mixes new pages with whatever it held before, so it says so; nothing
    /// landed keeps `writePages`' own message — a refusal, or a lost connection
    /// on the first page, which cannot say whether that page landed.
    nonisolated static func rawWriteFailureMessage(pagesWritten: Int, totalPages: Int, cause: String) -> String {
        guard pagesWritten > 0 else { return cause }
        return "The write was cut short after \(pagesWritten) of \(totalPages) pages, so the tag is only partly written. Write it again."
    }

    /// Messages shared by the iPhone handlers and the printer session.
    nonisolated static let aceWritePasswordMessage = "This tag is password-protected, as factory Anycubic tags are. SpoolKid can read it but cannot write it — use a blank NTAG213 or NTAG215."
    nonisolated static let clearLockedMessage = "This tag is locked or read-only, so it cannot be emptied."
    nonisolated static let clearPasswordMessage = "This tag is password-protected, as factory Anycubic tags are. SpoolKid can read it but cannot write it."
    nonisolated static let cloneLockedMessage = "This tag is locked or read-only, so it cannot hold a copy. Use a blank NTAG213 or NTAG215."
    nonisolated static let cloneTooSmallMessage = "This tag is too small to hold the copy. Use an NTAG213 or larger."
    nonisolated static let clonePasswordMessage = "This tag is password-protected, so it cannot hold a copy. Use a blank NTAG213 or NTAG215."
    nonisolated static let noErasablePagesMessage = "This tag has no erasable pages."
    nonisolated static func pageLimitMessage(_ page: Int) -> String {
        "Internal error: page number \(page) exceeds tag limit."
    }

    /// Why a raw filament write (TigerTag, ELEGOO) stopped before a page landed.
    nonisolated enum RawWriteRefusal { case encodeFailed, tooSmall, locked, passwordProtected }

    /// What a raw filament write refused before writing tells the user.
    nonisolated static func rawWriteRefusalMessage(_ refusal: RawWriteRefusal, formatName: String) -> String {
        switch refusal {
        case .encodeFailed:
            return "Failed to encode data for \(formatName)."
        case .tooSmall:
            return "This tag is too small for \(formatName) (needs NTAG213 or larger)."
        case .locked:
            return "This tag is locked or read-only, so SpoolKid cannot write it. Use a blank NTAG213 or NTAG215."
        case .passwordProtected:
            return "This tag is password-protected, so SpoolKid cannot write it."
        }
    }

    /// Why `data` cannot be written in `format`, found before a session opens
    /// so the user is not told to hold a tag that will be refused. Nil when it
    /// can. Only a raw filament format can refuse its data this way.
    static func writeRefusal(for data: FilamentTagData, format: TagFormat) -> String? {
        guard let pages = rawFilamentWritePages(for: data, format: format), pages.isEmpty else { return nil }
        if format == .elegoo,
           ElegooCanvasCatalog.entry(forTagMaterial: data.material, subtype: data.subtype) == nil {
            return "\(data.material) has no Canvas filament, so it cannot be written as an ELEGOO tag. Choose a Canvas filament in Write Tag, or write another format."
        }
        return rawWriteRefusalMessage(.encodeFailed, formatName: format.displayName)
    }

    /// The line a finished write adds to its success message. ELEGOO names the
    /// Canvas filament, which the spool form's Write Tag chooses without showing it.
    static func writtenNote(for data: FilamentTagData, format: TagFormat) -> String {
        guard format == .elegoo,
              let entry = ElegooCanvasCatalog.entry(forTagMaterial: data.material, subtype: data.subtype)
        else { return "" }
        return "\nCanvas filament: \(entry.name)"
    }

    /// The pages a raw filament write sends, nil for a format written another
    /// way (NDEF, or the ACE's own path). Empty when the data cannot be encoded.
    static func rawFilamentWritePages(for data: FilamentTagData, format: TagFormat) -> [(page: Int, data: Data)]? {
        switch format {
        case .tigerTag:
            // Data pages 4–23 plus zeroed signature pages 24–39: a reused
            // signed chip reads unsigned, never invalid.
            let zero = Data(repeating: 0, count: TigerTagPayload.bytesPerPage)
            return TigerTagPayload.encodePages(from: data) + (24...39).map { ($0, zero) }
        case .elegoo:
            return ElegooPayload.encodePages(from: data)
        case .openSpool, .openPrintTag, .openTag3D, .anycubicACE:
            return nil
        }
    }

    /// What an NDEF write refused by `queryNDEFStatus` tells the user. A tag
    /// SpoolKid formatted during this tap was changed, so "not writable" would
    /// be false: it is set up, and iOS sees the new container on the next tap.
    nonisolated static func ndefStatusRefusal(_ status: NFCNDEFStatus, preparedBlankTag: Bool) -> String {
        if status == .readOnly { return "Tag is read-only (write-protected)." }
        if preparedBlankTag { return "This blank tag is now set up. Hold it near again to write." }
        return "Tag is not writable."
    }

    /// Backward-compatible convenience accessor. Returns the decoded filament data from `scanResult`.
    var scannedData: FilamentTagData? {
        get { scanResult?.tagData }
        set {
            // Allow callers (e.g. TagsTabView) to nil this out after consumption.
            if newValue == nil { scanResult = nil }
        }
    }

    private var tagSession: NFCTagReaderSession?
    // Thread-safe access to mutable state shared between main thread and NFC delegate callbacks.
    private let stateQueue = DispatchQueue(label: "com.spoolkid.nfcmanager.state")
    /// What the in-flight write session is carrying. One field rather than a
    /// set of loosely-related optionals, so a second kind of write cannot
    /// arrive as a second parallel set of flags.
    /// Not `Equatable`: `FilamentTagData` is Codable/Identifiable/Sendable and
    /// deliberately not Equatable, so the conformance cannot be synthesized and
    /// nothing needs it.
    nonisolated enum PendingWrite {
        case filament(FilamentTagData, TagFormat, cardUID: String?)
        case location(LocationTagPayload)
        /// Erase whatever the tag carries. `expectedUID` is the tag the caller
        /// means, so presenting a different one is refused. `zeroPages` lists
        /// the raw pages a raw-format scan's snapshot saw — when non-empty on
        /// an NTAG, the erase zeroes those pages instead of writing NDEF,
        /// through the same guards a clone runs.
        case clear(expectedUID: String?, zeroPages: [Int] = [])
        /// Write a scanned tag's bytes back verbatim. See `cloneWriteDecision`
        /// for what the three UID fields refuse and allow.
        case clone(TagSnapshot, sourceUID: String?, blockedUIDs: Set<String>, allowedUID: String?)

        var filamentData: FilamentTagData? {
            if case .filament(let data, _, _) = self { return data }
            return nil
        }
        var tagFormat: TagFormat? {
            if case .filament(_, let format, _) = self { return format }
            return nil
        }
        var cardUID: String? {
            if case .filament(_, _, let uid) = self { return uid }
            return nil
        }
        var locationPayload: LocationTagPayload? {
            if case .location(let payload) = self { return payload }
            return nil
        }
    }

    private var _pendingWrite: PendingWrite?

    private var pendingWrite: PendingWrite? {
        get { stateQueue.sync { _pendingWrite } }
        set { stateQueue.sync { _pendingWrite = newValue } }
    }

    /// Set for the duration of a Diagnostics dump session. A dump reads every
    /// page the tag will return, which no normal scan wants to pay for.
    ///
    /// Scoped to one scan like `pendingWrite` and `rejectsLocationTags`: it is
    /// cleared on the connect-success path, but the commonest exit of all —
    /// the user tapping Cancel — never reaches that path, and neither does a
    /// failed `connect(to:)` or any other invalidation. A leaked `true` would
    /// hijack the very next scan or write into a raw dump, so every other
    /// session-starting method resets it at entry, the same as `pendingWrite`.
    private var _isDumping = false
    private var isDumping: Bool {
        get { stateQueue.sync { _isDumping } }
        set { stateQueue.sync { _isDumping = newValue } }
    }

    /// Set for a scan whose ONLY acceptable answer is a spool tag — the spool
    /// form's "Scan tag to link". A location tag presented to such a scan is
    /// refused by the session itself, so iOS shows its own error sheet and
    /// fires the system error haptic, instead of reporting a successful read
    /// that the app then contradicts with an alert a moment later.
    ///
    /// The result is still emitted, because the caller's refusal alert needs
    /// the shelf's name and the tag's UID to offer a way through.
    private var _rejectsLocationTags = false
    private var rejectsLocationTags: Bool {
        get { stateQueue.sync { _rejectsLocationTags } }
        set { stateQueue.sync { _rejectsLocationTags = newValue } }
    }

    /// Set for a scan whose result reaches the Scan Result hub — the Tags
    /// tab's — so its chip is asked one more question at the end of the read
    /// (see `queryChipDetails`). The other scans skip that round trip.
    /// Scoped to one scan like `rejectsLocationTags`.
    private var _queriesChipDetails = false
    private var queriesChipDetails: Bool {
        get { stateQueue.sync { _queriesChipDetails } }
        set { stateQueue.sync { _queriesChipDetails = newValue } }
    }

    /// What the unified read in flight has learned about the tag, attached to
    /// its result by `publish`. Touched only on CoreNFC's callback queue.
    private var inspection: TagInspection?

    private var _blockedWriteUIDs: Set<String> = []
    private var blockedWriteUIDs: Set<String> {
        get { stateQueue.sync { _blockedWriteUIDs } }
        set { stateQueue.sync { _blockedWriteUIDs = newValue } }
    }

    /// Derived — a write is in flight exactly while something is pending.
    /// Replaces the separately-tracked `_isWriting`, which could disagree.
    private var isWriting: Bool { pendingWrite != nil }

    /// The data most recently passed to `writeTag(data:)`. Accessible for
    /// post-write actions.
    ///
    /// Read-only: its only former non-nil writer was `writeTag`, which now
    /// assigns `pendingWrite` instead, and the two `isWriting = false` sites
    /// never touched it. A setter here would be dead code whose one branch
    /// silently discarded a non-nil assignment. Clearing is `pendingWrite = nil`.
    var tagDataToWrite: FilamentTagData? { pendingWrite?.filamentData }

    /// The format `tagDataToWrite` is written in. Read after a successful
    /// write to record it with the Recent Tag.
    var writeFormatToUse: TagFormat? { pendingWrite?.tagFormat }
    private var writeCardUID: String? { pendingWrite?.cardUID }

    // MARK: - Public API

    /// Unified scan: uses NFCTagReaderSession to handle all tag families.
    /// Dispatches to NDEF read for NTAG/Ultralight tags; MIFARE Classic falls back to UID-only.
    /// `rejectingLocationTags` is for a scan whose only acceptable answer is a
    /// spool tag. A parameter rather than a settable property so it is scoped
    /// to one scan and cannot leak into the next one from the same manager.
    /// `queryingChipDetails` is for the scan whose result reaches the hub,
    /// where Inspect Tag can show the chip's own answer.
    func startScanning(rejectingLocationTags: Bool = false, queryingChipDetails: Bool = false,
                       reader: TagReader = .iPhone) {
        if case .toolhead(let index) = reader {
            startPrinterScan(toolhead: index, rejectingLocationTags: rejectingLocationTags)
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            WorkflowTraceStore.log(path: "nfc", step: "scan.unavailable")
            return
        }

        pendingWrite = nil
        rejectsLocationTags = rejectingLocationTags
        queriesChipDetails = queryingChipDetails
        isDumping = false
        WorkflowTraceStore.log(path: "nfc", step: "scan.start", details: [
            "mode": "unified",
            "rejectsLocationTags": String(rejectingLocationTags),
            "queriesChipDetails": String(queryingChipDetails)
        ])
        startTagSession(message: "Hold your iPhone near the NFC tag to read.")
    }

    /// Reads a tag's whole user memory for the Diagnostics explorer.
    func startTagDump(reader: TagReader = .iPhone) {
        if case .toolhead(let index) = reader {
            startPrinterDump(toolhead: index)
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            WorkflowTraceStore.log(path: "nfc", step: "scan.unavailable")
            return
        }

        pendingWrite = nil
        rejectsLocationTags = false
        queriesChipDetails = false
        isDumping = true
        DispatchQueue.main.async {
            self.tagDumpResult = nil
            self.tagDumpError = nil
        }
        startTagSession(message: "Hold your iPhone near the tag to read all of it.")
    }

    func writeTag(data: FilamentTagData, reader: TagReader = .iPhone) {
        writeTag(data: data, format: TagFormatService.shared.currentFormat, cardUID: nil, reader: reader)
    }

    func writeTag(data: FilamentTagData, format: TagFormat, reader: TagReader = .iPhone) {
        writeTag(data: data, format: format, cardUID: nil, reader: reader)
    }

    func writeTag(data: FilamentTagData, format: TagFormat, cardUID: String?, reader: TagReader = .iPhone) {
        if case .toolhead(let index) = reader {
            startPrinterWrite(.filament(data, format, cardUID: cardUID), toolhead: index)
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        // Refused here, before a session opens, rather than at the tag: the
        // encoder returns nil for a read-only format and the user learns that
        // only after being told to hold their phone against the tag.
        guard format.canWrite else {
            alertMessage = "SpoolKid can read \(format.displayName) tags but cannot write them."
            WorkflowTraceStore.log(path: "nfc", step: "write.format-unwritable", details: [
                "format": format.rawValue
            ])
            return
        }
        if let refusal = Self.writeRefusal(for: data, format: format) {
            alertMessage = refusal
            WorkflowTraceStore.log(path: "nfc", step: "write.encode-refused", details: [
                "format": format.rawValue, "material": data.material
            ])
            return
        }

        pendingWrite = .filament(data, format, cardUID: cardUID)
        isDumping = false
        DispatchQueue.main.async {
            self.lastWriteSucceeded = false
            self.lastWrittenTagUID = nil
        }

        // Every format writes over the tag session. ACE needs it for raw page
        // access; the NDEF formats need it to learn the tag's UID, which an
        // NFCNDEFReaderSession never reports.
        let message = format == .anycubicACE
            ? "Hold your iPhone near the NFC tag to write (ACE format)."
            : "Hold your iPhone near the NFC tag to write."
        startTagSession(message: message)
    }

    /// Writes a SpoolKid location record to a tag.
    ///
    /// `blockedUIDs` are the tags currently claimed by a spool. A tag whose UID
    /// is in that set is refused rather than overwritten: `card_uids` is keyed
    /// by the hardware UID and survives any rewrite, so writing here would
    /// leave the spool claiming a tag that is no longer its own.
    func writeLocationTag(_ payload: LocationTagPayload, blockedUIDs: Set<String>) {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        blockedWriteUIDs = blockedUIDs
        pendingWrite = .location(payload)
        isDumping = false
        DispatchQueue.main.async {
            self.lastWriteSucceeded = false
            self.lastLocationWrite = nil
        }
        startTagSession(message: "Hold your iPhone near the tag to make it a location tag.")
    }

    /// Erases a tag, leaving it blank.
    ///
    /// NDEF tags (OpenSpool, OpenPrintTag, OpenTag3D, location tags) are
    /// emptied with a single empty NDEF record. A raw-format scan (Anycubic
    /// ACE, TigerTag, ELEGOO) passes its snapshot's pages as `zeroPages`, and
    /// the tag is emptied by zeroing those pages — raw formats are not NDEF,
    /// so an NDEF write would be refused with a misleading "not writable"
    /// (owner report, 2026-09-18). The zeroed range is the range the format
    /// owns: the same pages a clone of the same tag proved writable.
    func clearTag(expectedUID: String?, zeroPages: [Int] = [], reader: TagReader = .iPhone) {
        if case .toolhead(let index) = reader {
            startPrinterWrite(.clear(expectedUID: expectedUID, zeroPages: zeroPages), toolhead: index)
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        pendingWrite = .clear(expectedUID: expectedUID, zeroPages: zeroPages)
        isDumping = false
        DispatchQueue.main.async {
            self.lastWriteSucceeded = false
            self.lastTagClear = nil
        }
        startTagSession(message: "Hold your iPhone near the same tag to clear it.")
    }

    /// Writes what a scan read onto the next tag presented.
    ///
    /// `sourceUID` is the scanned tag. `blockedUIDs` are tags owned by anything
    /// other than the source's owner; `allowedUID` is the one of them the user
    /// agreed to take. The caller decides what counts as owned — this only
    /// refuses.
    func cloneTag(
        _ snapshot: TagSnapshot,
        sourceUID: String?,
        blockedUIDs: Set<String>,
        allowedUID: String?,
        reader: TagReader = .iPhone
    ) {
        if case .toolhead(let index) = reader {
            guard snapshot.isCopyable else {
                alertMessage = "There is nothing on the scanned tag to copy."
                return
            }
            startPrinterWrite(.clone(snapshot, sourceUID: sourceUID, blockedUIDs: blockedUIDs, allowedUID: allowedUID),
                              toolhead: index)
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        guard snapshot.isCopyable else {
            alertMessage = "There is nothing on the scanned tag to copy."
            return
        }

        pendingWrite = .clone(snapshot, sourceUID: sourceUID, blockedUIDs: blockedUIDs, allowedUID: allowedUID)
        isDumping = false
        DispatchQueue.main.async {
            self.lastClone = nil
        }
        WorkflowTraceStore.log(path: "nfc", step: "clone.start", details: [
            "kind": snapshot.pageWrites.isEmpty ? "ndef" : "rawPages",
            "sourceUID": sourceUID ?? "",
            "allowedUID": allowedUID ?? ""
        ])
        startTagSession(message: "Hold a blank tag near your iPhone to copy onto it.")
    }

    // MARK: - Session Management

    private func startTagSession(message: String) {
        WorkflowTraceStore.log(path: "nfc", step: "session.start-tag", details: [
            "message": message,
            "pollingOptions": "iso14443,iso15693"
        ])
        tagSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
        tagSession?.alertMessage = message
        tagSession?.begin()
        DispatchQueue.main.async { self.isScanning = true }
    }

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
            WorkflowTraceStore.log(path: "nfc", step: "session.tag-invalidated", details: [
                "error": error.localizedDescription
            ])
            if let readerError = error as? NFCReaderError {
                if readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead &&
                   readerError.code != .readerSessionInvalidationErrorUserCanceled {
                    self.alertMessage = "Session invalidated: \(error.localizedDescription)"
                }
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            WorkflowTraceStore.log(path: "nfc", step: "session.tag-detect-empty")
            session.restartPolling()
            return
        }

        WorkflowTraceStore.log(path: "nfc", step: "session.tag-detect", details: [
            "tagsDetected": String(tags.count),
            "tagType": tagTypeName(tag),
            "uid": normalizedUID(from: tag) ?? ""
        ])

        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                WorkflowTraceStore.log(path: "nfc", step: "session.tag-connect-failed", details: [
                    "error": error.localizedDescription,
                    "tagType": self.tagTypeName(tag),
                    "uid": self.normalizedUID(from: tag) ?? ""
                ])
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }

            WorkflowTraceStore.log(path: "nfc", step: "session.tag-connect-success", details: [
                "tagType": self.tagTypeName(tag),
                "uid": self.normalizedUID(from: tag) ?? "",
                "isWriting": String(self.isWriting)
            ])

            if self.isDumping {
                self.isDumping = false
                // A dump without a UID cannot be told apart from any other
                // dump, and the explorer would pair two different tags as a
                // before/after of one. Refuse rather than record that.
                guard let uid = self.normalizedUID(from: tag), !uid.isEmpty else {
                    self.failDump(
                        session: session,
                        message: "This tag did not give a serial number, so its pages could not be told apart from another tag's."
                    )
                    return
                }
                // Two families, two command sets. NTAG and Ultralight are read
                // four pages at a time with READ; ISO 15693 tags — the
                // Prusament's OpenPrintTag among them — have no such command
                // and are read block by block. Everything else has neither.
                switch tag {
                case .miFare(let miFareTag):
                    self.dumpAllPages(session: session, tag: miFareTag, uid: uid)
                case .iso15693(let isoTag):
                    self.dumpAllBlocks(session: session, tag: isoTag, uid: uid)
                default:
                    self.failDump(
                        session: session,
                        message: "SpoolKid can read NTAG and Ultralight tags page by page, and ISO 15693 tags block by block. This tag is neither."
                    )
                }
                return
            }

            switch self.pendingWrite {
            case .filament(_, .anycubicACE, _):
                if case .miFare(let miFareTag) = tag {
                    self.handleACEWrite(session: session, tag: miFareTag)
                } else {
                    session.invalidate(errorMessage: "Tag type is not supported for writing.")
                }
            case .filament(_, .tigerTag, _):
                if case .miFare(let miFareTag) = tag {
                    self.handleRawFilamentWrite(
                        session: session, tag: miFareTag, format: .tigerTag,
                        minChipPageCount: TigerTagPayload.minChipPageCount
                    )
                } else {
                    session.invalidate(errorMessage: "Tag type is not supported for writing.")
                }
            case .filament(_, .elegoo, _):
                if case .miFare(let miFareTag) = tag {
                    self.handleRawFilamentWrite(
                        session: session, tag: miFareTag, format: .elegoo,
                        minChipPageCount: ElegooPayload.minChipPageCount
                    )
                } else {
                    session.invalidate(errorMessage: "Tag type is not supported for writing.")
                }
            case .filament:
                self.handleNDEFWrite(session: session, tag: tag)
            case .location:
                self.handleLocationWrite(session: session, tag: tag)
            case .clear:
                self.handleClearWrite(session: session, tag: tag)
            case .clone:
                self.handleCloneWrite(session: session, tag: tag)
            case nil:
                self.handleUnifiedRead(session: session, tag: tag)
            }
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active, waiting for tag
    }

    // MARK: - Unified Read (NDEF → ELEGOO raw → ACE raw → UID-only)

    /// Main read dispatcher for the unified scan path.
    /// Order: NDEF read → ELEGOO raw → ACE raw → UID-only result.
    private func handleUnifiedRead(session: NFCTagReaderSession, tag: NFCTag) {
        WorkflowTraceStore.log(path: "nfc", step: "read.unified-start", details: [
            "uid": normalizedUID(from: tag) ?? "",
            "tagType": tagTypeName(tag)
        ])
        inspection = Self.initialInspection(of: tag)
        // Try NDEF first (works for NTAG/Ultralight based tags and ISO15693)
        tryNDEFRead(session: session, tag: tag)
    }

    /// The facts the tag hands over with no command sent: its family, UID and,
    /// on ISO 15693, the manufacturer code. Nil for a family CoreNFC added
    /// after this was written.
    private nonisolated static func initialInspection(of tag: NFCTag) -> TagInspection? {
        let family: TagInspection.Family
        let identifier: Data
        var icManufacturerCode: Int?
        switch tag {
        case .miFare(let t):
            switch t.mifareFamily {
            case .ultralight: family = .mifareUltralight
            case .desfire: family = .mifareDESFire
            case .plus: family = .mifarePlus
            default: family = .mifareOther
            }
            identifier = t.identifier
        case .iso15693(let t):
            family = .iso15693
            identifier = t.identifier
            icManufacturerCode = t.icManufacturerCode
        case .iso7816(let t):
            family = .iso7816
            identifier = t.identifier
        case .feliCa(let t):
            family = .feliCa
            identifier = t.currentIDm
        @unknown default:
            return nil
        }
        return TagInspection(
            capturedAt: Date(),
            family: family,
            uid: [UInt8](identifier),
            icManufacturerCode: icManufacturerCode
        )
    }

    /// Attempt to read NDEF payload from a tag.
    /// Falls back to raw reads if the tag is MIFARE and the message is absent or unrecognised;
    /// a link-only message on MIFARE tries the raw ELEGOO block first.
    private func tryNDEFRead(session: NFCTagReaderSession, tag: NFCTag) {
        guard let ndefTag = getNDEFTag(from: tag) else {
            WorkflowTraceStore.log(path: "nfc", step: "read.no-ndef-tag", details: [
                "uid": normalizedUID(from: tag) ?? "",
                "tagType": tagTypeName(tag)
            ])
            self.tryRawReadsOrFallback(session: session, tag: tag)
            return
        }

        ndefTag.queryNDEFStatus { status, capacity, _ in
            // Some tags can still return a readable NDEF payload even when status probing is
            // inconclusive, so we always attempt readNDEF before falling back to raw reads.
            let hintedNotSupported = (status == .notSupported)
            if let access = Self.inspectionAccess(for: status) {
                self.inspection?.ndef = .init(access: access, capacity: capacity)
            }

            ndefTag.readNDEF { message, error in
                if error != nil {
                    WorkflowTraceStore.log(path: "nfc", step: "read.ndef-error", details: [
                        "uid": self.normalizedUID(from: tag) ?? "",
                        "statusHint": String(describing: status),
                        "error": error?.localizedDescription ?? ""
                    ])
                    // NDEF read error — try raw reads before giving up
                    self.tryRawReadsOrFallback(session: session, tag: tag)
                    return
                }

                guard let message = message else {
                    WorkflowTraceStore.log(path: "nfc", step: "read.ndef-empty", details: [
                        "uid": self.normalizedUID(from: tag) ?? "",
                        "statusHint": String(describing: status)
                    ])
                    self.tryRawReadsOrFallback(session: session, tag: tag)
                    return
                }

                // Kept before any branch: a message nothing below recognises
                // still shows its records in Inspect Tag.
                self.inspection?.ndef?.messageLength = message.length
                self.inspection?.ndef?.records = message.records.map(NDEFRecordSnapshot.init(record:))

                let uid = self.normalizedUID(from: tag)
                // Every result below carries the message as read, for Clone Tag.
                let snapshot = TagSnapshot.capturing(message.records)

                // 0. A SpoolKid location tag is not filament data. It has to be
                //    recognized before the filament decode, or an unrecognised
                //    MIME record falls all the way through to the UID-only
                //    "unknown tag" path and the shelf reads as a mystery.
                for record in message.records {
                    let mimeType = self.getMimeType(from: record)
                    if let data = self.getPayloadData(from: record),
                       let location = LocationTagPayload.decode(payload: data, mimeType: mimeType) {
                        WorkflowTraceStore.log(path: "nfc", step: "read.location-tag", details: [
                            "uid": uid ?? "",
                            "location": location.name,
                            "locationId": location.uuid.uuidString
                        ])

                        let result = ScanResult(
                            cardUID: uid,
                            tagData: nil,
                            format: nil,
                            locationTag: location,
                            tagSnapshot: snapshot
                        )
                        if self.rejectsLocationTags {
                            // The result is still published: the caller needs
                            // the name and UID to offer "Unlink and Continue".
                            self.publish(result, session: session, tag: tag,
                                         errorMessage: "This tag labels \(location.name).")
                        } else {
                            self.publish(result, session: session, tag: tag, alertMessage: "Location tag read!")
                        }
                        return
                    }
                }

                // 1. Structured decode FIRST (OpenSpool / OpenPrintTag / OpenTag3D).
                //    On-tag data wins; the URL→web parse is only a fallback (step 2).
                for record in message.records {
                    let mimeType = self.getMimeType(from: record)
                    if let data = self.getPayloadData(from: record),
                       let read = TagFormatService.shared.decodeDetectingFormat(payload: data, mimeType: mimeType) {
                        var decoded = read.data
                        let detectedFormat = read.format
                        if detectedFormat == .openPrintTag {
                            if let url = Self.firstURL(in: message.records) {
                                decoded.tagURL = url.absoluteString
                            }
                            let hex = [UInt8](data).map { String(format: "%02x", $0) }.joined()
                            logger.info("OpenPrintTag decoded from tag (\(data.count) bytes). payloadHex=\(hex, privacy: .public)")
                        }
                        WorkflowTraceStore.log(path: "nfc", step: "read.ndef-payload-decoded", details: [
                            "uid": uid ?? "",
                            "mimeType": mimeType ?? "",
                            "detectedFormat": detectedFormat?.displayName ?? "",
                            "material": decoded.material,
                            "brand": decoded.brand,
                            "name": decoded.name ?? ""
                        ])

                        let result = ScanResult(
                            cardUID: uid,
                            tagData: decoded,
                            format: detectedFormat,
                            tagSnapshot: snapshot
                        )
                        self.publish(result, session: session, tag: tag, alertMessage: "Tag read successfully!")
                        return
                    }
                }

                // 2. No structured record decoded — the message may still carry a link.
                //    On an NTAG the raw ELEGOO read goes first. A real ELEGOO tag is a
                //    link to elegoo.com on the NDEF layer and its filament block at
                //    page 16, past the terminator; accepting the link first meant no
                //    scan ever reached the block. `decodeElegoo` needs the block's
                //    signature and a readable material, so an ordinary link tag still
                //    falls through to the link.
                if let url = Self.firstURL(in: message.records) {
                    // rawPagesRead: nil when no raw read was attempted, false when the READs did not complete, true when they completed and found no ELEGOO block.
                    let acceptURL = { (rawPagesRead: Bool?) in
                        WorkflowTraceStore.log(path: "nfc", step: "read.ndef-url-detected", details: [
                            "uid": uid ?? "",
                            "url": url.absoluteString,
                            "records": String(message.records.count),
                            "rawPagesRead": rawPagesRead.map { String($0) } ?? ""
                        ])
                        let result = ScanResult(
                            cardUID: uid,
                            tagData: nil,
                            format: .webUrl,
                            url: url,
                            // An interrupted ELEGOO read leaves a real spool's block
                            // unread; copying only its link would not be a clone.
                            tagSnapshot: rawPagesRead == false ? nil : snapshot
                        )
                        self.publish(result, session: session, tag: tag, alertMessage: "Web link found!")
                    }

                    // Only MIFARE-family tags take NTAG READ commands; anything else accepts the link.
                    guard case .miFare(let miFareTag) = tag else {
                        acceptURL(nil)
                        return
                    }

                    WorkflowTraceStore.log(path: "nfc", step: "read.ndef-url-elegoo-check", details: [
                        "uid": uid ?? ""
                    ])
                    self.tryElegooRead(session: session, tag: miFareTag) { elegooDecoded, pages in
                        // A decoded block has already emitted its result and
                        // closed the session.
                        if !elegooDecoded { acceptURL(pages != nil) }
                    }
                    return
                }

                // 3. NDEF present but neither structured nor URL — fall through to raw reads
                WorkflowTraceStore.log(path: "nfc", step: "read.ndef-unrecognized", details: [
                    "uid": uid ?? "",
                    "records": String(message.records.count),
                    "statusHint": String(describing: status),
                    "hintedNotSupported": String(hintedNotSupported)
                ])
                self.tryRawReadsOrFallback(session: session, tag: tag)
            }
        }
    }

    private func tryRawReadsOrFallback(session: NFCTagReaderSession, tag: NFCTag) {
        if case .miFare(let miFareTag) = tag {
            WorkflowTraceStore.log(path: "nfc", step: "read.raw-attempt", details: [
                "uid": normalizedUID(from: tag) ?? "",
                "tagType": tagTypeName(tag)
            ])
            self.tryRawReads(session: session, tag: miFareTag)
        } else if case .iso15693(let isoTag) = tag {
            // No decoder reads ISO 15693 raw, so its memory only decides
            // whether the tag is empty or in a format SpoolKid does not know.
            // A read that returned nothing proves neither, and stays "unknown".
            self.readAllBlocks(isoTag) { bytes in
                let isBlank = Type5Format.isBlank(memory: bytes)
                WorkflowTraceStore.log(path: "nfc", step: "read.iso15693-undecoded", details: [
                    "uid": self.normalizedUID(from: tag) ?? "",
                    "bytesRead": String(bytes.count),
                    "isBlank": String(isBlank)
                ])
                if !bytes.isEmpty {
                    // Four-byte blocks until Get System Info says otherwise
                    // (`attaching`).
                    self.inspection?.rawMemory = TagInspection.RawMemory(firstUnit: 0, unitSize: 4, bytes: bytes)
                }
                self.emitUIDOnlyResult(
                    session: session,
                    tag: tag,
                    alertMessage: isBlank ? "Empty tag. UID captured." : "Unknown tag format. UID captured.",
                    rawPageLogBytes: self.trimmedRawPageLogBytes(from: Data(bytes)),
                    isBlankTag: isBlank
                )
            }
        } else {
            WorkflowTraceStore.log(path: "nfc", step: "read.uid-only-non-mifare", details: [
                "uid": normalizedUID(from: tag) ?? "",
                "tagType": tagTypeName(tag)
            ])
            // For non-Mifare tags without known NDEF, emit UID
            self.emitUIDOnlyResult(
                session: session,
                tag: tag,
                alertMessage: "Unknown tag format. UID captured.",
                rawPageLogBytes: nil
            )
        }
    }

    /// Attempt raw page reads for ELEGOO and ACE formats.
    /// Falls back to UID-only result if all decodes fail.
    private func tryRawReads(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag
    ) {
        self.tryElegooRead(session: session, tag: tag) { [weak self] elegooReadSucceeded, elegooBufferData in
            guard let self = self else { return }

            let action = Self.rawReadFollowupAction(
                elegooReadSucceeded: elegooReadSucceeded,
                shouldTryACEFallback: Self.shouldTryACEFallback(afterElegooFailure: !elegooReadSucceeded)
            )

            switch action {
            case .stop:
                return
            case .tryAnycubicACE:
                let priorRawBytes = self.trimmedRawPageLogBytes(from: elegooBufferData)
                self.tryAnycubicACERead(
                    session: session,
                    tag: tag,
                    priorUnknownRawPageBytes: priorRawBytes
                )
            case .emitUIDOnly:
                let rawBytes = self.trimmedRawPageLogBytes(from: elegooBufferData)
                self.emitUIDOnlyResult(
                    session: session,
                    tag: .miFare(tag),
                    alertMessage: "Unknown tag format. UID captured.",
                    rawPageLogBytes: rawBytes
                )
            }
        }
    }

    private func tryAnycubicACERead(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        priorUnknownRawPageBytes: [UInt8]? = nil
    ) {
        let aceReadPages = AnycubicACEPayload.readPages
        guard let aceBuffer = NSMutableData(length: AnycubicACEPayload.totalBytes) else {
            emitUIDOnlyResult(session: session, tag: .miFare(tag), alertMessage: "Tag detected. UID captured.")
            return
        }

        readACEPagesSequentially(session: session, tag: tag, readPages: aceReadPages, index: 0, buffer: aceBuffer) { [weak self] error in
            guard let self = self else { return }

            if error != nil {
                self.tryTigerTagRead(session: session, tag: tag) { tigerHandled, tigerBuffer in
                    if tigerHandled { return }
                    self.emitUndecodedResult(
                        session: session,
                        tag: tag,
                        tigerBuffer: tigerBuffer,
                        fallbackRawBytes: priorUnknownRawPageBytes
                    )
                }
                return
            }

            let aceBytes = [UInt8](aceBuffer as Data)
            if let tagData = TagFormatService.shared.decodeAnycubicACE(pages: aceBytes) {
                let uid = self.normalizedUID(from: .miFare(tag))
                WorkflowTraceStore.log(path: "nfc", step: "read.raw-ace-decoded", details: [
                    "uid": uid ?? "",
                    "material": tagData.material,
                    "brand": tagData.brand,
                    "name": tagData.name ?? ""
                ])
                let aceSnapshot = TagSnapshot.capturingPages(
                    aceBytes,
                    firstPage: TagSnapshot.firstUserPage,
                    lastPage: AnycubicACEPayload.totalPages - 1
                )
                let result = ScanResult(
                    cardUID: uid,
                    tagData: tagData,
                    format: .anycubicACE,
                    tagSnapshot: aceSnapshot
                )
                self.inspection?.rawMemory = TagInspection.RawMemory(snapshot: aceSnapshot)
                self.publish(result, session: session, tag: .miFare(tag),
                             alertMessage: "Tag read successfully! (Anycubic ACE)")
                return
            }

            WorkflowTraceStore.log(path: "nfc", step: "read.raw-ace-failed", details: [
                "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
            ])
            let aceRawBytes = self.trimmedRawPageLogBytes(from: aceBuffer as Data)
            self.tryTigerTagRead(session: session, tag: tag) { tigerHandled, tigerBuffer in
                if tigerHandled { return }
                self.emitUndecodedResult(
                    session: session,
                    tag: tag,
                    tigerBuffer: tigerBuffer,
                    fallbackRawBytes: aceRawBytes ?? priorUnknownRawPageBytes
                )
            }
        }
    }

    /// Reads pages 4–39 and decodes TigerTag — the third raw read, tried
    /// after ELEGOO and ACE. Completion carries whether the chain must stop
    /// (decoded, or an Init tag reported) and the raw buffer for the next
    /// fallback — the same contract as `tryElegooRead`.
    private func tryTigerTagRead(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        completion: @escaping (Bool, Data?) -> Void
    ) {
        let tigerReadPages = TigerTagPayload.readPages
        let tigerTotalBytes = (TigerTagPayload.readPages.max()! + 4) * TigerTagPayload.bytesPerPage
        guard let tigerBuffer = NSMutableData(length: tigerTotalBytes) else {
            completion(false, nil)
            return
        }

        readACEPagesSequentially(session: session, tag: tag, readPages: tigerReadPages, index: 0, buffer: tigerBuffer) { [weak self] error in
            guard let self = self else { return }

            if error != nil {
                completion(false, nil)
                return
            }

            let bufferData = tigerBuffer as Data
            let tigerBytes = [UInt8](bufferData[TigerTagPayload.firstUserPageOffset...])
            let uid = self.normalizedUID(from: .miFare(tag))
            // Built from `tigerBytes`, which start at page 4, never from the
            // decoded result's snapshot.
            let tigerMemory = TagInspection.RawMemory(
                firstUnit: TagSnapshot.firstUserPage, unitSize: TagSnapshot.bytesPerPage, bytes: tigerBytes
            )

            // A blank Init chip is not filament data, but it is also not
            // garbage — the user is holding a tag waiting to be written.
            if TigerTagPayload.variant(of: tigerBytes) == .initTag {
                WorkflowTraceStore.log(path: "nfc", step: "read.tigertag-init", details: ["uid": uid ?? ""])
                self.inspection?.rawMemory = tigerMemory
                self.emitUIDOnlyResult(
                    session: session,
                    tag: .miFare(tag),
                    alertMessage: "TigerTag Init (blank tag). UID captured.",
                    rawPageLogBytes: nil
                )
                completion(true, nil)
                return
            }

            if let tagData = TagFormatService.shared.decodeTigerTag(dataFromPage4: tigerBytes) {
                WorkflowTraceStore.log(path: "nfc", step: "read.tigertag-decoded", details: [
                    "uid": uid ?? "",
                    "material": tagData.material,
                    "brand": tagData.brand,
                    "name": tagData.name ?? ""
                ])
                let result = ScanResult(
                    cardUID: uid,
                    tagData: tagData,
                    format: .tigerTag,
                    tagSnapshot: TagSnapshot.capturingPages(
                        tigerBytes,
                        firstPage: TagSnapshot.firstUserPage,
                        lastPage: TagSnapshot.firstUserPage
                                  + TigerTagPayload.totalByteCount / TigerTagPayload.bytesPerPage - 1
                    ),
                    tigerTagInfo: TigerTagInfo(
                        variant: TigerTagPayload.variant(of: tigerBytes) ?? .tigerTag,
                        signature: TigerTagSignature.verify(uid: tag.identifier, dataBytes: tigerBytes)
                    )
                )
                self.inspection?.rawMemory = tigerMemory
                self.publish(result, session: session, tag: .miFare(tag),
                             alertMessage: "Tag read successfully! (TigerTag)")
                completion(true, nil)
                return
            }

            WorkflowTraceStore.log(path: "nfc", step: "read.tigertag-failed", details: ["uid": uid ?? ""])
            completion(false, bufferData)
        }
    }

    private func tryElegooRead(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        completion: @escaping (Bool, Data?) -> Void
    ) {
        let elegooReadPages = ElegooPayload.readPages
        // Elegoo needs pages up to 35. Each read returns 4 pages (16 bytes).
        // readPages [4,8,12,16,20,24,28,32] covers pages 4-35.
        let elegooTotalBytes = (ElegooPayload.readPages.max()! + 4) * ElegooPayload.bytesPerPage
        guard let elegooBuffer = NSMutableData(length: elegooTotalBytes) else {
            completion(false, nil)
            return
        }

        readACEPagesSequentially(session: session, tag: tag, readPages: elegooReadPages, index: 0, buffer: elegooBuffer) { [weak self] error in
            guard let self = self else { return }

            if error != nil {
                completion(false, nil)
                return
            }

            let elegooBytes = [UInt8](elegooBuffer as Data)
            if let tagData = TagFormatService.shared.decodeElegoo(pages: elegooBytes) {
                let uid = self.normalizedUID(from: .miFare(tag))
                WorkflowTraceStore.log(path: "nfc", step: "read.raw-elegoo-decoded", details: [
                    "uid": uid ?? "",
                    "material": tagData.material,
                    "brand": tagData.brand,
                    "name": tagData.name ?? ""
                ])
                let elegooSnapshot = TagSnapshot.capturingPages(
                    elegooBytes,
                    firstPage: TagSnapshot.firstUserPage,
                    lastPage: elegooTotalBytes / ElegooPayload.bytesPerPage - 1
                )
                let result = ScanResult(
                    cardUID: uid,
                    tagData: tagData,
                    format: .elegoo,
                    tagSnapshot: elegooSnapshot
                )
                self.inspection?.rawMemory = TagInspection.RawMemory(snapshot: elegooSnapshot)
                self.publish(result, session: session, tag: .miFare(tag),
                             alertMessage: "Tag read successfully! (ELEGOO)")
                completion(true, nil)
                return
            }

            WorkflowTraceStore.log(path: "nfc", step: "read.raw-elegoo-failed", details: [
                "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
            ])
            completion(false, elegooBuffer as Data)
        }
    }

    /// The end of the raw chain: no decoder recognised the tag. The TigerTag
    /// read is the last and widest (pages 4-39), so its buffer decides whether
    /// the tag is empty or in a format SpoolKid does not know. A failed read
    /// proves neither, and stays "unknown".
    private func emitUndecodedResult(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        tigerBuffer: Data?,
        fallbackRawBytes: [UInt8]?
    ) {
        let isBlank = tigerBuffer.map {
            TagDumpDecode.isBlank(in: [UInt8]($0), from: TigerTagPayload.firstUserPageOffset)
        } ?? false
        if let tigerBuffer {
            inspection?.rawMemory = TagInspection.RawMemory(snapshot: TagSnapshot.capturingPages(
                [UInt8](tigerBuffer),
                firstPage: TagSnapshot.firstUserPage,
                lastPage: TigerTagPayload.readPages.max()! + 3
            ))
        }
        emitUIDOnlyResult(
            session: session,
            tag: .miFare(tag),
            alertMessage: isBlank ? "Empty tag. UID captured." : "Unknown tag format. UID captured.",
            rawPageLogBytes: tigerBuffer.flatMap { trimmedRawPageLogBytes(from: $0) } ?? fallbackRawBytes,
            isBlankTag: isBlank
        )
    }

    /// Emit a generic UID-only result for any tag whose UID could be read.
    private func emitUIDOnlyResult(
        session: NFCTagReaderSession,
        tag: NFCTag,
        alertMessage: String,
        rawPageLogBytes: [UInt8]? = nil,
        isBlankTag: Bool = false
    ) {
        let uid = normalizedUID(from: tag)
        let result = ScanResult(
            cardUID: uid,
            tagData: nil,
            format: nil,
            rawPageLogBytes: rawPageLogBytes,
            isBlankTag: isBlankTag
        )
        WorkflowTraceStore.log(path: "nfc", step: "read.uid-only-result", details: [
            "uid": uid ?? "",
            "rawPageLogBytes": String(rawPageLogBytes?.count ?? 0),
            "alertMessage": alertMessage
        ])
        publish(result, session: session, tag: tag, alertMessage: alertMessage)
    }

    /// Where every unified-read result leaves: asks the chip about itself when
    /// the scan opted in, attaches the inspection, closes the session and
    /// publishes. The chip is asked last, after every read: a refused
    /// GET_VERSION can drop an original Ultralight out of the selected state.
    /// Pass `errorMessage` to close the session as a failure instead.
    private func publish(
        _ result: ScanResult,
        session: NFCTagReaderSession,
        tag: NFCTag,
        alertMessage: String? = nil,
        errorMessage: String? = nil
    ) {
        let finish = { (chip: TagInspection.Chip?) in
            let published = Self.attaching(self.inspection, chip: chip, to: result)
            self.inspection = nil
            if let errorMessage {
                session.invalidate(errorMessage: errorMessage)
            } else {
                if let alertMessage { session.alertMessage = alertMessage }
                session.invalidate()
            }
            DispatchQueue.main.async { self.scanResult = published; self.isScanning = false }
        }
        if queriesChipDetails {
            queryChipDetails(tag, completion: finish)
        } else {
            finish(nil)
        }
    }

    /// One extra question for the chip: GET_VERSION on Ultralight/NTAG, Get
    /// System Info on ISO 15693, nothing on any other family. Best effort —
    /// any failure hands back nil and the result goes out as it would have.
    /// No deadline of its own, like every other command in the read chain:
    /// CoreNFC answers a tag that left the field with an error.
    private func queryChipDetails(_ tag: NFCTag, completion: @escaping (TagInspection.Chip?) -> Void) {
        let uid = normalizedUID(from: tag) ?? ""
        let answer = { (chip: TagInspection.Chip?) in
            WorkflowTraceStore.log(path: "nfc", step: "read.chip-query", details: [
                "uid": uid,
                "answered": String(chip != nil)
            ])
            completion(chip)
        }
        switch tag {
        case .miFare(let miFareTag) where miFareTag.mifareFamily == .ultralight:
            miFareTag.sendMiFareCommand(commandPacket: Data([0x60])) { data, error in
                guard error == nil, data.count >= 8 else {
                    answer(nil)
                    return
                }
                answer(TagInspection.Chip(getVersion: [UInt8](data)))
            }
        case .iso15693(let isoTag):
            isoTag.getSystemInfo(requestFlags: [.highDataRate]) { result in
                guard case .success(let info) = result else {
                    answer(nil)
                    return
                }
                answer(TagInspection.Chip(
                    icReference: info.icReference >= 0 ? info.icReference : nil,
                    blockSize: info.blockSize > 0 ? info.blockSize : nil,
                    totalBlocks: info.totalBlocks > 0 ? info.totalBlocks : nil
                ))
            }
        default:
            answer(nil)
        }
    }

    /// `result` with the scan's inspection attached and nothing else changed.
    /// A chip query that failed passes nil, so the hub gets exactly what it
    /// got before. An ISO 15693 tag's block size replaces the four bytes its
    /// raw memory was read with.
    nonisolated static func attaching(
        _ inspection: TagInspection?,
        chip: TagInspection.Chip?,
        to result: ScanResult
    ) -> ScanResult {
        guard var inspection else { return result }
        inspection.chip = chip
        if inspection.family == .iso15693, let blockSize = chip?.blockSize, blockSize > 0 {
            inspection.rawMemory?.unitSize = blockSize
        }
        var published = result
        published.inspection = inspection
        return published
    }

    /// What `queryNDEFStatus` said, for Inspect Tag. Nil for a status CoreNFC
    /// added after this was written.
    private nonisolated static func inspectionAccess(for status: NFCNDEFStatus) -> TagInspection.NDEFAccess? {
        switch status {
        case .readWrite: .readWrite
        case .readOnly: .readOnly
        case .notSupported: .notSupported
        @unknown default: nil
        }
    }

    private func tagTypeName(_ tag: NFCTag) -> String {
        switch tag {
        case .miFare:
            return "miFare"
        case .iso15693:
            return "iso15693"
        case .iso7816:
            return "iso7816"
        case .feliCa:
            return "feliCa"
        @unknown default:
            return "unknown"
        }
    }

    func trimmedRawPageLogBytes(from data: Data?) -> [UInt8]? {
        guard let data, !data.isEmpty else { return nil }
        let bytes = [UInt8](data)
        let lastNonZeroIndex = bytes.lastIndex(where: { $0 != 0 })
        guard let lastNonZeroIndex else { return nil }
        return Array(bytes[...lastNonZeroIndex])
    }

    // MARK: - NDEF Write (OpenSpool, OpenPrintTag, OpenTag3D)

    /// Build the NDEF records for a write: optional well-known URI record first, then the MIME record.
    nonisolated static func ndefRecords(mimePayload: Data, mimeType: String, urlString: String?) -> [NFCNDEFPayload] {
        var records: [NFCNDEFPayload] = []
        if let urlString,
           case let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
           let url = URL(string: trimmed),
           let uri = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) {
            records.append(uri)
        }
        records.append(NFCNDEFPayload(format: .media, type: Data(mimeType.utf8), identifier: Data(), payload: mimePayload))
        return records
    }

    /// First well-known URI value among the records, if any. Decoded by
    /// `NDEFURIRecord`, not CoreNFC's `wellKnownTypeURIPayload()`, which aborts
    /// the app on a URI record that is not UTF-8.
    static func firstURL(in records: [NFCNDEFPayload]) -> URL? {
        for record in records where record.typeNameFormat == .nfcWellKnown && record.type == Data("U".utf8) {
            if let url = NDEFURIRecord.url(from: record.payload) { return url }
        }
        return nil
    }

    /// Writes a filament payload over the tag-reader session.
    ///
    /// Runs on `NFCTagReaderSession` rather than `NFCNDEFReaderSession` for one
    /// reason: only the tag session exposes the tag's hardware UID. An NDEF
    /// session cannot report it at all, so before 2026-08-31 a tag written from
    /// an existing spool could never be linked back to that spool — the app had
    /// just written the tag and still did not know which tag it was.
    private func handleNDEFWrite(session: NFCTagReaderSession, tag: NFCTag) {
        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }

        guard let ndefTag = getNDEFTag(from: tag) else {
            session.invalidate(errorMessage: "Tag type is not supported for writing.")
            return
        }

        // The UID this write is FOR (a rewrite of a known tag) is not the same
        // as the UID it LANDED on. Prefer what the hardware just reported.
        let uid = normalizedUID(from: tag) ?? writeCardUID

        let format = writeFormatToUse ?? TagFormatService.shared.currentFormat

        guard let payloadData = TagFormatService.shared.encode(data: dataToWrite, format: format) else {
            session.invalidate(errorMessage: "Failed to encode data for \(format.displayName).")
            return
        }

        // Create NDEF Payload with the correct MIME type for the format
        guard let mimeType = format.mimeType else {
            session.invalidate(errorMessage: "\(format.displayName) does not use NDEF.")
            return
        }

        let urlString = (format == .openPrintTag) ? dataToWrite.tagURL : nil
        // Unpadded. An OpenPrintTag write replaces it below, once the tag has
        // reported the capacity its layout fills.
        let unpaddedMessage = NFCNDEFMessage(records: Self.ndefRecords(
            mimePayload: payloadData, mimeType: mimeType, urlString: urlString))

        queryNDEFStatusPreparingBlankTag(tag, ndefTag: ndefTag) { status, capacity, error, prepared in
            if let error {
                WorkflowTraceStore.log(path: "nfc", step: "session.ndef-query-status-failed", details: [
                    "error": error.localizedDescription
                ])
                session.invalidate(errorMessage: "Fail to query status: \(error.localizedDescription)")
                return
            }

            guard status == .readWrite else {
                session.invalidate(errorMessage: Self.ndefStatusRefusal(status, preparedBlankTag: prepared))
                return
            }

            // OpenPrintTag is laid out as Prusa's initializer does, filling the
            // tag; an unknown capacity (<= 0) keeps the unpadded record.
            let message: NFCNDEFMessage
            let countdownDropped: Bool
            if format == .openPrintTag, capacity > 0 {
                var isSLIX2 = false
                if case .iso15693(let isoTag) = tag {
                    isSLIX2 = TagDumpWalk.isSLIX2(uid: [UInt8](isoTag.identifier))
                }
                guard let laidOut = OpenPrintTagLayout.layout(
                    for: dataToWrite, urlString: urlString, capacity: capacity, isSLIX2: isSLIX2
                ) else {
                    let room = OpenPrintTagLayout.messageCeiling(capacity: capacity, isSLIX2: isSLIX2)
                    session.invalidate(errorMessage: "Tag is too small. Needs \(unpaddedMessage.length) bytes but tag only has \(room) bytes available.")
                    return
                }
                WorkflowTraceStore.log(path: "nfc", step: "write.opt-layout", details: [
                    "capacity": String(capacity),
                    "messageLength": String(laidOut.messageLength),
                    "aux": laidOut.auxOffset == nil ? "no" : "yes",
                    "length": laidOut.writesLength ? "yes" : "no"
                ])
                message = NFCNDEFMessage(records: Self.ndefRecords(
                    mimePayload: laidOut.payload, mimeType: mimeType, urlString: urlString))
                countdownDropped = Self.countdownDidNotFit(data: dataToWrite, auxWritten: laidOut.auxOffset != nil)
            } else {
                message = unpaddedMessage
                if format == .openPrintTag {
                    WorkflowTraceStore.log(path: "nfc", step: "write.opt-unpadded", details: [
                        "capacity": String(capacity),
                        "messageLength": String(unpaddedMessage.length)
                    ])
                }
                // The unpadded record has no aux region.
                countdownDropped = format == .openPrintTag
                    && Self.countdownDidNotFit(data: dataToWrite, auxWritten: false)
            }

            // Check tag capacity before writing
            let messageLength = message.length
            if capacity > 0 && messageLength > capacity {
                session.invalidate(errorMessage: "Tag is too small. Needs \(messageLength) bytes but tag only has \(capacity) bytes available.")
                return
            }

            ndefTag.writeNDEF(message) { (error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                } else {
                    self.finishFilamentWrite(
                        session: session, uid: uid, data: dataToWrite, format: format,
                        note: countdownDropped ? " — no room on this tag for the printer countdown." : "")
                }
            }
        }
    }

    /// `queryNDEFStatus`, after first formatting a factory-blank ISO 15693 tag.
    ///
    /// iOS writes NDEF only to a tag that already has a capability container,
    /// and an ICODE SLIX typically ships with every block zero — so without
    /// this a blank NFC-V tag answers notSupported and can never be written
    /// (owner's ICODE SLIX, 2026-10-02). Only a tag whose block 0 is all zero
    /// is formatted; `prepared` is true when the format landed this tap.
    /// Whether CoreNFC sees the new container within the same session is
    /// unverified on hardware: if it does not, the re-query still answers
    /// notSupported and `ndefStatusRefusal` asks for a second tap.
    private func queryNDEFStatusPreparingBlankTag(
        _ tag: NFCTag,
        ndefTag: NFCNDEFTag,
        completion: @escaping (_ status: NFCNDEFStatus, _ capacity: Int, _ error: Error?, _ prepared: Bool) -> Void
    ) {
        ndefTag.queryNDEFStatus { status, capacity, error in
            guard error == nil, status == .notSupported, case .iso15693(let isoTag) = tag else {
                completion(status, capacity, error, false)
                return
            }
            self.formatBlankType5Tag(isoTag) { formatted in
                guard formatted else {
                    completion(status, capacity, nil, false)
                    return
                }
                ndefTag.queryNDEFStatus { status, capacity, error in
                    completion(status, capacity, error, true)
                }
            }
        }
    }

    /// Writes `Type5Format`'s container to a tag whose block 0 is all zero.
    ///
    /// Block 0 is read with Read Multiple Blocks first: an answer is the
    /// evidence the container's MBREAD flag needs. A tag that refuses it is
    /// read with Read Single Block and formatted without the flag.
    private func formatBlankType5Tag(_ tag: NFCISO15693Tag, completion: @escaping (Bool) -> Void) {
        let uid = normalizedUID(from: .iso15693(tag)) ?? ""
        let formatWithFirstBlock: (Data, Bool) -> Void = { firstBlock, multipleBlockRead in
            guard Type5Format.isUnformatted(firstBlock: firstBlock) else {
                WorkflowTraceStore.log(path: "nfc", step: "write.type5-not-blank", details: ["uid": uid])
                completion(false)
                return
            }
            tag.getSystemInfo(requestFlags: [.highDataRate]) { result in
                guard case .success(let info) = result,
                      let writes = Type5Format.formatWrites(
                          blockSize: info.blockSize, blockCount: info.totalBlocks,
                          multipleBlockRead: multipleBlockRead,
                          uid: [UInt8](tag.identifier)
                      ) else {
                    WorkflowTraceStore.log(path: "nfc", step: "write.type5-no-size", details: ["uid": uid])
                    completion(false)
                    return
                }
                self.writeType5Blocks(tag, writes: writes[...]) { error in
                    if let error {
                        logger.error("Type 5 format failed: \(error.localizedDescription, privacy: .public)")
                    }
                    WorkflowTraceStore.log(path: "nfc", step: "write.type5-format", details: [
                        "uid": uid,
                        "blockSize": String(info.blockSize),
                        "blockCount": String(info.totalBlocks),
                        "ok": String(error == nil)
                    ])
                    completion(error == nil)
                }
            }
        }

        tag.readMultipleBlocks(requestFlags: [.highDataRate], blockRange: NSRange(location: 0, length: 1)) { result in
            if case .success(let blocks) = result, let first = blocks.first {
                formatWithFirstBlock(first, true)
                return
            }
            tag.readSingleBlock(requestFlags: [.highDataRate], blockNumber: 0) { result in
                guard case .success(let first) = result else {
                    completion(false)
                    return
                }
                formatWithFirstBlock(first, false)
            }
        }
    }

    private func writeType5Blocks(
        _ tag: NFCISO15693Tag,
        writes: ArraySlice<(block: Int, data: Data)>,
        completion: @escaping (Error?) -> Void
    ) {
        guard let next = writes.first else {
            completion(nil)
            return
        }
        tag.writeSingleBlock(requestFlags: [.highDataRate], blockNumber: UInt8(next.block), dataBlock: next.data) { error in
            if let error {
                completion(error)
                return
            }
            self.writeType5Blocks(tag, writes: writes.dropFirst(), completion: completion)
        }
    }

    /// The one way a filament write finishes, whatever the format.
    ///
    /// The UID is published in the same main-queue hop as the success flag,
    /// because `WriteTagView` links the tag to its spool the moment the flag
    /// flips and reads the UID to do it. The ACE path used to publish only the
    /// flag, so an ACE tag was never linked to the spool it was written for —
    /// found on real hardware (issue #5), after this file's docs had said for
    /// two weeks that every write published both.
    private func finishFilamentWrite(
        session: NFCTagReaderSession,
        uid: String?,
        data: FilamentTagData,
        format: TagFormat,
        note: String = ""
    ) {
        DispatchQueue.main.async {
            self.lastWrittenTagUID = uid
            self.lastWriteSucceeded = true
        }
        recordLedgerAfterWrite(uid: uid, data: data)
        session.alertMessage = "Tag written successfully! (\(format.displayName))" + note
        session.invalidate()
    }

    // MARK: - ACE Write (raw page writes)

    private func handleACEWrite(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }

        // Highest page first (`rawWriteOrder`): GET_VERSION does not size every
        // chip, and one that keeps its configuration at pages 16-19 must refuse
        // page 31 before pages 16 and 17 land in CFG0 and CFG1.
        let pages = Self.rawWriteOrder(AnycubicACEPayload.encodePages(from: dataToWrite))
        guard !pages.isEmpty else {
            session.invalidate(errorMessage: "Failed to encode data for Anycubic ACE.")
            return
        }

        // Validate all page numbers fit in NTAG range (max 255)
        if let maxPage = pages.max(by: { $0.page < $1.page }), maxPage.page > 255 {
            session.invalidate(errorMessage: Self.pageLimitMessage(maxPage.page))
            return
        }

        readHeaderAllowsWrite(tag: tag) { allowed in
            guard allowed else {
                WorkflowTraceStore.log(path: "nfc", step: "write.ace-locked", details: [
                    "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
                ])
                session.invalidate(errorMessage: Self.rawWriteRefusalMessage(.locked, formatName: "Anycubic ACE"))
                return
            }

            // A factory Anycubic tag is password-protected against writes. Ask the
            // tag before writing a page, so it is refused with a reason rather than
            // failing at the first page — or, worse, not failing at all.
            let lastPage = pages.map(\.page).max() ?? 0
            self.checkWritePassword(tag: tag, throughPage: lastPage) { needsPassword, _ in
                guard !needsPassword else {
                    WorkflowTraceStore.log(path: "nfc", step: "write.ace-password-protected", details: [
                        "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
                    ])
                    session.invalidate(errorMessage: Self.aceWritePasswordMessage)
                    return
                }
                self.writeACEPages(session: session, tag: tag, pages: pages, data: dataToWrite)
            }
        }
    }

    /// READs pages 0-3 and answers whether a raw page write may go ahead
    /// (`rawWriteHeaderAllowsWrite`). Only a clear refusal is `false`: a failed
    /// or short READ lets the write proceed, protected by its highest page going
    /// first.
    private func readHeaderAllowsWrite(tag: NFCMiFareTag, completion: @escaping (_ allowed: Bool) -> Void) {
        tag.sendMiFareCommand(commandPacket: Data([0x30, 0x00])) { header, error in
            completion(error != nil || Self.rawWriteHeaderAllowsWrite(header) != false)
        }
    }

    /// Reads the tag's configuration pages and answers whether a write through
    /// `lastPage` needs a password, handing back the chip's page count as well:
    /// a raw clone needs both, and asking GET_VERSION twice is how two answers
    /// could disagree. Anything short of a clear answer — a chip that does not
    /// report its size, a refused read — is `false`: the write goes ahead,
    /// protected by writing its highest page first (`rawWriteOrder`).
    private func checkWritePassword(
        tag: NFCMiFareTag,
        throughPage lastPage: Int,
        completion: @escaping (_ needsPassword: Bool, _ pageCount: Int?) -> Void
    ) {
        readVersion(tag: tag) { _, pageCount in
            guard let pageCount else {
                completion(false, nil)
                return
            }
            let configPage = Self.configPage(forPageCount: pageCount)
            tag.sendMiFareCommand(commandPacket: Data([0x30, UInt8(configPage)])) { data, error in
                guard error == nil,
                      let needsPassword = Self.writeNeedsPassword(configRead: data, throughPage: lastPage) else {
                    completion(false, pageCount)
                    return
                }
                completion(needsPassword, pageCount)
            }
        }
    }

    private func writeACEPages(session: NFCTagReaderSession, tag: NFCMiFareTag, pages: [(page: Int, data: Data)], data: FilamentTagData) {
        writePages(tag: tag, pages: pages) { failure, pagesWritten, _ in
            if let failure {
                WorkflowTraceStore.log(path: "nfc", step: "write.ace-stopped", details: [
                    "uid": self.normalizedUID(from: .miFare(tag)) ?? "", "cause": failure,
                    "pagesWritten": String(pagesWritten), "pages": String(pages.count)
                ])
                session.invalidate(errorMessage: Self.rawWriteFailureMessage(
                    pagesWritten: pagesWritten, totalPages: pages.count, cause: failure
                ))
                return
            }
            let uid = self.normalizedUID(from: .miFare(tag)) ?? self.writeCardUID
            self.finishFilamentWrite(session: session, uid: uid, data: data, format: .anycubicACE)
        }
    }

    // MARK: - Raw Filament Write (TigerTag, ELEGOO)

    /// Writes a raw-page filament format. Every refusal — a chip too small,
    /// locked or password-protected — happens before a byte lands, and pages
    /// go highest first (`rawWriteOrder`). The ACE keeps its own path, whose
    /// ascending order is a filed owner decision (2026-09-15).
    private func handleRawFilamentWrite(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        format: TagFormat,
        minChipPageCount: Int
    ) {
        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }

        let pages = Self.rawWriteOrder(Self.rawFilamentWritePages(for: dataToWrite, format: format) ?? [])
        guard let lastPage = pages.map(\.page).max() else {
            session.invalidate(errorMessage: Self.rawWriteRefusalMessage(.encodeFailed, formatName: format.displayName))
            return
        }
        if lastPage > 255 {
            session.invalidate(errorMessage: Self.pageLimitMessage(lastPage))
            return
        }

        readVersion(tag: tag) { [weak self] _, pageCount in
            guard let self = self else { return }
            // Known chip smaller than the format needs: refuse before a byte
            // lands. Unknown chips proceed — highest page first makes a
            // too-small tag refuse the top page before low pages land in its
            // configuration (the ACE lesson, 2026-09-15).
            if let pageCount, pageCount < minChipPageCount {
                WorkflowTraceStore.log(path: "nfc", step: "write.\(format.rawValue)-too-small", details: [
                    "uid": self.normalizedUID(from: .miFare(tag)) ?? "",
                    "pages": String(pageCount)
                ])
                session.invalidate(errorMessage: Self.rawWriteRefusalMessage(.tooSmall, formatName: format.displayName))
                return
            }

            self.readHeaderAllowsWrite(tag: tag) { allowed in
                guard allowed else {
                    WorkflowTraceStore.log(path: "nfc", step: "write.\(format.rawValue)-locked", details: [
                        "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
                    ])
                    session.invalidate(errorMessage: Self.rawWriteRefusalMessage(.locked, formatName: format.displayName))
                    return
                }
                self.checkWritePassword(tag: tag, throughPage: lastPage) { needsPassword, _ in
                    guard !needsPassword else {
                        WorkflowTraceStore.log(path: "nfc", step: "write.\(format.rawValue)-password-protected", details: [
                            "uid": self.normalizedUID(from: .miFare(tag)) ?? ""
                        ])
                        session.invalidate(errorMessage: Self.rawWriteRefusalMessage(.passwordProtected, formatName: format.displayName))
                        return
                    }
                    self.writePages(tag: tag, pages: pages) { failure, pagesWritten, _ in
                        if let failure {
                            WorkflowTraceStore.log(path: "nfc", step: "write.\(format.rawValue)-stopped", details: [
                                "uid": self.normalizedUID(from: .miFare(tag)) ?? "",
                                "cause": failure,
                                "pagesWritten": String(pagesWritten), "pages": String(pages.count)
                            ])
                            session.invalidate(errorMessage: Self.rawWriteFailureMessage(
                                pagesWritten: pagesWritten, totalPages: pages.count, cause: failure
                            ))
                            return
                        }
                        let uid = self.normalizedUID(from: .miFare(tag)) ?? self.writeCardUID
                        self.finishFilamentWrite(
                            session: session, uid: uid, data: dataToWrite, format: format,
                            note: Self.writtenNote(for: dataToWrite, format: format)
                        )
                    }
                }
            }
        }
    }

    /// Writes pages in the order given with WRITE (0xA2), stopping at the first
    /// page the tag refuses. `completion` gets nil once every page is
    /// acknowledged, or the message to show, with how many pages the tag
    /// accepted before stopping, and whether it refused rather than was lost. Shared by the ACE write and a raw clone so the
    /// ACK rule lives in one place.
    private func writePages(
        tag: NFCMiFareTag,
        pages: [(page: Int, data: Data)],
        index: Int = 0,
        completion: @escaping (_ failure: String?, _ pagesWritten: Int, _ refused: Bool) -> Void
    ) {
        guard index < pages.count else {
            completion(nil, pages.count, false)
            return
        }

        let page = pages[index]

        // NTAG WRITE command: 0xA2, page number, 4 bytes of data
        var writeCommand = Data([0xA2, UInt8(page.page)])
        writeCommand.append(page.data)

        tag.sendMiFareCommand(commandPacket: writeCommand) { pageData, error in
            if let error = error {
                completion("Write failed at page \(page.page): \(error.localizedDescription)", index, false)
                return
            }
            guard Self.isAcknowledgedWriteResponse(pageData) else {
                completion("The tag refused page \(page.page), so it was not fully written.", index, true)
                return
            }
            self.writePages(tag: tag, pages: pages, index: index + 1, completion: completion)
        }
    }

    // MARK: - Clone Write

    /// Writes a `TagSnapshot` verbatim. Every refusal happens before a byte is
    /// written; the snapshot's kind decides which write path runs.
    private func handleCloneWrite(session: NFCTagReaderSession, tag: NFCTag) {
        guard case .clone(let snapshot, let sourceUID, let blockedUIDs, let allowedUID) = pendingWrite else {
            failClone(session: session, reason: "Nothing to copy.")
            return
        }

        let uid = normalizedUID(from: tag)

        switch Self.cloneWriteDecision(
            targetUID: uid, sourceUID: sourceUID, blockedUIDs: blockedUIDs, allowedUID: allowedUID
        ) {
        case .sameTag:
            WorkflowTraceStore.log(path: "nfc", step: "clone.same-tag", details: ["uid": uid ?? ""])
            finishClone(session: session, result: .sameTag,
                        errorMessage: "That's the tag you scanned. Tap Clone Tag again and hold a blank tag.")
        case .blocked(let blockedUID):
            WorkflowTraceStore.log(path: "nfc", step: "clone.blocked", details: ["uid": blockedUID])
            finishClone(session: session, result: .blocked(uid: blockedUID),
                        errorMessage: "This tag belongs to something else.")
        case .proceed:
            switch snapshot {
            case .ndef:
                cloneNDEF(session: session, tag: tag, snapshot: snapshot, uid: uid)
            case .rawPages:
                // Raw pages are NTAG pages; nothing else takes a WRITE (0xA2).
                guard case .miFare(let miFareTag) = tag else {
                    failClone(session: session, reason: "This copy needs an NTAG213 or larger tag.")
                    return
                }
                cloneRawPages(session: session, tag: miFareTag, snapshot: snapshot, uid: uid)
            }
        }
    }

    private func cloneNDEF(session: NFCTagReaderSession, tag: NFCTag, snapshot: TagSnapshot, uid: String?) {
        guard let ndefTag = getNDEFTag(from: tag) else {
            failClone(session: session, reason: "This tag cannot hold an NDEF message.")
            return
        }
        guard let records = snapshot.records(), !records.isEmpty else {
            failClone(session: session, reason: "There is nothing on the scanned tag to copy.")
            return
        }
        let message = NFCNDEFMessage(records: records)

        queryNDEFStatusPreparingBlankTag(tag, ndefTag: ndefTag) { status, capacity, error, prepared in
            if let error {
                self.failClone(session: session, reason: "Could not check the tag: \(error.localizedDescription)")
                return
            }
            guard status == .readWrite else {
                self.failClone(session: session, reason: Self.ndefStatusRefusal(status, preparedBlankTag: prepared))
                return
            }
            if capacity > 0 && message.length > capacity {
                WorkflowTraceStore.log(path: "nfc", step: "clone.too-small", details: [
                    "uid": uid ?? "", "needed": String(message.length), "capacity": String(capacity)
                ])
                self.failClone(session: session, reason: "Tag is too small. Needs \(message.length) bytes but tag only has \(capacity) bytes available.")
                return
            }

            ndefTag.writeNDEF(message) { error in
                if let error {
                    self.failClone(session: session, reason: "Write failed: \(error.localizedDescription)")
                    return
                }
                self.succeedClone(session: session, uid: uid)
            }
        }
    }

    private func cloneRawPages(session: NFCTagReaderSession, tag: NFCMiFareTag, snapshot: TagSnapshot, uid: String?) {
        // Pages 0-3 hold the UID, lock bits and capability container, some of it
        // one-time programmable. A copy never writes them, whatever built it.
        guard case .rawPages(let firstPage, _) = snapshot, firstPage >= TagSnapshot.firstUserPage else {
            failClone(session: session, reason: "There is nothing on the scanned tag to copy.")
            return
        }
        let pages = Self.rawWriteOrder(snapshot.pageWrites)
        guard let lastPage = pages.first?.page, lastPage <= 255 else {
            failClone(session: session, reason: "There is nothing on the scanned tag to copy.")
            return
        }

        readHeaderAllowsWrite(tag: tag) { allowed in
            guard allowed else {
                WorkflowTraceStore.log(path: "nfc", step: "clone.locked", details: ["uid": uid ?? ""])
                self.failClone(session: session, reason: Self.cloneLockedMessage)
                return
            }

            self.checkWritePassword(tag: tag, throughPage: lastPage) { needsPassword, pageCount in
                guard Self.rawCloneFits(lastPage: lastPage, pageCount: pageCount) else {
                    WorkflowTraceStore.log(path: "nfc", step: "clone.too-small", details: [
                        "uid": uid ?? "", "lastPage": String(lastPage), "pageCount": pageCount.map(String.init) ?? ""
                    ])
                    self.failClone(session: session, reason: Self.cloneTooSmallMessage)
                    return
                }
                guard !needsPassword else {
                    WorkflowTraceStore.log(path: "nfc", step: "clone.password-protected", details: ["uid": uid ?? ""])
                    self.failClone(session: session, reason: Self.clonePasswordMessage)
                    return
                }
                self.writePages(tag: tag, pages: pages) { failure, pagesWritten, refused in
                    guard let failure else {
                        self.succeedClone(session: session, uid: uid)
                        return
                    }
                    WorkflowTraceStore.log(path: "nfc", step: "clone.write-stopped", details: [
                        "uid": uid ?? "", "cause": failure,
                        "pagesWritten": String(pagesWritten), "pages": String(pages.count)
                    ])
                    self.failClone(session: session, reason: Self.rawCloneFailureMessage(
                        pagesWritten: pagesWritten, totalPages: pages.count, refused: refused, cause: failure
                    ))
                }
            }
        }
    }

    private func failClone(session: NFCTagReaderSession, reason: String) {
        WorkflowTraceStore.log(path: "nfc", step: "clone.failed", details: ["reason": reason])
        finishClone(session: session, result: .failed(reason), errorMessage: reason)
    }

    private func succeedClone(session: NFCTagReaderSession, uid: String?) {
        WorkflowTraceStore.log(path: "nfc", step: "clone.ok", details: ["uid": uid ?? ""])
        finishClone(session: session, result: .written(uid: uid.map(SpoolMappingService.normalizeUID)), errorMessage: nil)
    }

    /// The one way a clone ends. `lastWriteSucceeded` is deliberately left
    /// alone: views observing it add the write to Recent Tags as filament data,
    /// and a clone is not one. The tag ledger is left alone for the same
    /// reason — it changes only when the caller links the copy.
    private func finishClone(session: NFCTagReaderSession, result: CloneWriteResult, errorMessage: String?) {
        pendingWrite = nil
        DispatchQueue.main.async {
            self.lastClone = result
            self.isScanning = false
        }
        if let errorMessage {
            session.invalidate(errorMessage: errorMessage)
        } else {
            session.alertMessage = "Tag copied."
            session.invalidate()
        }
    }

    // MARK: - Location Write (NDEF over a tag session)

    /// NDEF write over a tag session. Deliberately separate from
    /// `handleNDEFWrite`: that one is typed to `NFCNDEFReaderSession`, writes a
    /// single MIME record for a `TagFormat`, and is inside the filament
    /// round-trip invariant's blast radius. This writes two records and knows
    /// nothing about `TagFormat`.
    private func handleLocationWrite(session: NFCTagReaderSession, tag: NFCTag) {
        guard let payload = pendingWrite?.locationPayload else {
            session.invalidate(errorMessage: "No location to write.")
            return
        }

        let uid = normalizedUID(from: tag)

        if case .blocked(let blockedUID) = Self.locationWriteDecision(uid: uid, blockedUIDs: blockedWriteUIDs) {
            WorkflowTraceStore.log(path: "nfc", step: "write.location-blocked", details: ["uid": blockedUID])
            DispatchQueue.main.async {
                self.lastLocationWrite = .blocked(uid: blockedUID)
                self.isScanning = false
            }
            pendingWrite = nil
            blockedWriteUIDs = []
            session.invalidate(errorMessage: "This tag is linked to a spool or a filament.")
            return
        }

        guard let ndefTag = getNDEFTag(from: tag) else {
            self.finishLocationWrite(session: session, result: .failed("This tag cannot hold an NDEF message."))
            return
        }

        guard let mimePayload = payload.encoded(),
              let textRecord = NFCNDEFPayload.wellKnownTypeTextPayload(
                  string: payload.textRecordString, locale: Locale(identifier: "en")
              ) else {
            self.finishLocationWrite(session: session, result: .failed("The location could not be encoded."))
            return
        }

        let mimeRecord = NFCNDEFPayload(
            format: .media,
            type: Data(LocationTagPayload.mimeType.utf8),
            identifier: Data(),
            payload: mimePayload
        )
        let message = NFCNDEFMessage(records: [textRecord, mimeRecord])

        queryNDEFStatusPreparingBlankTag(tag, ndefTag: ndefTag) { status, capacity, _, prepared in
            guard status == .readWrite else {
                self.finishLocationWrite(session: session, result: .failed(
                    Self.ndefStatusRefusal(status, preparedBlankTag: prepared)
                ))
                return
            }
            if capacity > 0 && message.length > capacity {
                self.finishLocationWrite(session: session, result: .failed(
                    "Tag is too small. Needs \(message.length) bytes but tag only has \(capacity) bytes available."
                ))
                return
            }

            ndefTag.writeNDEF(message) { error in
                if let error {
                    self.finishLocationWrite(session: session, result: .failed("Write failed: \(error.localizedDescription)"))
                    return
                }
                WorkflowTraceStore.log(path: "nfc", step: "write.location-ok", details: [
                    "uid": uid ?? "", "location": payload.name
                ])
                DispatchQueue.main.async { self.lastWriteSucceeded = true }
                self.finishLocationWrite(session: session, result: .written(uid: uid))
            }
        }
    }

    /// Writes a single empty NDEF record — the canonical erased state, and
    /// better than a zero-record message, which some tag types reject outright.
    private func handleClearWrite(session: NFCTagReaderSession, tag: NFCTag) {
        guard case .clear(let expectedUID, let zeroPages) = pendingWrite else {
            session.invalidate(errorMessage: "Nothing to clear.")
            return
        }

        let uid = normalizedUID(from: tag)

        // A nil expectation clears whatever is presented; a nil READING cannot
        // be checked against one and is allowed through, matching
        // `locationWriteDecision`'s reasoning for ISO 15693 tags.
        if let expectedUID, let uid, uid != expectedUID {
            self.finishClear(session: session, result: .wrongTag(uid: uid),
                             errorMessage: "That is a different tag. Nothing was changed.")
            return
        }

        // A raw-format tag is not NDEF, so `queryNDEFStatus` answers
        // notSupported and an NDEF write would be refused with a misleading
        // "Tag is not writable". Zero the snapshot's pages instead, through
        // the same guards a clone runs.
        if !zeroPages.isEmpty, case .miFare(let miFareTag) = tag {
            self.rawClear(session: session, tag: miFareTag, zeroPages: zeroPages, uid: uid)
            return
        }

        guard let ndefTag = getNDEFTag(from: tag) else {
            self.finishClear(session: session, result: .failed("This tag cannot hold an NDEF message."),
                             errorMessage: "This tag cannot hold an NDEF message.")
            return
        }

        let message = NFCNDEFMessage(records: [
            NFCNDEFPayload(format: .empty, type: Data(), identifier: Data(), payload: Data())
        ])

        ndefTag.queryNDEFStatus { status, _, _ in
            guard status == .readWrite else {
                let reason = status == .readOnly ? "Tag is read-only (write-protected)." : "Tag is not writable."
                self.finishClear(session: session, result: .failed(reason), errorMessage: reason)
                return
            }

            ndefTag.writeNDEF(message) { error in
                if let error {
                    let reason = "Clearing failed: \(error.localizedDescription)"
                    self.finishClear(session: session, result: .failed(reason), errorMessage: reason)
                    return
                }
                WorkflowTraceStore.log(path: "nfc", step: "write.tag-cleared", details: ["uid": uid ?? ""])
                self.finishClear(session: session, result: .cleared(uid: uid), errorMessage: nil)
            }
        }
    }

    private func finishClear(session: NFCTagReaderSession, result: TagClearResult, errorMessage: String?) {
        pendingWrite = nil
        DispatchQueue.main.async {
            self.lastTagClear = result
            self.isScanning = false
        }
        if let errorMessage {
            session.invalidate(errorMessage: errorMessage)
        } else {
            session.alertMessage = "Tag cleared."
            session.invalidate()
        }
    }

    /// The raw-format half of an erase: zero the scan snapshot's pages,
    /// highest first, behind the same guards a clone runs — static locks
    /// (`readHeaderAllowsWrite`) and password protection (`checkWritePassword`)
    /// each refuse with their own honest reason, and a mid-write refusal
    /// reports how far it got (`writePages`).
    private func rawClear(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        zeroPages: [Int],
        uid: String?
    ) {
        let pages = Self.clearPagePlan(zeroPages: zeroPages)
        guard let lastPage = pages.first?.page, lastPage <= 255 else {
            self.finishClear(session: session, result: .failed(Self.noErasablePagesMessage),
                             errorMessage: Self.noErasablePagesMessage)
            return
        }

        WorkflowTraceStore.log(path: "nfc", step: "erase.raw-start", details: [
            "uid": uid ?? "", "pages": String(pages.count), "lastPage": String(lastPage)
        ])

        readHeaderAllowsWrite(tag: tag) { allowed in
            guard allowed else {
                WorkflowTraceStore.log(path: "nfc", step: "erase.locked", details: ["uid": uid ?? ""])
                self.finishClear(session: session, result: .failed(Self.clearLockedMessage),
                                 errorMessage: Self.clearLockedMessage)
                return
            }

            self.checkWritePassword(tag: tag, throughPage: lastPage) { needsPassword, _ in
                guard !needsPassword else {
                    WorkflowTraceStore.log(path: "nfc", step: "erase.password-protected", details: ["uid": uid ?? ""])
                    self.finishClear(session: session,
                                     result: .failed(Self.clearPasswordMessage),
                                     errorMessage: Self.clearPasswordMessage)
                    return
                }

                self.writePages(tag: tag, pages: pages) { failure, pagesWritten, _ in
                    if let failure {
                        WorkflowTraceStore.log(path: "nfc", step: "erase.raw-stopped", details: [
                            "uid": uid ?? "", "cause": failure, "pagesWritten": String(pagesWritten)
                        ])
                        self.finishClear(session: session,
                                         result: .failed(Self.rawWriteFailureMessage(
                                             pagesWritten: pagesWritten, totalPages: pages.count, cause: failure
                                         )),
                                         errorMessage: Self.rawWriteFailureMessage(
                                             pagesWritten: pagesWritten, totalPages: pages.count, cause: failure
                                         ))
                        return
                    }
                    WorkflowTraceStore.log(path: "nfc", step: "erase.raw-ok", details: [
                        "uid": uid ?? "", "pages": String(pages.count)
                    ])
                    self.finishClear(session: session, result: .cleared(uid: uid), errorMessage: nil)
                }
            }
        }
    }

    private func finishLocationWrite(session: NFCTagReaderSession, result: LocationWriteResult) {
        pendingWrite = nil
        blockedWriteUIDs = []
        DispatchQueue.main.async {
            self.lastLocationWrite = result
            self.isScanning = false
        }
        if case .written = result {
            session.alertMessage = "Location tag written!"
            session.invalidate()
        } else if case .failed(let reason) = result {
            session.invalidate(errorMessage: reason)
        }
    }

    // MARK: - Ledger

    /// Records (or clears) the tag ledger after a successful write, when the UID
    /// is known. A write carrying a spool id upserts; a write without one clears
    /// the entry (the tag no longer maps to a spool). Blind NDEF writes (uid nil)
    /// do nothing — captured on the tag's next read. Thread-safe; off-main is fine.
    private func recordLedgerAfterWrite(uid: String?, data: FilamentTagData) {
        guard let uid, !uid.isEmpty else { return }
        if let spoolId = data.spoolmanId {
            TagAssociationStore.shared.record(uid: uid, spoolId: spoolId)
        } else {
            TagAssociationStore.shared.remove(uid: uid)
        }
    }

    // MARK: - ACE Raw Page Read (sequential)

    private func readACEPagesSequentially(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        readPages: [Int],
        index: Int,
        buffer: NSMutableData,
        completion: @escaping (Error?) -> Void
    ) {
        guard index < readPages.count else {
            completion(nil)
            return
        }

        let page = readPages[index]

        // NTAG READ command: 0x30, page number — returns 16 bytes (4 pages)
        let readCommand = Data([0x30, UInt8(page)])

        tag.sendMiFareCommand(commandPacket: readCommand) { [weak self] data, error in
            if let error = error {
                completion(error)
                return
            }

            guard Self.isValidRawReadResponse(data) else {
                let responseError = NSError(
                    domain: "NFCManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected raw read response length: \(data.count)"]
                )
                completion(responseError)
                return
            }

            // Copy returned bytes into the buffer at the correct offset
            let startByte = page * AnycubicACEPayload.bytesPerPage
            let copyLen = 16
            let range = NSRange(location: startByte, length: min(copyLen, buffer.length - startByte))
            if range.length > 0 {
                data.withUnsafeBytes { ptr in
                    if let baseAddr = ptr.baseAddress {
                        buffer.replaceBytes(in: range, withBytes: baseAddr)
                    }
                }
            }

            self?.readACEPagesSequentially(
                session: session,
                tag: tag,
                readPages: readPages,
                index: index + 1,
                buffer: buffer,
                completion: completion
            )
        }
    }

    // MARK: - Tag Dump (Diagnostics)

    /// Reads upward from page 0 until the tag errors or wraps.
    ///
    /// `NFCManager` is not `@MainActor` — this runs on CoreNFC's callback
    /// queue like every other read here, and touches `@Published` state only
    /// through an explicit hop to main.
    private func dumpAllPages(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        uid: String
    ) {
        WorkflowTraceStore.log(path: "nfc", step: "dump.start", details: ["uid": uid])

        readVersion(tag: tag) { [weak self] chipVersion, pageCount in
            guard let self = self else { return }
            self.readDumpBlock(
                session: session, tag: tag, uid: uid, page: 0,
                buffer: NSMutableData(), firstPage: nil,
                chipVersion: chipVersion, pageCount: pageCount
            )
        }
    }

    /// One 4-page read, then the next.
    ///
    /// The accumulated bytes travel in an `NSMutableData` and the first block
    /// travels as a parameter, mirroring `readACEPagesSequentially`. Capturing
    /// mutable locals in these escaping callbacks instead would be a data race
    /// the compiler is entitled to reject under Swift 6.
    ///
    /// `pageCount` is what the chip said about itself via GET_VERSION. When it
    /// is known it is the bound, because the wrap heuristic is only a guess:
    /// a page that happens to repeat page 0's four bytes would end the walk
    /// early and the dump would look like a normal completion.
    private func readDumpBlock(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        uid: String,
        page: Int,
        buffer: NSMutableData,
        firstPage: [UInt8]?,
        chipVersion: String?,
        pageCount: Int?
    ) {
        // Page addresses are a single byte, so 255 is the hard ceiling. A tag
        // that neither errors nor wraps still has to stop.
        guard page < 256 else {
            finishDump(session: session, tag: .miFare(tag), uid: uid, bytes: [UInt8](buffer as Data),
                       chipVersion: chipVersion, endedBy: .error)
            return
        }

        // The chip's own count reached: a complete read, not a failure.
        if let pageCount = pageCount, page >= pageCount {
            finishDump(session: session, tag: .miFare(tag), uid: uid, bytes: [UInt8](buffer as Data),
                       chipVersion: chipVersion, endedBy: .endOfTag)
            return
        }

        tag.sendMiFareCommand(commandPacket: Data([0x30, UInt8(page)])) { [weak self] data, error in
            guard let self = self else { return }

            if error != nil || !Self.isValidRawReadResponse(data) {
                self.finishDump(session: session, tag: .miFare(tag), uid: uid, bytes: [UInt8](buffer as Data),
                                chipVersion: chipVersion, endedBy: .error)
                return
            }

            let block = [UInt8](data)
            let first = firstPage ?? Array(block.prefix(4))

            if let pageCount = pageCount {
                // Authoritative bound. The last read still comes back wrapped
                // — page counts are not multiples of four — but how much of it
                // is real is arithmetic here, not a byte comparison.
                let remaining = pageCount - page
                if remaining < TagDumpWalk.pagesPerRead {
                    buffer.append(Data(block.prefix(remaining * 4)))
                    self.finishDump(session: session, tag: .miFare(tag), uid: uid, bytes: [UInt8](buffer as Data),
                                    chipVersion: chipVersion, endedBy: .endOfTag)
                    return
                }
            } else {
                // No GET_VERSION answer, so the only signal left is the wrap
                // itself: NTAG page counts are not multiples of four, so the
                // last read returns one to three real pages and then the start
                // of the tag again. Only the real ones are kept.
                let realPages = TagDumpWalk.realPageCount(in: block, firstPage: first, atPage: page)
                if realPages < TagDumpWalk.pagesPerRead {
                    buffer.append(Data(block.prefix(realPages * 4)))
                    self.finishDump(session: session, tag: .miFare(tag), uid: uid, bytes: [UInt8](buffer as Data),
                                    chipVersion: chipVersion, endedBy: .wrap)
                    return
                }
            }

            buffer.append(data)
            self.readDumpBlock(
                session: session, tag: tag, uid: uid,
                page: page + TagDumpWalk.pagesPerRead,
                buffer: buffer, firstPage: first,
                chipVersion: chipVersion, pageCount: pageCount
            )
        }
    }

    /// GET_VERSION, which not every Ultralight-compatible tag answers. A tag
    /// that refuses it is still dumped; the field is simply absent and the walk
    /// falls back to watching for the wrap.
    ///
    /// Hands back both the part name and the page count behind it — the count
    /// is what bounds the walk, and deriving it twice from the same reply is
    /// how the two could disagree.
    private func readVersion(tag: NFCMiFareTag, completion: @escaping (String?, Int?) -> Void) {
        tag.sendMiFareCommand(commandPacket: Data([0x60])) { data, error in
            guard error == nil,
                  let pages = TagDumpWalk.pageCount(forVersionResponse: [UInt8](data)) else {
                completion(nil, nil)
                return
            }
            completion(TagDumpWalk.chipName(forPageCount: pages), pages)
        }
    }

    // MARK: - Tag Dump (ISO 15693)

    /// Reads an ISO 15693 tag block by block.
    ///
    /// A separate walk from the NTAG one because the two share no commands:
    /// there is no READ (0x30) here, and no wrap to watch for either. An ISO
    /// 15693 tag refuses a block past its end, so running off the end is the
    /// terminator — which makes this walk shorter than the NTAG one, not
    /// longer.
    ///
    /// The Prusament's OpenPrintTag is an ICODE SLIX2 and lands here. The
    /// explorer used to turn it away with "This tag type cannot be read page
    /// by page" (owner device pass, 2026-09-07).
    private func dumpAllBlocks(
        session: NFCTagReaderSession,
        tag: NFCISO15693Tag,
        uid: String
    ) {
        WorkflowTraceStore.log(path: "nfc", step: "dump.start", details: [
            "uid": uid,
            "family": "iso15693"
        ])

        // Asked for the record, not to bound the walk: Get System Info's block
        // count is reported inconsistently across tags, and a bound that is
        // one block short would silently truncate every dump. The tag's own
        // refusal is the reliable end.
        tag.getSystemInfo(requestFlags: [.highDataRate]) { [weak self] result in
            guard let self = self else { return }
            let reference: String? = switch result {
            case .success(let info): TagDumpWalk.describeICReference(info.icReference)
            case .failure: nil
            }
            let chipVersion = TagDumpWalk.icodeName(forUID: [UInt8](tag.identifier)) ?? reference
            self.readAllBlocks(tag) { bytes in
                // A refusal with nothing behind it is a failure — the dump
                // would be empty. A refusal after any block at all is the end
                // of the tag, which is how every ISO 15693 dump ends.
                self.finishDump(
                    session: session, tag: .iso15693(tag), uid: uid, bytes: bytes,
                    chipVersion: chipVersion, endedBy: bytes.isEmpty ? .error : .endOfTag
                )
            }
        }
    }

    /// Every block an ISO 15693 tag will return, from `block` to its end.
    ///
    /// Several blocks at a time, falling back to one at a time: Read Multiple
    /// Blocks is optional in ISO 15693 and a range that straddles the end of
    /// the tag fails whole. Both look identical from here, and both are
    /// answered the same way — single blocks distinguish a tag that cannot do
    /// range reads from a tag that has simply ended, and find the exact last
    /// block either way. Shared by the Tag Explorer's dump and the scan's
    /// empty-tag verdict; empty when the tag refused the first block.
    private func readAllBlocks(
        _ tag: NFCISO15693Tag,
        from block: Int = 0,
        into buffer: NSMutableData = NSMutableData(),
        completion: @escaping ([UInt8]) -> Void
    ) {
        guard block < TagDumpWalk.blockCeiling else {
            completion([UInt8](buffer as Data))
            return
        }

        tag.readMultipleBlocks(
            requestFlags: [.highDataRate],
            blockRange: NSRange(location: block, length: TagDumpWalk.blocksPerRead)
        ) { [weak self] result in
            guard let self = self else { return }
            guard case .success(let blocks) = result, !blocks.isEmpty else {
                self.readBlocksSingly(tag, from: block, into: buffer, completion: completion)
                return
            }
            for data in blocks { buffer.append(data) }
            self.readAllBlocks(tag, from: block + blocks.count, into: buffer, completion: completion)
        }
    }

    /// One block at a time until the tag refuses one.
    private func readBlocksSingly(
        _ tag: NFCISO15693Tag,
        from block: Int,
        into buffer: NSMutableData,
        completion: @escaping ([UInt8]) -> Void
    ) {
        guard block < TagDumpWalk.blockCeiling else {
            completion([UInt8](buffer as Data))
            return
        }

        tag.readSingleBlock(
            requestFlags: [.highDataRate],
            blockNumber: UInt8(block)
        ) { [weak self] result in
            guard let self = self else { return }
            guard case .success(let data) = result, !data.isEmpty else {
                completion([UInt8](buffer as Data))
                return
            }
            buffer.append(data)
            self.readBlocksSingly(tag, from: block + 1, into: buffer, completion: completion)
        }
    }

    /// Ends a dump before it starts: no session, no result, one message the
    /// explorer can show.
    private func failDump(session: NFCTagReaderSession, message: String) {
        session.invalidate(errorMessage: message)
        DispatchQueue.main.async {
            self.tagDumpError = message
            self.isScanning = false
        }
    }

    private func finishDump(
        session: NFCTagReaderSession,
        tag: NFCTag,
        uid: String,
        bytes: [UInt8],
        chipVersion: String?,
        endedBy: TagDump.EndReason
    ) {
        let pages = TagDump.hexPages(from: bytes)

        // A dump of nothing is not a dump. Without this the explorer offers
        // "Keep This Dump" for zero pages, which burns one of the twenty
        // capture slots on a record that says only that a read failed — and
        // the failure is already the message the tester needs.
        guard !pages.isEmpty else {
            failDump(session: session, message: "Nothing could be read from this tag.")
            return
        }

        let decoded = describeDump(bytes: bytes)

        WorkflowTraceStore.log(path: "nfc", step: "dump.finished", details: [
            "uid": uid,
            "pages": String(pages.count),
            "endedBy": endedBy.rawValue
        ])

        let dump = TagDump(
            capturedAt: Date(),
            uid: uid,
            tagType: self.tagTypeName(tag),
            chipVersion: chipVersion,
            pagesRead: pages.count,
            endedBy: endedBy,
            pages: pages,
            decodedAs: decoded,
            note: "",
            appVersion: AppConfig.versionString
        )

        session.alertMessage = "Read \(pages.count) pages."
        session.invalidate()
        DispatchQueue.main.async {
            self.tagDumpResult = dump
            self.isScanning = false
        }
    }

    /// What a dump is, as far as SpoolKid can tell.
    ///
    /// This attempted Anycubic ACE and nothing else until 2026-09-07, so a
    /// SpoolKid-written OpenSpool tag — read perfectly by the Scan Hub two
    /// screens away — came back as "Nothing recognised it". The raw formats
    /// go first because they have no NDEF structure to find; the NDEF walk
    /// then answers for everything else, including tags in formats nothing
    /// here decodes.
    func describeDump(bytes: [UInt8]) -> String? {
        if TagFormatService.shared.decodeAnycubicACE(pages: bytes) != nil {
            return TagFormat.anycubicACE.displayName
        }
        if TagFormatService.shared.decodeElegoo(pages: bytes) != nil {
            return TagFormat.elegoo.displayName
        }
        if bytes.count >= TigerTagPayload.firstUserPageOffset + TigerTagPayload.totalByteCount {
            let fromPage4 = Array(bytes[TigerTagPayload.firstUserPageOffset
                                        ..< TigerTagPayload.firstUserPageOffset + TigerTagPayload.totalByteCount])
            if let name = TigerTagPayload.dumpName(for: fromPage4) {
                return name
            }
        }
        return TagDumpDecode.nameForNDEF(in: bytes)
    }

    // MARK: - Helpers

    /// Extracts the NDEF tag from a generic NFCTag.
    private func getNDEFTag(from tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let t): return t
        case .iso15693(let t): return t
        case .iso7816(let t): return t
        case .feliCa(let t): return t
        @unknown default: return nil
        }
    }

    /// Normalizes any tag's identifier to a lowercase hex string.
    private func normalizedUID(from tag: NFCTag) -> String? {
        let identifier: Data
        switch tag {
        case .miFare(let t): identifier = t.identifier
        case .iso15693(let t): identifier = t.identifier
        case .iso7816(let t): identifier = t.identifier
        case .feliCa(let t): identifier = t.currentIDm
        @unknown default: return nil
        }
        
        let bytes = [UInt8](identifier)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return hex.isEmpty ? nil : hex
    }

    /// Extracts the MIME type string from an NDEF record.
    func getMimeType(from record: NFCNDEFPayload) -> String? {
        if record.typeNameFormat == .media {
            return String(data: record.type, encoding: .utf8)
        }
        return nil
    }

    /// Extracts payload data from an NDEF record.
    func getPayloadData(from record: NFCNDEFPayload) -> Data? {
        // If it's a MIME type record
        if record.typeNameFormat == .media {
             return record.payload
        }
        // If it's a Well Known Text record, strip the language code
        if record.typeNameFormat == .nfcWellKnown && record.type == Data([0x54]) { // 'T'
            let payload = record.payload
            guard payload.count > 0 else { return nil }
            let statusByte = payload[0]
            let languageCodeLength = Int(statusByte & 0x3F)
            guard payload.count > 1 + languageCodeLength else { return nil }
            return payload.subdata(in: (1 + languageCodeLength)..<payload.count)
        }

        return nil
    }


    static func isValidRawReadResponse(_ data: Data) -> Bool {
        data.count == 16
    }

    /// Whether a WRITE (0xA2) reply is the tag accepting the page.
    ///
    /// An NTAG answers a WRITE with a 4-bit ACK (0xA) or a NAK (0x0, 0x1, 0x4,
    /// 0x5). The ACE write used to ignore the reply, so a NAK CoreNFC hands back
    /// as data rather than as an error would have been reported as written.
    /// An empty reply is accepted: CoreNFC may consume the ACK itself.
    static func isAcknowledgedWriteResponse(_ data: Data) -> Bool {
        guard let first = data.first else { return true }
        return first & 0x0F == 0x0A
    }

    /// CFG0 sits four pages before the end of an NTAG213, 215 or 216.
    static func configPage(forPageCount pageCount: Int) -> Int {
        pageCount - 4
    }

    /// Whether writing through `lastPage` reaches a page only a password holder
    /// may write, from the READ reply at the CFG0 page (CFG0, CFG1, PWD, PACK).
    ///
    /// Byte 3 of CFG0 is AUTH0, the first protected page. Writes from AUTH0 on
    /// need the password whether or not reads do (PROT only adds reads), so
    /// AUTH0 alone decides. Factory Anycubic tags carry AUTH0 = 4. Nil when the
    /// reply is not a full READ.
    static func writeNeedsPassword(configRead: Data, throughPage lastPage: Int) -> Bool? {
        guard isValidRawReadResponse(configRead) else { return nil }
        let firstProtectedPage = Int(configRead[configRead.startIndex + 3])
        return lastPage >= firstProtectedPage
    }

    /// The page writes an erase issues for a raw-format tag: every page the
    /// scan's snapshot saw, zeroed, highest page first (`rawWriteOrder`) so a
    /// chip that refuses refuses before anything lands. The snapshot range is
    /// the range the format owns — the same pages a clone proved writable on
    /// the same chip — never a speculative sweep past it.
    static func clearPagePlan(zeroPages: [Int]) -> [(page: Int, data: Data)] {
        let zero = Data(repeating: 0, count: 4)
        var seen = Set<Int>()
        let unique = zeroPages.filter { seen.insert($0).inserted }
        return rawWriteOrder(unique.map { ($0, zero) })
    }

    static func shouldTryACEFallback(afterElegooFailure: Bool) -> Bool {
        afterElegooFailure
    }

    static func rawReadFollowupAction(
        elegooReadSucceeded: Bool,
        shouldTryACEFallback: Bool
    ) -> RawReadFollowupAction {
        if elegooReadSucceeded {
            return .stop
        }

        return shouldTryACEFallback ? .tryAnycubicACE : .emitUIDOnly
    }
}

// MARK: - NDEF Payload Helpers

extension NFCNDEFPayload {
    static func wellKnownTypeJSONPayload(string: String) -> NFCNDEFPayload? {
        guard let payloadData = string.data(using: .utf8),
              let typeData = "application/json".data(using: .utf8) else { return nil }
        return NFCNDEFPayload(
            format: .media,
            type: typeData,
            identifier: Data(),
            payload: payloadData
        )
    }
}


// MARK: - Toolhead reader

/// The printer path: the same entry points, run by a `PrinterTagSession` and
/// published into the same properties the iPhone path sets. Never falls back to
/// the iPhone when the printer cannot be used.
extension NFCManager {

    private func printerSession(toolhead: Int) -> PrinterTagSession? {
        Self.printerTagGateway.map { PrinterTagSession(gateway: $0, toolhead: toolhead) }
    }

    private var noPrinterMessage: String {
        PrinterTagError.notReady("No printer is connected.").message(toolhead: 0)
    }

    fileprivate func startPrinterScan(toolhead: Int, rejectingLocationTags: Bool) {
        guard !isScanning else { return }
        pendingWrite = nil
        isDumping = false
        guard let session = printerSession(toolhead: toolhead) else {
            alertMessage = noPrinterMessage
            return
        }
        isScanning = true
        Task {
            switch await session.scan(rejectingLocationTags: rejectingLocationTags) {
            case .result(let result):
                scanResult = result
            case .refused(let message, let result):
                // A rejected location tag still publishes its result; the caller words the refusal.
                if let result { scanResult = result }
                alertMessage = message
            case .failed(let error):
                alertMessage = error.message(toolhead: toolhead)
            }
            isScanning = false
        }
    }

    fileprivate func startPrinterDump(toolhead: Int) {
        guard !isScanning else { return }
        pendingWrite = nil
        isDumping = false
        tagDumpResult = nil
        tagDumpError = nil
        guard let session = printerSession(toolhead: toolhead) else {
            tagDumpError = noPrinterMessage
            return
        }
        isScanning = true
        Task {
            switch await session.dump() {
            case .success(let dump): tagDumpResult = dump
            case .failure(let error): tagDumpError = error.message(toolhead: toolhead)
            }
            isScanning = false
        }
    }

    fileprivate func startPrinterWrite(_ write: PendingWrite, toolhead: Int) {
        guard !isScanning else { return }
        isDumping = false
        switch write {
        case .filament:
            lastWriteSucceeded = false
            lastWrittenTagUID = nil
        case .clear:
            lastWriteSucceeded = false
            lastTagClear = nil
        case .clone:
            lastClone = nil
        case .location:
            break
        }
        guard let session = printerSession(toolhead: toolhead) else {
            publishPrinterWrite(.failed(message: noPrinterMessage), for: write)
            return
        }
        pendingWrite = write
        isScanning = true
        Task {
            let outcome = await session.perform(write, blockedUIDs: [])
            publishPrinterWrite(outcome, for: write)
            isScanning = false
        }
    }

    /// Sets what the iPhone path's finishers set. A filament write has no result
    /// property of its own, so its refusals and failures go to `alertMessage`
    /// (on the iPhone the invalidated session does that).
    private func publishPrinterWrite(_ outcome: PrinterWriteOutcome, for write: PendingWrite) {
        switch write {
        case .filament(let data, _, _):
            switch outcome {
            case .written(let uid):
                lastWrittenTagUID = uid
                lastWriteSucceeded = true
                // pendingWrite stays: the views read tagDataToWrite and writeFormatToUse
                // after a success, as they do on the iPhone path.
                recordLedgerAfterWrite(uid: uid, data: data)
            case .refused(let message):
                pendingWrite = nil
                alertMessage = message
            case .failed(let message):
                pendingWrite = nil
                alertMessage = message
            case .blocked:
                pendingWrite = nil
                alertMessage = "This tag belongs to something else."
            case .wrongTag, .sameTag:
                break
            }
        case .clear:
            pendingWrite = nil
            switch outcome {
            case .written(let uid): lastTagClear = .cleared(uid: uid)
            case .wrongTag(let uid): lastTagClear = .wrongTag(uid: uid)
            case .refused(let message), .failed(let message): lastTagClear = .failed(message)
            case .blocked, .sameTag: lastTagClear = .failed("Tag is not writable.")
            }
        case .clone:
            pendingWrite = nil
            switch outcome {
            case .written(let uid): lastClone = .written(uid: SpoolMappingService.normalizeUID(uid))
            case .blocked(let uid): lastClone = .blocked(uid: uid)
            case .sameTag: lastClone = .sameTag
            case .refused(let message), .failed(let message): lastClone = .failed(message)
            case .wrongTag: lastClone = .failed("That is a different tag. Nothing was changed.")
            }
        case .location:
            pendingWrite = nil
            if case .refused(let message) = outcome { alertMessage = message }
        }
    }
}
