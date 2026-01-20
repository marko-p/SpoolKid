//
//  NFCManager.swift
//  SpoolKid
//
//  Purpose: Core logic for interacting with CoreNFC.
//  Responsibilities:
//  - Managing the NFCNDEFReaderSession.
//  - Reading NDEF messages and decoding them into `FilamentTagData`.
//  - Encoding `FilamentTagData` into JSON and writing it to NDEF tags.
//  - Handling errors and session invalidation.
//
//  Important for Contributors:
//  - iOS requires a valid provisioning profile with "NFC Tag Reading" capability.
//  - NFC only works on physical devices, not the simulator.
//  - The `Info.plist` must contain `NFCReaderUsageDescription`.
//

import Foundation
import CoreNFC
import Combine

class NFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    
    @Published var alertMessage = ""
    @Published var isScanning = false
    @Published var scannedData: FilamentTagData?
    
    private var session: NFCNDEFReaderSession?
    private var tagDataToWrite: FilamentTagData?
    private var isWriting = false
    
    func startScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        
        isWriting = false
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your iPhone near the NFC tag to read."
        session?.begin()
        isScanning = true
    }
    
    func writeTag(data: FilamentTagData) {
        guard NFCNDEFReaderSession.readingAvailable else {
            alertMessage = "NFC is not available on this device."
            return
        }
        
        tagDataToWrite = data
        isWriting = true
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your iPhone near the NFC tag to write."
        session?.begin()
        isScanning = true
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
        // This method is not called when invalidateAfterFirstRead is true, didDetect tags is called instead if implemented,
        // but actually for NDEF reading/writing we usually use didDetect tags to connect.
        // However, for simple reading invalidateAfterFirstRead=true calls this one if we don't implement the other.
        // But for writing we MUST implement didDetect tags.
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
                    self.handleWrite(session: session, tag: tag, status: status)
                } else {
                    self.handleRead(session: session, tag: tag, status: status)
                }
            }
        }
    }
    
    private func handleWrite(session: NFCNDEFReaderSession, tag: NFCNDEFTag, status: NFCNDEFStatus) {
        guard status == .readWrite else {
            session.invalidate(errorMessage: "Tag is not writable.")
            return
        }
        
        guard let dataToWrite = tagDataToWrite else {
            session.invalidate(errorMessage: "No data to write.")
            return
        }
        
        guard let jsonData = TagFormatService.shared.encode(data: dataToWrite) else {
            session.invalidate(errorMessage: "Failed to encode data.")
            return
        }
            
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            session.invalidate(errorMessage: "Failed to stringify data.")
            return
        }
            
        // Create NDEF Payload
        // We use "application/json" mime type
        guard let payload = NFCNDEFPayload.wellKnownTypeJSONPayload(string: jsonString) else {
                session.invalidate(errorMessage: "Failed to create payload.")
                return
        }
        
        let message = NFCNDEFMessage(records: [payload])
        
        tag.writeNDEF(message) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
            } else {
                session.alertMessage = "Tag written successfully!"
                session.invalidate()
            }
        }
    }
    
    private func handleRead(session: NFCNDEFReaderSession, tag: NFCNDEFTag, status: NFCNDEFStatus) {
        if status == .notSupported {
            session.invalidate(errorMessage: "Tag not supported.")
            return
        }
        
        tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                return
            }
            
            guard let message = message else {
                session.invalidate(errorMessage: "No NDEF message found.")
                return
            }
            
            for record in message.records {
                // Check for JSON payload
                // Mime type should be application/json
                // Or it could be a text record with JSON content.
                
                // Let's try to decode from the payload
                if let data = self.getData(from: record) {
                    if let decodedData = TagFormatService.shared.decode(payload: data) {
                        DispatchQueue.main.async {
                            self.scannedData = decodedData
                        }
                        session.alertMessage = "Tag read successfully!"
                        session.invalidate()
                        return
                    } else {
                        print("Failed to decode data from record")
                    }
                }
            }
            
            session.invalidate(errorMessage: "No valid OpenSpool data found.")
        }
    }
    
    private func getData(from record: NFCNDEFPayload) -> Data? {
        // If it's a MIME type record
        if record.typeNameFormat == .media {
             return record.payload
        }
        // If it's a Well Known Text record, we might need to strip the language code
        // But standard says application/json should be used.
        // However, let's support text record just in case.
        if record.typeNameFormat == .nfcWellKnown && record.type == Data([0x54]) { // 'T'
            // Text record
            // Payload: Status Byte + Language Code + Text
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

extension NFCNDEFPayload {
    static func wellKnownTypeJSONPayload(string: String) -> NFCNDEFPayload? {
        guard let payloadData = string.data(using: .utf8) else { return nil }
        return NFCNDEFPayload(
            format: .media,
            type: "application/json".data(using: .utf8)!,
            identifier: Data(),
            payload: payloadData
        )
    }
}
