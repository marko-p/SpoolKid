import Foundation

struct SmartScanFastProfile: Sendable {
    var qrHighConfidenceThreshold: Double
    var ocrFallbackBoundarySeconds: TimeInterval

    static let `default` = SmartScanFastProfile(
        qrHighConfidenceThreshold: 0.90,
        ocrFallbackBoundarySeconds: 1.20
    )
}

struct SmartScanQRCodeCandidate: Sendable {
    let payload: String
    let confidence: Double
}

enum SmartScanDecision: Sendable {
    case wait
    case acceptQR(String)
    case acceptOCR(OCRParsedCandidate)
}

enum SmartScanArbitrationService {
    static func decide(
        qrCandidate: SmartScanQRCodeCandidate?,
        ocrCandidate: OCRParsedCandidate?,
        elapsed: TimeInterval,
        profile: SmartScanFastProfile = .default
    ) -> SmartScanDecision {
        if let qrCandidate,
           qrCandidate.confidence >= profile.qrHighConfidenceThreshold,
           isValidURLPayload(qrCandidate.payload)
            // Spoolman's `WEB+SPOOLMAN:` labels are not http(s) URLs.
            || BackendLabel.parse(qrCandidate.payload, spoolmanURL: "", filamanURL: "") != nil {
            return .acceptQR(qrCandidate.payload)
        }

        if elapsed >= profile.ocrFallbackBoundarySeconds,
           let ocrCandidate {
            return .acceptOCR(ocrCandidate)
        }

        return .wait
    }

    private static func isValidURLPayload(_ payload: String) -> Bool {
        guard let url = URL(string: payload),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return false
        }

        return true
    }
}
