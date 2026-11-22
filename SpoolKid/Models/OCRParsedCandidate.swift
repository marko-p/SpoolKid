import Foundation
import CoreGraphics

enum OCRFieldConfidence: String, Sendable, Codable {
    case high
    case medium
    case low
    case none
}

struct OCRParsedCandidate: Sendable, Identifiable {
    let id = UUID()
    
    enum Field: String, CaseIterable, Sendable {
        case material
        case subtype
        case brand
        case filamentName
        case colorHex
        case serialNumber
        case diameterMM
        case netWeightG
        case minNozzleTemp
        case maxNozzleTemp
        case minBedTemp
        case maxBedTemp
        case isBedTempInferred
    }

    var material: String?
    var subtype: String? = nil
    var brand: String?
    var filamentName: String? = nil
    var colorHex: String?
    var serialNumber: String? = nil
    var diameterMM: Double? = nil
    var netWeightG: Int? = nil
    var minNozzleTemp: Int?
    var maxNozzleTemp: Int?
    var minBedTemp: Int?
    var maxBedTemp: Int?
    var isBedTempInferred: Bool = false
    var wasNozzleExplicitlyLabeled: Bool = false
    var wasBedExplicitlyLabeled: Bool = false
    var confidenceByField: [Field: OCRFieldConfidence]
    var rawLines: [String]
    /// Per-line Vision bounding boxes (normalized, origin bottom-left), parallel to `rawLines` and
    /// in the same order they were fed to the parser. Capture metadata for the OCR archive — the
    /// parser ignores it. Empty when geometry wasn't captured (e.g. constructed in tests).
    var rawLineBoxes: [CGRect] = []
}

enum OCRReviewDestination: Sendable {
    case scanHub
    case retakeSmartScan
    case cancelled
}

enum OCRReviewOutcome: Sendable {
    case proceedToScanHub(ScanResult)
    case retakeSmartScan
    case cancel

    var destination: OCRReviewDestination {
        switch self {
        case .proceedToScanHub: return .scanHub
        case .retakeSmartScan: return .retakeSmartScan
        case .cancel: return .cancelled
        }
    }
}
