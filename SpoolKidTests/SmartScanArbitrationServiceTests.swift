import Foundation
import Testing
@testable import SpoolKid

struct SmartScanArbitrationServiceTests {
    @Test func validHighConfidenceQRIsSelectedEarly() {
        let decision = SmartScanArbitrationService.decide(
            qrCandidate: SmartScanQRCodeCandidate(
                payload: "https://spoolman.example/spool/42",
                confidence: 0.95
            ),
            ocrCandidate: nil,
            elapsed: 0.10
        )

        guard case .acceptQR(let selectedPayload) = decision else {
            Issue.record("Expected early high-confidence QR selection")
            return
        }

        #expect(selectedPayload == "https://spoolman.example/spool/42")
    }

    @Test func ocrIsSelectedAtFallbackBoundaryWhenQRMissing() {
        let ocrCandidate = OCRParsedCandidate(
            material: "PLA",
            brand: "Polymaker",
            colorHex: "112233",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            confidenceByField: [:],
            rawLines: ["PLA", "Polymaker"]
        )

        let profile = SmartScanFastProfile(
            qrHighConfidenceThreshold: 0.90,
            ocrFallbackBoundarySeconds: 1.20
        )

        let decision = SmartScanArbitrationService.decide(
            qrCandidate: nil,
            ocrCandidate: ocrCandidate,
            elapsed: 1.20,
            profile: profile
        )

        guard case .acceptOCR(let selected) = decision else {
            Issue.record("Expected OCR selection at fallback boundary")
            return
        }

        #expect(selected.material == "PLA")
        #expect(selected.brand == "Polymaker")
    }

    @Test func weakQROcrAtBoundarySelectsOCR() {
        let ocrCandidate = OCRParsedCandidate(
            material: "PETG",
            brand: "Prusament",
            colorHex: "445566",
            minNozzleTemp: 230,
            maxNozzleTemp: 250,
            minBedTemp: 70,
            maxBedTemp: 85,
            confidenceByField: [:],
            rawLines: ["PETG", "Prusament"]
        )

        let decision = SmartScanArbitrationService.decide(
            qrCandidate: SmartScanQRCodeCandidate(
                payload: "https://spoolman.example/spool/21",
                confidence: 0.30
            ),
            ocrCandidate: ocrCandidate,
            elapsed: 1.20
        )

        guard case .acceptOCR(let selected) = decision else {
            Issue.record("Expected OCR selection when QR is weak at boundary")
            return
        }

        #expect(selected.material == "PETG")
        #expect(selected.brand == "Prusament")
    }

    @Test func invalidHighConfidenceQROcrAtBoundarySelectsOCR() {
        let ocrCandidate = OCRParsedCandidate(
            material: "ABS",
            brand: "eSUN",
            colorHex: "000000",
            minNozzleTemp: 240,
            maxNozzleTemp: 260,
            minBedTemp: 90,
            maxBedTemp: 110,
            confidenceByField: [:],
            rawLines: ["ABS", "eSUN"]
        )

        let decision = SmartScanArbitrationService.decide(
            qrCandidate: SmartScanQRCodeCandidate(
                payload: "not-a-url",
                confidence: 0.99
            ),
            ocrCandidate: ocrCandidate,
            elapsed: 1.20
        )

        guard case .acceptOCR(let selected) = decision else {
            Issue.record("Expected OCR selection when QR is invalid at boundary")
            return
        }

        #expect(selected.material == "ABS")
        #expect(selected.brand == "eSUN")
    }

    @Test func ocrJustBelowBoundaryWaits() {
        let ocrCandidate = OCRParsedCandidate(
            material: "PLA",
            brand: "Anycubic",
            colorHex: "FFFFFF",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            confidenceByField: [:],
            rawLines: ["PLA", "Anycubic"]
        )

        let decision = SmartScanArbitrationService.decide(
            qrCandidate: nil,
            ocrCandidate: ocrCandidate,
            elapsed: 1.19
        )

        guard case .wait = decision else {
            Issue.record("Expected wait when OCR is just below fallback boundary")
            return
        }
    }

    @Test func noQrNoOcrWaits() {
        let decision = SmartScanArbitrationService.decide(
            qrCandidate: nil,
            ocrCandidate: nil,
            elapsed: 5.0
        )

        guard case .wait = decision else {
            Issue.record("Expected wait when no QR and no OCR are available")
            return
        }
    }

    @Test func invalidHighConfidenceQRBeforeBoundaryWaits() {
        let ocrCandidate = OCRParsedCandidate(
            material: "ASA",
            brand: "Polymaker",
            colorHex: "222222",
            minNozzleTemp: 250,
            maxNozzleTemp: 270,
            minBedTemp: 90,
            maxBedTemp: 110,
            confidenceByField: [:],
            rawLines: ["ASA", "Polymaker"]
        )

        let decision = SmartScanArbitrationService.decide(
            qrCandidate: SmartScanQRCodeCandidate(
                payload: "ftp://example.com/spool/11",
                confidence: 0.95
            ),
            ocrCandidate: ocrCandidate,
            elapsed: 0.50
        )

        guard case .wait = decision else {
            Issue.record("Expected wait for invalid QR before fallback boundary")
            return
        }
    }
}
