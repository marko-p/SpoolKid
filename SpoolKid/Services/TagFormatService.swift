//
//  TagFormatService.swift
//  SpoolKid
//
//  Purpose: Handles encoding and decoding of different NFC tag formats.
//

import Foundation

enum TagFormat {
    case openSpool
    // Future: case openPrintTag
}

struct TagFormatService {
    static let shared = TagFormatService()
    
    // Default format for now
    var currentFormat: TagFormat = .openSpool
    
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    
    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Or .withoutEscapingSlashes if needed
        self.jsonEncoder = encoder
        
        self.jsonDecoder = JSONDecoder()
    }
    
    func encode(data: FilamentTagData) -> Data? {
        switch currentFormat {
        case .openSpool:
            let payload = OpenSpoolPayload(from: data)
            return serializeOpenSpoolManually(payload)
        }
    }
    
    private func serializeOpenSpoolManually(_ payload: OpenSpoolPayload) -> Data? {
        func escape(_ string: String) -> String {
            if let data = try? jsonEncoder.encode(string), let s = String(data: data, encoding: .utf8) {
                return s
            }
            return "\"\(string)\""
        }
        
        var lines: [String] = []
        
        // Order as per https://printtag-web.pages.dev/ sample:
        // protocol, version, type, color_hex, brand, min_temp, max_temp, bed_min_temp, bed_max_temp
        
        lines.append("  \"protocol\": \"openspool\"")
        lines.append("  \"version\": \"1.0\"")
        lines.append("  \"type\": \(escape(payload.type))")
        lines.append("  \"color_hex\": \(escape(payload.colorHex))")
        lines.append("  \"brand\": \(escape(payload.brand))")
        lines.append("  \"min_temp\": \(escape(payload.minTemp))")
        lines.append("  \"max_temp\": \(escape(payload.maxTemp))")
        lines.append("  \"bed_min_temp\": \(escape(payload.bedMinTemp))")
        lines.append("  \"bed_max_temp\": \(escape(payload.bedMaxTemp))")
        
        // Optional properties
        // name is in OpenSpoolPayload but not in standard sample. We include it if present before spool_id.
        if let name = payload.name {
            lines.append("  \"name\": \(escape(name))")
        }
        
        // spool_id should be last
        if let id = payload.spoolId {
            lines.append("  \"spool_id\": \(id)")
        }
        
        let body = lines.joined(separator: ",\n")
        let json = "{\n\(body)\n}"
        
        return json.data(using: .utf8)
    }
    
    func decode(payload: Data) -> FilamentTagData? {
        // Try OpenSpool first (check for "protocol": "openspool")
        if let json = try? JSONSerialization.jsonObject(with: payload, options: []) as? [String: Any] {
            if let proto = json["protocol"] as? String, proto == "openspool" {
                if let openSpoolData = try? jsonDecoder.decode(OpenSpoolPayload.self, from: payload) {
                    return openSpoolData.toFilamentTagData()
                }
            }
            
            // Fallback: Try legacy FilamentTagData format (direct mapping)
            // This supports tags created with older versions of SpoolKid
            if let legacyData = try? jsonDecoder.decode(FilamentTagData.self, from: payload) {
                 return legacyData
            }
        }
        
        return nil
    }
}
