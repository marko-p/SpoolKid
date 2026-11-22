import Foundation
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "OCRArchiveBuilder")

nonisolated struct OCRArchiveWorkflow: Codable, Sendable {
    let schemaVersion: Int
    let scanId: UUID
    let capturedAt: Date
    let appVersion: String
    let appBuild: String
    let detected: Detected
    let confidenceByField: [String: OCRFieldConfidence]
    let rawLines: [String]
    /// Per-line Vision bounding boxes (normalized, origin bottom-left), index-aligned with
    /// `rawLines` and in the same order they were fed to the parser. Geometry corpus for studying
    /// OCRLineOrderer offline. Added in schema v3; empty on archives where geometry wasn't captured.
    let rawLineBoxes: [CGRect]
    let `final`: Final
    let corrections: [Correction]
    /// Ordered decision provenance from a deterministic re-parse of `rawLines` (the highest-confidence
    /// frame). Explains how each field's value — or its absence — was reached. `detected` is the
    /// cross-frame consensus vote; in the common case the two agree, and this trace explains the
    /// per-frame parser logic that feeds the vote.
    let parseTrace: [OCRParseStep]
    /// App-wide workflow telemetry (`WorkflowTraceStore`) captured at archive time, folded in so the
    /// archive is a single JSON + image.
    let flowTrace: [WorkflowTraceEvent]

    nonisolated struct Detected: Codable, Sendable {
        let material: String?
        let subtype: String?
        let brand: String?
        let filamentName: String?
        let colorHex: String?
        let serialNumber: String?
        let diameterMM: Double?
        let netWeightG: Int?
        let minNozzleTemp: Int?
        let maxNozzleTemp: Int?
        let minBedTemp: Int?
        let maxBedTemp: Int?
        let isBedTempInferred: Bool
        let wasNozzleExplicitlyLabeled: Bool
        let wasBedExplicitlyLabeled: Bool
    }

    nonisolated struct Final: Codable, Sendable {
        let material: String?
        let subtype: String?
        let brand: String?
        let filamentName: String?
        let colorHex: String?
        let serialNumber: String?
        let diameterMM: Double?
        let netWeightG: Int?
        let minNozzleTemp: Int?
        let maxNozzleTemp: Int?
        let minBedTemp: Int?
        let maxBedTemp: Int?
    }

    nonisolated struct Correction: Codable, Sendable {
        let field: String
        let detected: String?
        let `final`: String?
        let detectedConfidence: OCRFieldConfidence
    }
}

struct OCRArchiveBuilder {
    /// Builds the capture directory — image plus one JSON — and returns it.
    ///
    /// Stops short of zipping: since 2026-09-06 a capture is kept by
    /// `DiagnosticCaptureStore` and zipped only when the user actually shares
    /// it, so the folder holds one copy of each capture rather than two.
    func makeArchiveDirectory(
        candidate: OCRParsedCandidate,
        final finalValues: OCRArchiveWorkflow.Final,
        imageData: Data?
    ) throws -> URL {
        let now = Date()
        let workDir = try DiagnosticBundle.makeWorkDirectory(kind: "ocr-scan", at: now)

        if let imageData {
            try imageData.write(to: workDir.appendingPathComponent("label.jpg"))
        }

        // Re-parse the stored rawLines once with a trace recorder attached. parse() is pure and
        // deterministic, so this reproduces the highest-confidence frame's decisions exactly.
        let traceRecorder = OCRParseTrace()
        _ = OCRFilamentParserService.parse(lines: candidate.rawLines, trace: traceRecorder)

        let workflow = OCRArchiveWorkflow(
            schemaVersion: 3,
            scanId: UUID(),
            capturedAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            detected: .init(from: candidate),
            confidenceByField: candidate.confidenceByField
                .reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            rawLines: candidate.rawLines,
            rawLineBoxes: candidate.rawLineBoxes,
            final: finalValues,
            corrections: Self.computeCorrections(candidate: candidate, final: finalValues),
            parseTrace: traceRecorder.steps,
            flowTrace: WorkflowTraceStore.shared.exportEvents()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(workflow).write(to: workDir.appendingPathComponent("workflow.json"))

        return workDir
    }

    static func computeCorrections(
        candidate: OCRParsedCandidate,
        final finalValues: OCRArchiveWorkflow.Final
    ) -> [OCRArchiveWorkflow.Correction] {
        var result: [OCRArchiveWorkflow.Correction] = []

        func normalize(_ s: String?) -> String? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t.lowercased()
        }
        func store(_ s: String?) -> String? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        func checkText(_ field: OCRParsedCandidate.Field, _ d: String?, _ f: String?) {
            if normalize(d) != normalize(f) {
                result.append(.init(field: field.rawValue, detected: store(d), final: store(f),
                                    detectedConfidence: candidate.confidenceByField[field] ?? .none))
            }
        }
        func checkInt(_ field: OCRParsedCandidate.Field, _ d: Int?, _ f: Int?) {
            if d != f {
                result.append(.init(field: field.rawValue, detected: d.map(String.init), final: f.map(String.init),
                                    detectedConfidence: candidate.confidenceByField[field] ?? .none))
            }
        }
        func checkDouble(_ field: OCRParsedCandidate.Field, _ d: Double?, _ f: Double?) {
            if d != f {
                result.append(.init(field: field.rawValue,
                                    detected: d.map { String(format: "%.2f", $0) },
                                    final: f.map { String(format: "%.2f", $0) },
                                    detectedConfidence: candidate.confidenceByField[field] ?? .none))
            }
        }

        checkText(.material, candidate.material, finalValues.material)
        checkText(.subtype, candidate.subtype, finalValues.subtype)
        checkText(.brand, candidate.brand, finalValues.brand)
        checkText(.filamentName, candidate.filamentName, finalValues.filamentName)
        checkText(.colorHex, candidate.colorHex, finalValues.colorHex)
        checkText(.serialNumber, candidate.serialNumber, finalValues.serialNumber)
        checkDouble(.diameterMM, candidate.diameterMM, finalValues.diameterMM)
        checkInt(.netWeightG, candidate.netWeightG, finalValues.netWeightG)
        checkInt(.minNozzleTemp, candidate.minNozzleTemp, finalValues.minNozzleTemp)
        checkInt(.maxNozzleTemp, candidate.maxNozzleTemp, finalValues.maxNozzleTemp)
        checkInt(.minBedTemp, candidate.minBedTemp, finalValues.minBedTemp)
        checkInt(.maxBedTemp, candidate.maxBedTemp, finalValues.maxBedTemp)

        return result
    }
}

private extension OCRArchiveWorkflow.Detected {
    init(from candidate: OCRParsedCandidate) {
        self.init(
            material: candidate.material,
            subtype: candidate.subtype,
            brand: candidate.brand,
            filamentName: candidate.filamentName,
            colorHex: candidate.colorHex,
            serialNumber: candidate.serialNumber,
            diameterMM: candidate.diameterMM,
            netWeightG: candidate.netWeightG,
            minNozzleTemp: candidate.minNozzleTemp,
            maxNozzleTemp: candidate.maxNozzleTemp,
            minBedTemp: candidate.minBedTemp,
            maxBedTemp: candidate.maxBedTemp,
            isBedTempInferred: candidate.isBedTempInferred,
            wasNozzleExplicitlyLabeled: candidate.wasNozzleExplicitlyLabeled,
            wasBedExplicitlyLabeled: candidate.wasBedExplicitlyLabeled
        )
    }
}
