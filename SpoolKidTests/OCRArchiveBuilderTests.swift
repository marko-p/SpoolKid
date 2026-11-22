import Testing
import Foundation
import CoreGraphics
@testable import SpoolKid

@MainActor struct OCRArchiveBuilderTests {

    private static func makeSampleCandidate() -> OCRParsedCandidate {
        OCRParsedCandidate(
            material: "PLA",
            subtype: "Matte",
            brand: "Bambu",
            filamentName: "PLA Matte Charcoal",
            colorHex: "2B2B2B",
            serialNumber: nil,
            diameterMM: 1.75,
            netWeightG: 1000,
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 45,
            maxBedTemp: 60,
            isBedTempInferred: true,
            wasNozzleExplicitlyLabeled: true,
            wasBedExplicitlyLabeled: false,
            confidenceByField: [
                .material: .high,
                .brand: .medium,
                .minBedTemp: .low,
                .minNozzleTemp: .high
            ],
            rawLines: ["PLA Matte", "Bambu", "190-220°C"],
            rawLineBoxes: [
                CGRect(x: 0.1, y: 0.9, width: 0.4, height: 0.05),
                CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.05),
                CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05),
            ]
        )
    }

    private static func makeSampleFinal() -> OCRArchiveWorkflow.Final {
        OCRArchiveWorkflow.Final(
            material: "PLA",
            subtype: "Matte",
            brand: "Bambu",
            filamentName: "PLA Matte Charcoal",
            colorHex: "2B2B2B",
            serialNumber: nil,
            diameterMM: 1.75,
            netWeightG: 1000,
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 60,
            maxBedTemp: 60
        )
    }

    @Test func makeArchiveReturnsDirectoryWithImageAndSingleWorkflowJSON() throws {
        let candidate = Self.makeSampleCandidate()
        let finalValues = Self.makeSampleFinal()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

        let workDir = try OCRArchiveBuilder().makeArchiveDirectory(
            candidate: candidate, final: finalValues, imageData: imageData
        )

        // A directory, not a zip: since 2026-09-06 the capture is kept by
        // DiagnosticCaptureStore and zipped only when the user shares it.
        #expect(FileManager.default.fileExists(atPath: workDir.path))
        #expect(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("label.jpg").path))
        #expect(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("workflow.json").path))
        // Telemetry is now folded into workflow.json — the separate trace.json is gone.
        #expect(!FileManager.default.fileExists(atPath: workDir.appendingPathComponent("trace.json").path))
    }

    @Test func workflowJSONDecodesWithExpectedValues() throws {
        let candidate = Self.makeSampleCandidate()
        let finalValues = Self.makeSampleFinal()

        let workDir = try OCRArchiveBuilder().makeArchiveDirectory(
            candidate: candidate, final: finalValues, imageData: nil
        )
        let workflowData = try Data(contentsOf: workDir.appendingPathComponent("workflow.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workflow = try decoder.decode(OCRArchiveWorkflow.self, from: workflowData)

        #expect(workflow.schemaVersion == 3)
        #expect(workflow.detected.material == "PLA")
        #expect(workflow.detected.minBedTemp == 45)
        #expect(workflow.final.minNozzleTemp == 200)
        #expect(workflow.final.minBedTemp == 60)
        // Geometry (schema v3) round-trips index-aligned with rawLines.
        #expect(workflow.rawLines.count == workflow.rawLineBoxes.count)
        #expect(workflow.rawLineBoxes.first == CGRect(x: 0.1, y: 0.9, width: 0.4, height: 0.05))
        // rawLines is non-empty, so the re-parse must have recorded provenance steps.
        #expect(!workflow.parseTrace.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workDir.appendingPathComponent("label.jpg").path))

        let bedCorrection = workflow.corrections.first { $0.field == "minBedTemp" }
        #expect(bedCorrection != nil)
        #expect(bedCorrection?.detected == "45")
        #expect(bedCorrection?.final == "60")
        #expect(bedCorrection?.detectedConfidence == .low)
    }

    @Test func parseTraceExplainsTempAndDiameterProvenance() throws {
        // Real Anycubic label OCR lines (from a captured archive). The trace must show *why*
        // nozzle temp and diameter got their values, not just the end state.
        let rawLines = [
            "ANYCUBIC", "PLA+", "Diameter", "1.75+0.02mm",
            "Printing Temp", "190-230°C", "Color", "Black", "Mat weight", "1 kg"
        ]
        let candidate = OCRFilamentParserService.parse(lines: rawLines)
        let finalValues = OCRArchiveWorkflow.Final(
            material: candidate.material, subtype: candidate.subtype, brand: candidate.brand,
            filamentName: candidate.filamentName, colorHex: candidate.colorHex,
            serialNumber: candidate.serialNumber, diameterMM: candidate.diameterMM,
            netWeightG: candidate.netWeightG, minNozzleTemp: candidate.minNozzleTemp,
            maxNozzleTemp: candidate.maxNozzleTemp, minBedTemp: candidate.minBedTemp,
            maxBedTemp: candidate.maxBedTemp
        )

        let workDir = try OCRArchiveBuilder().makeArchiveDirectory(
            candidate: candidate, final: finalValues, imageData: nil
        )
        let data = try Data(contentsOf: workDir.appendingPathComponent("workflow.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workflow = try decoder.decode(OCRArchiveWorkflow.self, from: data)

        let nozzleStep = workflow.parseTrace.first {
            $0.field == "nozzleTemp" && $0.decision.hasPrefix("labeledTemperature") && $0.outcome == "accepted"
        }
        #expect(nozzleStep?.value == "190-230")

        let diameterStep = workflow.parseTrace.first {
            $0.field == "diameterMM" && $0.outcome == "accepted"
        }
        #expect(diameterStep?.value == "1.75")
    }

    @Test func correctionsCaptureEditedFields() {
        let candidate = Self.makeSampleCandidate()
        let finalValues = Self.makeSampleFinal()

        let corrections = OCRArchiveBuilder.computeCorrections(candidate: candidate, final: finalValues)

        let fields = corrections.map(\.field)
        #expect(fields.contains("minNozzleTemp"))
        #expect(fields.contains("minBedTemp"))

        let nozzle = corrections.first { $0.field == "minNozzleTemp" }
        #expect(nozzle?.detected == "190")
        #expect(nozzle?.final == "200")
        #expect(nozzle?.detectedConfidence == .high)
    }

    @Test func correctionsEmptyWhenFinalMatchesDetected() {
        let candidate = OCRParsedCandidate(
            material: "PLA",
            brand: "Bambu",
            colorHex: "FFFFFF",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 60,
            maxBedTemp: 60,
            wasNozzleExplicitlyLabeled: true,
            wasBedExplicitlyLabeled: true,
            confidenceByField: [:],
            rawLines: []
        )
        let finalValues = OCRArchiveWorkflow.Final(
            material: "PLA",
            subtype: nil,
            brand: "Bambu",
            filamentName: nil,
            colorHex: "FFFFFF",
            serialNumber: nil,
            diameterMM: nil,
            netWeightG: nil,
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 60,
            maxBedTemp: 60
        )

        let corrections = OCRArchiveBuilder.computeCorrections(candidate: candidate, final: finalValues)
        #expect(corrections.isEmpty)
    }
}
