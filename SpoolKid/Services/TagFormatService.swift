//
//  TagFormatService.swift
//  SpoolKid
//
//  Purpose: Handles encoding and decoding of different NFC tag formats.
//  Supports: OpenSpool, OpenPrintTag (Prusa), OpenTag3D, Anycubic ACE.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "TagFormatService")

enum TagFormat: String, CaseIterable, Identifiable {
    case openSpool = "openspool"
    case openPrintTag = "openprinttag"
    case openTag3D = "opentag3d"
    case anycubicACE = "anycubic_ace"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openSpool:    return "OpenSpool"
        case .openPrintTag: return "OpenPrintTag"
        case .openTag3D:    return "OpenTag3D"
        case .anycubicACE:  return "Anycubic ACE"
        }
    }
    
    /// Whether this format uses standard NDEF records (vs raw page writes)
    var isNDEF: Bool {
        switch self {
        case .openSpool, .openPrintTag, .openTag3D: return true
        case .anycubicACE: return false
        }
    }
    
    /// The NDEF MIME type used by this format, if applicable
    var mimeType: String? {
        switch self {
        case .openSpool:    return "application/json"
        case .openPrintTag: return "application/vnd.openprinttag"
        case .openTag3D:    return "application/opentag3d"
        case .anycubicACE:  return nil
        }
    }
}

final class TagFormatService {
    static let shared = TagFormatService()
    
    /// The format used for writing. Persisted via @AppStorage in the UI layer;
    /// read from UserDefaults here for use outside SwiftUI views.
    var currentFormat: TagFormat {
        get {
            let raw = UserDefaults.standard.string(forKey: AppConfig.nfcTagFormatKey) ?? TagFormat.openSpool.rawValue
            return TagFormat(rawValue: raw) ?? .openSpool
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppConfig.nfcTagFormatKey)
        }
    }
    
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    
    private init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        self.jsonEncoder = encoder
        self.jsonDecoder = JSONDecoder()
    }
    
    // MARK: - Encode (for writing)
    
    /// Encodes FilamentTagData for the currently selected write format.
    /// Returns nil for Anycubic ACE — that format uses raw page writes handled by NFCManager.
    func encode(data: FilamentTagData) -> Data? {
        return encode(data: data, format: currentFormat)
    }
    
    /// Encodes FilamentTagData for a specific format.
    func encode(data: FilamentTagData, format: TagFormat) -> Data? {
        let result: Data?
        switch format {
        case .openSpool:
            let payload = OpenSpoolPayload(from: data)
            result = serializeOpenSpoolManually(payload)
        case .openPrintTag:
            result = OpenPrintTagPayload.encode(from: data)
        case .openTag3D:
            result = OpenTag3DPayload.encode(from: data)
        case .anycubicACE:
            // ACE uses raw page writes, not a single Data blob for NDEF.
            // Encoding is handled directly in NFCManager via AnycubicACEPayload.
            result = nil
        }
        if result == nil && format != .anycubicACE {
            logger.error("Encoding failed for format \(format.rawValue, privacy: .public) with material=\(data.material, privacy: .public)")
        }
        return result
    }
    
    private func serializeOpenSpoolManually(_ payload: OpenSpoolPayload) -> Data? {
        func escape(_ string: String) -> String {
            if let data = try? jsonEncoder.encode(string), let s = String(data: data, encoding: .utf8) {
                return s
            }
            // Fallback: manually escape special characters to produce valid JSON
            logger.warning("JSON encoder failed for string, using manual escape: \(string, privacy: .public)")
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        }
        
        var parts: [String] = []
        
        // Field order per OpenSpool spec / printtag-web reference
        parts.append("\"protocol\":\"openspool\"")
        parts.append("\"version\":\"1.0\"")
        parts.append("\"type\":\(escape(payload.type))")
        if let subtype = payload.subtype, !subtype.isEmpty {
            parts.append("\"subtype\":\(escape(subtype))")
        }
        parts.append("\"color_hex\":\(escape(payload.colorHex.uppercased()))")
        parts.append("\"brand\":\(escape(payload.brand))")
        parts.append("\"min_temp\":\(escape(payload.minTemp))")
        parts.append("\"max_temp\":\(escape(payload.maxTemp))")
        parts.append("\"bed_min_temp\":\(escape(payload.bedMinTemp))")
        parts.append("\"bed_max_temp\":\(escape(payload.bedMaxTemp))")
        
        if let name = payload.name, !name.isEmpty {
            parts.append("\"name\":\(escape(name))")
        }
        
        if let id = payload.spoolId {
            parts.append("\"spool_id\":\(id)")
        }
        
        let json = "{\(parts.joined(separator: ","))}"
        
        return json.data(using: .utf8)
    }
    
    // MARK: - Decode (for reading — auto-detect format)
    
    /// Auto-detects format from an NDEF record's MIME type and payload data.
    /// Decoded data is clamped to reasonable temperature ranges to handle corrupted tags.
    func decode(payload: Data, mimeType: String? = nil) -> FilamentTagData? {
        // 1. If we have a MIME type hint, use it for direct dispatch
        if let mime = mimeType?.lowercased() {
            if mime == "application/vnd.openprinttag" {
                if let result = OpenPrintTagPayload.decode(from: payload) {
                    return result.clamped()
                }
                logger.warning("Failed to decode OpenPrintTag CBOR payload (\(payload.count) bytes)")
                return nil
            }
            if mime == "application/opentag3d" {
                if let result = OpenTag3DPayload.decode(from: payload) {
                    return result.clamped()
                }
                logger.warning("Failed to decode OpenTag3D binary payload (\(payload.count) bytes)")
                return nil
            }
        }
        
        // 2. Try OpenSpool (JSON with "protocol": "openspool")
        if let json = try? JSONSerialization.jsonObject(with: payload, options: []) as? [String: Any] {
            if let proto = json["protocol"] as? String, proto == "openspool" {
                if let openSpoolData = try? jsonDecoder.decode(OpenSpoolPayload.self, from: payload) {
                    return openSpoolData.toFilamentTagData().clamped()
                }
                logger.warning("OpenSpool JSON found but failed to decode as OpenSpoolPayload")
            }
            
            // Fallback: Try legacy FilamentTagData format (direct mapping)
            // This supports tags created with older versions of SpoolKid
            if let legacyData = try? jsonDecoder.decode(FilamentTagData.self, from: payload) {
                 return legacyData.clamped()
            }
        }
        
        // 3. If no MIME hint but binary data, try OpenPrintTag CBOR
        if mimeType == nil, let result = OpenPrintTagPayload.decode(from: payload) {
            return result.clamped()
        }
        
        // 4. Try OpenTag3D binary
        if mimeType == nil, let result = OpenTag3DPayload.decode(from: payload) {
            return result.clamped()
        }
        
        logger.info("No format matched for payload (\(payload.count) bytes, mimeType=\(mimeType ?? "nil", privacy: .public))")
        return nil
    }
    
    /// Decode raw NFC page data as Anycubic ACE format.
    /// Called by NFCManager after reading pages from a non-NDEF tag.
    func decodeAnycubicACE(pages: [UInt8]) -> FilamentTagData? {
        return AnycubicACEPayload.decode(from: pages)?.clamped()
    }
}
