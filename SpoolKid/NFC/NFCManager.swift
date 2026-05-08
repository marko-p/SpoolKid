//
//  NFCManager.swift
//  SpoolKid
//
//  Purpose: Core logic for interacting with CoreNFC.
//  Responsibilities:
//  - Managing NFCNDEFReaderSession (for OpenSpool, OpenPrintTag, OpenTag3D).
//  - Managing NFCTagReaderSession (for Anycubic ACE raw page access and Bambu Lab UID detection).
//  - Reading NDEF messages and decoding them into `FilamentTagData`.
//  - Auto-detecting the tag format on read.
//  - Encoding `FilamentTagData` and writing to NFC tags in the selected format.
//  - Emitting a structured `ScanResult` for the Scan Result Hub.
//  - Handling errors and session invalidation.
//
//  Scan flow:
//  - `startScanning()`: unified scan via NFCTagReaderSession (iso14443).
//    Detects MIFARE Ultralight/NTAG (NDEF) and MIFARE Classic (Bambu).
//    For NTAG tags: attempts NDEF read first, then ACE raw fallback.
//    For MIFARE Classic tags: emits Bambu probe result (UID only; data encrypted on iOS).
//  - `startScanningRaw()`: retained for explicit "Scan ACE Tag" menu entry (same session type).
//  - `writeTag(data:)`: unchanged; uses NDEF session for NDEF formats, tag session for ACE.
//
//  Important for Contributors:
//  - iOS requires a valid provisioning profile with "NFC Tag Reading" capability.
//  - NFC only works on physical devices, not the simulator.
//  - The `Info.plist` must contain `NFCReaderUsageDescription`.
//  - The entitlements must include the `TAG` format for raw tag access.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC
import Combine

// Note: NFCManager intentionally does NOT use @MainActor on the class level.
// CoreNFC invokes delegate callbacks on background threads,
// so the delegate methods must remain callable off the main thread. Instead,
// @Published property updates are explicitly dispatched to the main queue.
// Internal mutable state (isWriting, tagDataToWrite) is protected by a serial queue.
class NFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate, NFCTagReaderSessionDelegate {

    private static let openPrintTagURLMIMEType = "text/plain"

    @Published var alertMessage = ""
    @Published var isScanning = false
    /// Structured result of the most recent scan. Emitted for every completed read.
    @Published var scanResult: ScanResult?
    @Published var lastWriteSucceeded = false

    /// Backward-compatible convenience accessor. Returns the decoded filament data from `scanResult`.
    var scannedData: FilamentTagData? {
        get { scanResult?.tagData }
        set {
            // Allow callers (e.g. TagsTabView) to nil this out after consumption.
            if newValue == nil { scanResult = nil }
        }
    }

    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?
    // Thread-safe access to mutable state shared between main thread and NFC delegate callbacks.
    private let stateQueue = DispatchQueue(label: "com.spoolkid.nfcmanager.state")
    private var _isWriting = false
    private var _tagDataToWrite: FilamentTagData?
    private var _writeFormatToUse: TagFormat?
    private var isWriting: Bool {
        get { stateQueue.sync { _isWriting } }
        set { stateQueue.sync { _isWriting = newValue } }
    }

    /// The data most recently passed to `writeTag(data:)`. Accessible for post-write actions.
    private(set) var tagDataToWrite: FilamentTagData? {
        get { stateQueue.sync { _tagDataToWrite } }
        set { stateQueue.sync { _tagDataToWrite = newValue } }
    }

    private var writeFormatToUse: TagFormat? {
        get { stateQueue.sync { _writeFormatToUse } }
        set { stateQueue.sync { _writeFormatToUse = newValue } }
    }

    // MARK: - Public API

    /// Unified scan: uses NFCTagReaderSession to handle all tag families.
    /// Dispatches to NDEF read for NTAG/Ultralight tags and to Bambu probe for MIFARE Classic.
    func startScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        isWriting = false
        startTagSession(message: "Hold your iPhone near the NFC tag to read.")
    }

    /// Explicit ACE scan — same session type as `startScanning()`, kept for menu entry.
    func startScanningRaw() {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        isWriting = false
        startTagSession(message: "Hold your iPhone near the NFC tag to read.")
    }

    func writeTag(data: FilamentTagData) {
        writeTag(data: data, format: TagFormatService.shared.currentFormat)
    }

    func writeTag(data: FilamentTagData, format: TagFormat) {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }

        tagDataToWrite = data
        writeFormatToUse = format
        isWriting = true
        lastWriteSucceeded = false

        if format == .anycubicACE {
            // ACE requires raw page writes via NFCTagReaderSession
            startTagSession(message: "Hold your iPhone near the NFC tag to write (ACE format).")
        } else {
            // All other formats use NDEF session for writing
            startNDEFSession(message: "Hold your iPhone near the NFC tag to write.")
        }
    }

    // MARK: - Session Management

    private func startNDEFSession(message: String) {
        ndefSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        ndefSession?.alertMessage = message
        ndefSession?.begin()
        DispatchQueue.main.async { self.isScanning = true }
    }

    private func startTagSession(message: String) {
        tagSession = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
        tagSession?.alertMessage = message
        tagSession?.begin()
        DispatchQueue.main.async { self.isScanning = true }
    }

    // MARK: - NFCNDEFReaderSessionDelegate (write path only)

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
            if let readerError = error as? NFCReaderError {
                if readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead &&
                   readerError.code != .readerSessionInvalidationErrorUserCanceled {
                    self.alertMessage = "Session invalidated: \(error.localizedDescription)"
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not used when we implement didDetect tags
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.restartPolling()
            return
        }

        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }

            tag.queryNDEFStatus { (status: NFCNDEFStatus, capacity: Int, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Fail to query status: \(error.localizedDescription)")
                    return
                }

                // NDEF session is only used for writing
                if self.isWriting {
                    self.handleNDEFWrite(session: session, tag: tag, status: status, capacity: capacity)
                }
            }
        }
    }

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
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
            session.restartPolling()
            return
        }

        guard case .miFare(let miFareTag) = tag else {
            session.invalidate(errorMessage: "Tag type is not supported. Expected MIFARE / NTAG.")
            return
        }

        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }

            if self.isWriting {
                self.handleACEWrite(session: session, tag: miFareTag)
            } else {
                self.handleUnifiedRead(session: session, tag: miFareTag)
            }
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active, waiting for tag
    }

    // MARK: - Unified Read (NTAG NDEF → ACE raw → Bambu probe)

    /// Main read dispatcher for the unified scan path.
    /// Order: NDEF read → ACE raw fallback → Bambu UID-only probe.
    private func handleUnifiedRead(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        let identifierBytes = [UInt8](tag.identifier)
        let probe = BambuTagProbe.probe(identifierBytes: identifierBytes, ndefPayload: nil)

        // Try NDEF first (works for NTAG/Ultralight based tags)
        tryNDEFRead(session: session, tag: tag, probe: probe)
    }

    /// Attempt to read NDEF payload from a MiFare tag.
    /// Falls back to ACE raw read on failure.
    private func tryNDEFRead(session: NFCTagReaderSession, tag: NFCMiFareTag, probe: BambuTagProbeResult) {
        // NFCMiFareTag conforms to NFCNDEFTag, so use it directly.
        let ndefTag: NFCNDEFTag = tag

        ndefTag.queryNDEFStatus { status, _, _ in
            // Some tags can still return a readable NDEF payload even when status probing is
            // inconclusive, so we always attempt readNDEF before falling back to raw reads.
            let hintedNotSupported = (status == .notSupported)

            ndefTag.readNDEF { message, error in
                if error != nil {
                    // NDEF read error — try ACE raw before giving up
                    // MIFARE Classic tags commonly fail here with connection/auth errors.
                    self.tryACERawRead(session: session, tag: tag, probe: probe, ndefNotSupported: hintedNotSupported)
                    return
                }

                guard let message = message else {
                    self.tryACERawRead(session: session, tag: tag, probe: probe, ndefNotSupported: hintedNotSupported)
                    return
                }

                var discoveredOpenPrintTagURL: String?
                for record in message.records {
                    if let mimeType = self.getMimeType(from: record)?.lowercased(),
                       mimeType == Self.openPrintTagURLMIMEType,
                       let data = self.getPayloadData(from: record),
                       let urlString = String(data: data, encoding: .utf8),
                       !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        discoveredOpenPrintTagURL = urlString
                    }
                }

                // Try to decode the NDEF payload
                for record in message.records {
                    let mimeType = self.getMimeType(from: record)
                    if let data = self.getPayloadData(from: record),
                       var decoded = TagFormatService.shared.decode(payload: data, mimeType: mimeType) {
                        if let mimeType = mimeType?.lowercased(), mimeType == "application/vnd.openprinttag" {
                            decoded.tagURL = discoveredOpenPrintTagURL
                        }
                        let detectedFormat = self.detectedFormat(from: mimeType)
                        let result = ScanResult(
                            cardUID: probe.normalizedUID.isEmpty ? nil : probe.normalizedUID,
                            tagData: decoded,
                            format: detectedFormat,
                            bambuProbe: nil
                        )
                        session.alertMessage = "Tag read successfully!"
                        session.invalidate()
                        DispatchQueue.main.async { self.scanResult = result; self.isScanning = false }
                        return
                    }
                }

                // NDEF present but no recognized format — fall through to ACE
                self.tryACERawRead(session: session, tag: tag, probe: probe, ndefNotSupported: hintedNotSupported)
            }
        }
    }

    /// Attempt Anycubic ACE raw page read. Surfaces Bambu probe result on failure.
    private func tryACERawRead(
        session: NFCTagReaderSession,
        tag: NFCMiFareTag,
        probe: BambuTagProbeResult,
        ndefNotSupported: Bool
    ) {
        let readPages = [0, 4, 8, 12, 16, 20, 24, 28]
        guard let buffer = NSMutableData(length: AnycubicACEPayload.totalBytes) else {
            emitProbeResult(session: session, probe: probe, strongBambuEvidence: ndefNotSupported)
            return
        }

        readACEPagesSequentially(session: session, tag: tag, readPages: readPages, index: 0, buffer: buffer) { [weak self] error in
            guard let self = self else { return }

            if error != nil {
                // Page read failed — likely MIFARE Classic encryption; emit probe
                self.emitProbeResult(session: session, probe: probe, strongBambuEvidence: ndefNotSupported)
                return
            }

            let bytes = [UInt8](buffer as Data)
            if let tagData = TagFormatService.shared.decodeAnycubicACE(pages: bytes) {
                let uid = probe.normalizedUID.isEmpty ? nil : probe.normalizedUID
                let result = ScanResult(
                    cardUID: uid,
                    tagData: tagData,
                    format: .anycubicACE,
                    bambuProbe: nil
                )
                session.alertMessage = "Tag read successfully! (Anycubic ACE)"
                session.invalidate()
                DispatchQueue.main.async { self.scanResult = result; self.isScanning = false }
            } else {
                // Raw page reads succeeded but format is unknown.
                // This is not strong evidence for Bambu encryption.
                self.emitUnknownReadableResult(session: session, probe: probe)
            }
        }
    }

    /// Emit a UID-only scan result (Bambu encrypted tag or unknown MIFARE tag).
    private func emitProbeResult(
        session: NFCTagReaderSession,
        probe: BambuTagProbeResult,
        strongBambuEvidence: Bool
    ) {
        let uid = probe.normalizedUID.isEmpty ? nil : probe.normalizedUID
        let surfacedProbe = NFCManager.surfacedProbeResult(for: probe, strongBambuEvidence: strongBambuEvidence)

        let result = ScanResult(
            cardUID: uid,
            tagData: nil,
            format: nil,
            bambuProbe: surfacedProbe
        )
        session.alertMessage = "\(surfacedProbe.displayLabel) detected. UID captured."
        session.invalidate()
        DispatchQueue.main.async { self.scanResult = result; self.isScanning = false }
    }

    /// Emit a UID-only result for unknown-but-readable tags (non-encrypted fallback).
    private func emitUnknownReadableResult(session: NFCTagReaderSession, probe: BambuTagProbeResult) {
        let uid = probe.normalizedUID.isEmpty ? nil : probe.normalizedUID
        let surfacedProbe = NFCManager.unknownReadableProbeResult(for: probe)

        let result = ScanResult(
            cardUID: uid,
            tagData: nil,
            format: nil,
            bambuProbe: surfacedProbe
        )
        session.alertMessage = "Unknown tag format detected. UID captured."
        session.invalidate()
        DispatchQueue.main.async { self.scanResult = result; self.isScanning = false }
    }

    // MARK: - NDEF Write (OpenSpool, OpenPrintTag, OpenTag3D)

    private func handleNDEFWrite(session: NFCNDEFReaderSession, tag: NFCNDEFTag, status: NFCNDEFStatus, capacity: Int) {
        guard status == .readWrite else {
            let reason = status == .readOnly ? "Tag is read-only (write-protected)." : "Tag is not writable."
            session.invalidate(errorMessage: reason)
            return
        }

        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }

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

        guard let mimeTypeData = mimeType.data(using: .utf8) else {
            session.invalidate(errorMessage: "Internal error: invalid MIME type.")
            return
        }

        let payload = NFCNDEFPayload(
            format: .media,
            type: mimeTypeData,
            identifier: Data(),
            payload: payloadData
        )

        var records = [payload]
        if format == .openPrintTag,
           let tagURL = dataToWrite.tagURL,
           !tagURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let urlPayload = makeOpenPrintTagURLPayload(from: tagURL) {
            records.insert(urlPayload, at: 0)
        }

        let message = NFCNDEFMessage(records: records)

        // Check tag capacity before writing
        let messageLength = message.length
        if capacity > 0 && messageLength > capacity {
            session.invalidate(errorMessage: "Tag is too small. Needs \(messageLength) bytes but tag only has \(capacity) bytes available.")
            return
        }

        tag.writeNDEF(message) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async { self.lastWriteSucceeded = true }
                session.alertMessage = "Tag written successfully! (\(format.displayName))"
                session.invalidate()
            }
        }
    }

    // MARK: - ACE Write (raw page writes)

    private func handleACEWrite(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }

        let pages = AnycubicACEPayload.encodePages(from: dataToWrite)
        guard !pages.isEmpty else {
            session.invalidate(errorMessage: "Failed to encode data for Anycubic ACE.")
            return
        }

        // Validate all page numbers fit in NTAG range (max 255)
        if let maxPage = pages.max(by: { $0.page < $1.page }), maxPage.page > 255 {
            session.invalidate(errorMessage: "Internal error: page number \(maxPage.page) exceeds tag limit.")
            return
        }

        // Write pages sequentially
        writeACEPages(session: session, tag: tag, pages: pages, index: 0)
    }

    private func writeACEPages(session: NFCTagReaderSession, tag: NFCMiFareTag, pages: [(page: Int, data: Data)], index: Int) {
        guard index < pages.count else {
            // All pages written successfully
            DispatchQueue.main.async { self.lastWriteSucceeded = true }
            session.alertMessage = "Tag written successfully! (Anycubic ACE)"
            session.invalidate()
            return
        }

        let page = pages[index]

        // NTAG WRITE command: 0xA2, page number, 4 bytes of data
        var writeCommand = Data([0xA2, UInt8(page.page)])
        writeCommand.append(page.data)

        tag.sendMiFareCommand(commandPacket: writeCommand) { data, error in
            if let error = error {
                session.invalidate(errorMessage: "Write failed at page \(page.page): \(error.localizedDescription)")
                return
            }
            // Continue to next page
            self.writeACEPages(session: session, tag: tag, pages: pages, index: index + 1)
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

            // Copy returned bytes into the buffer at the correct offset
            let startByte = page * AnycubicACEPayload.bytesPerPage
            let copyLen = min(data.count, 16)
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

    // MARK: - Helpers

    /// Extracts the MIME type string from an NDEF record.
    private func getMimeType(from record: NFCNDEFPayload) -> String? {
        if record.typeNameFormat == .media {
            return String(data: record.type, encoding: .utf8)
        }
        return nil
    }

    /// Extracts payload data from an NDEF record.
    private func getPayloadData(from record: NFCNDEFPayload) -> Data? {
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

    /// Maps a MIME type string to a `ScanResult.DetectedFormat`.
    private func detectedFormat(from mimeType: String?) -> ScanResult.DetectedFormat? {
        guard let mimeType = mimeType?.lowercased() else { return nil }
        if mimeType.contains("openspool")    { return .openSpool }
        if mimeType.contains("openprinttag") { return .openPrintTag }
        if mimeType.contains("opentag3d")    { return .openTag3D }
        return nil
    }

    static func surfacedProbeResult(for probe: BambuTagProbeResult, strongBambuEvidence: Bool) -> BambuTagProbeResult {
        let isLikelyBambu = strongBambuEvidence && probe.couldBeBambu
        let displayLabel = isLikelyBambu ? "Bambu Lab (encrypted)" : "Unknown or encrypted tag"
        return BambuTagProbeResult(
            couldBeBambu: probe.couldBeBambu,
            dataEncrypted: true,
            normalizedUID: probe.normalizedUID,
            displayLabel: displayLabel
        )
    }

    static func unknownReadableProbeResult(for probe: BambuTagProbeResult) -> BambuTagProbeResult {
        BambuTagProbeResult(
            couldBeBambu: false,
            dataEncrypted: false,
            normalizedUID: probe.normalizedUID,
            displayLabel: "Unknown tag format"
        )
    }

    private func makeOpenPrintTagURLPayload(from urlString: String) -> NFCNDEFPayload? {
        guard let encoded = urlString.data(using: .utf8),
              let typeData = Self.openPrintTagURLMIMEType.data(using: .utf8) else {
            return nil
        }

        return NFCNDEFPayload(
            format: .media,
            type: typeData,
            identifier: Data(),
            payload: encoded
        )
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
