import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagsCameraModeFlowTests {
    @Test func smartScannerActionRoutesValidQRToScanHubWebURLResult() {
        let action = TagsTabView.smartScannerAction(for: .qr("https://example.com/spool/42"))

        switch action {
        case .scanHub(let result):
            #expect(result.format == .webUrl)
            #expect(result.url?.absoluteString == "https://example.com/spool/42")
        default:
            Issue.record("Expected scan hub route for valid QR payload")
        }
    }

    @Test func smartScannerActionRoutesInvalidQRToInvalidQRCodeAlert() {
        let action = TagsTabView.smartScannerAction(for: .qr("not a url"))

        switch action {
        case .invalidQRCode:
            #expect(Bool(true))
        default:
            Issue.record("Expected invalid QR action for invalid QR payload")
        }
    }

    @Test func smartScannerActionRoutesOCRToScanHub() {
        let candidate = OCRParsedCandidate(confidenceByField: [:], rawLines: ["PLA"])
        let action = TagsTabView.smartScannerAction(for: .ocr(candidate))

        switch action {
        case .scanHub(let result):
            #expect(result.format == .ocr)
            #expect(result.ocrCandidate?.rawLines == candidate.rawLines)
        default:
            Issue.record("Expected scan hub route for OCR candidate output")
        }
    }

    @Test func smartScannerSelectionTraceEventUsesContractStepForQR() {
        let action = TagsTabView.smartScannerAction(for: .qr("https://example.com/spool/42"))
        let event = TagsTabView.smartScannerSelectionTraceEvent(for: action)

        #expect(event.step == SmartScanTelemetryContract.arbitrationSelected)
        #expect(event.details["type"] == "qr")
    }

    @Test func smartScannerSelectionTraceEventUsesContractStepForOCR() {
        let candidate = OCRParsedCandidate(confidenceByField: [:], rawLines: ["PLA", "Brand"])
        let action = TagsTabView.smartScannerAction(for: .ocr(candidate))
        let event = TagsTabView.smartScannerSelectionTraceEvent(for: action)

        #expect(event.step == SmartScanTelemetryContract.arbitrationSelected)
        #expect(event.details["type"] == "ocr")
        #expect(event.details["lineCount"] == "2")
    }

    @Test func smartScannerSelectionTraceEventUsesContractStepForInvalidQR() {
        let action = TagsTabView.smartScannerAction(for: .qr("not-a-url"))
        let event = TagsTabView.smartScannerSelectionTraceEvent(for: action)

        #expect(event.step == SmartScanTelemetryContract.arbitrationSelected)
        #expect(event.details["type"] == "qr-invalid")
    }

    @Test func smartScannerTraceStepAcceptsKnownStatusesAndFiltersUnknown() {
        #expect(TagsTabView.smartScannerTraceStep(forStatus: SmartScanTelemetryContract.started) == SmartScanTelemetryContract.started)
        #expect(TagsTabView.smartScannerTraceStep(forStatus: SmartScanTelemetryContract.qrCandidate) == SmartScanTelemetryContract.qrCandidate)
        #expect(TagsTabView.smartScannerTraceStep(forStatus: SmartScanTelemetryContract.ocrCandidate) == SmartScanTelemetryContract.ocrCandidate)
        #expect(TagsTabView.smartScannerTraceStep(forStatus: SmartScanTelemetryContract.noDecision) == SmartScanTelemetryContract.noDecision)
        #expect(TagsTabView.smartScannerTraceStep(forStatus: SmartScanTelemetryContract.cancel) == SmartScanTelemetryContract.cancel)
        #expect(TagsTabView.smartScannerTraceStep(forStatus: "QR detected, validating...") == nil)
    }

    @Test func smartScannerStatusContractValuesRemainAligned() {
        let expected: Set<String> = [
            SmartScanTelemetryContract.started,
            SmartScanTelemetryContract.qrCandidate,
            SmartScanTelemetryContract.ocrCandidate,
            SmartScanTelemetryContract.noDecision,
            SmartScanTelemetryContract.cancel
        ]

        #expect(Set(SmartScanTelemetryContract.statusSteps) == expected)
    }

    @Test func retakeSmartScanReviewDestinationMapsBackToSmartScannerRoute() {
        let route = TagsTabView.cameraSheetRoute(forReviewOutcome: .retakeSmartScan)

        #expect(route == .smartScanner)
    }

    @Test func cancelReviewOutcomeDoesNotReopenCameraRoute() {
        let route = TagsTabView.cameraSheetRoute(forReviewOutcome: .cancel)

        #expect(route == nil)
    }

    @Test func ocrReviewRetakeButtonUsesRetakeSmartScanOutcome() {
        let outcome = OCRReviewView.retakeOutcome

        switch outcome {
        case .retakeSmartScan:
            #expect(Bool(true))
        default:
            Issue.record("Expected OCR review retake control to emit retake smart scan outcome")
        }
    }
}
