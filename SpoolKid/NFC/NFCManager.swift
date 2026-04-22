//
//  NFCManager.swift
//  SpoolKid
//
//  Purpose: Core logic for interacting with CoreNFC.
//  Responsibilities:
//  - Managing NFCNDEFReaderSession (for OpenSpool, OpenPrintTag, OpenTag3D).
//  - Managing NFCTagReaderSession (for Anycubic ACE raw page access).
//  - Reading NDEF messages and decoding them into `FilamentTagData`.
//  - Auto-detecting the tag format on read.
//  - Encoding `FilamentTagData` and writing to NFC tags in the selected format.
//  - Handling errors and session invalidation.
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
    
    @Published var alertMessage = ""
    @Published var isScanning = false
    @Published var scannedData: FilamentTagData?
    @Published var lastWriteSucceeded = false
    
    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?
    /// The data most recently passed to `writeTag(data:)`. Accessible for post-write actions.
    private(set) var tagDataToWrite: FilamentTagData?
    
    // Thread-safe access to mutable state shared between main thread and NFC delegate callbacks.
    private let stateQueue = DispatchQueue(label: "com.spoolkid.nfcmanager.state")
    private var _isWriting = false
    private var isWriting: Bool {
        get { stateQueue.sync { _isWriting } }
        set { stateQueue.sync { _isWriting = newValue } }
    }
    
    // MARK: - Public API
    
    func startScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        
        isWriting = false
        // Use NDEF session for reading — works for all NDEF-based formats
        // (OpenSpool, OpenPrintTag, OpenTag3D). Auto-detection uses MIME types.
        startNDEFSession(message: "Hold your iPhone near the NFC tag to read.")
    }
    
    /// Start a scan using raw tag session — needed for reading Anycubic ACE tags.
    /// Falls back to NDEF parsing if the tag isn't ACE.
    func startScanningRaw() {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        
        isWriting = false
        startTagSession(message: "Hold your iPhone near the NFC tag to read.")
    }
    
    func writeTag(data: FilamentTagData) {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        
        tagDataToWrite = data
        isWriting = true
        lastWriteSucceeded = false
        
        let format = TagFormatService.shared.currentFormat
        if format == .anycubicACE {
            // ACE requires raw page writes via NFCTagReaderSession
            startTagSession(message: "Hold your iPhone near the NFC tag to write (ACE format).")
        } else {
            // All other formats use NDEF
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
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
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
                
                if self.isWriting {
                    self.handleNDEFWrite(session: session, tag: tag, status: status, capacity: capacity)
                } else {
                    self.handleNDEFRead(session: session, tag: tag, status: status)
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
        
        // We need a MiFare tag for raw page access
        guard case .miFare(let miFareTag) = tag else {
            session.invalidate(errorMessage: "Tag is not compatible with this format. Expected NTAG/MIFARE Ultralight.")
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
                self.handleACEAutoDetectRead(session: session, tag: miFareTag)
            }
        }
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active, waiting for tag
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
        
        let format = TagFormatService.shared.currentFormat
        
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
        
        let message = NFCNDEFMessage(records: [payload])
        
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
    
    // MARK: - NDEF Read (auto-detect OpenSpool, OpenPrintTag, OpenTag3D)
    
    private func handleNDEFRead(session: NFCNDEFReaderSession, tag: NFCNDEFTag, status: NFCNDEFStatus) {
        if status == .notSupported {
            session.invalidate(errorMessage: "This tag does not support NDEF. Try 'Scan ACE Tag' for Anycubic ACE tags.")
            return
        }
        
        tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                return
            }
            
            guard let message = message else {
                session.invalidate(errorMessage: "No data found on this tag. It may be blank or use a non-NDEF format.")
                return
            }
            
            for record in message.records {
                let mimeType = self.getMimeType(from: record)
                
                if let data = self.getPayloadData(from: record) {
                    if let decodedData = TagFormatService.shared.decode(payload: data, mimeType: mimeType) {
                        DispatchQueue.main.async {
                            self.scannedData = decodedData
                        }
                        session.alertMessage = "Tag read successfully!"
                        session.invalidate()
                        return
                    }
                }
            }
            
            session.invalidate(errorMessage: "No recognized filament data on this tag. Supported formats: OpenSpool, OpenPrintTag, OpenTag3D.")
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
    
    // MARK: - ACE Read / Auto-Detect Read (raw tag session)
    
    /// Reads using raw tag session. First tries NDEF, then falls back to ACE raw page read.
    private func handleACEAutoDetectRead(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        // First, try to read NDEF from the tag using queryNDEF on the MiFare tag
        // MiFare tags that contain NDEF can be read via the NDEF interface
        
        // Try reading raw pages to check for ACE magic byte
        readACERawPages(session: session, tag: tag)
    }
    
    private func readACERawPages(session: NFCTagReaderSession, tag: NFCMiFareTag) {
        // Read pages 0-30 using NTAG READ command (returns 4 pages / 16 bytes per read)
        // Read starting at pages: 0, 4, 8, 12, 16, 20, 24, 28
        
        let readPages = [0, 4, 8, 12, 16, 20, 24, 28]
        // Use NSMutableData as a reference-type buffer to avoid inout in closures
        guard let buffer = NSMutableData(length: AnycubicACEPayload.totalBytes) else {
            session.invalidate(errorMessage: "Internal error: failed to allocate read buffer.")
            return
        }
        
        readACEPagesSequentially(session: session, tag: tag, readPages: readPages, index: 0, buffer: buffer) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                return
            }
            
            let bytes = [UInt8](buffer as Data)
            
            // Try ACE decode
            if let tagData = TagFormatService.shared.decodeAnycubicACE(pages: bytes) {
                DispatchQueue.main.async {
                    self.scannedData = tagData
                }
                session.alertMessage = "Tag read successfully! (Anycubic ACE)"
                session.invalidate()
                return
            }
            
            session.invalidate(errorMessage: "No valid Anycubic ACE data found on this tag.")
        }
    }
    
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
