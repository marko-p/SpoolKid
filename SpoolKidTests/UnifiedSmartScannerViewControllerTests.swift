import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Testing
@testable import SpoolKid

struct UnifiedSmartScannerViewControllerTests {
    @Test func mapsQrDecisionToUnifiedQrOutput() {
        let decision = SmartScanDecision.acceptQR("https://spoolman.example/spool/100")

        let output = UnifiedSmartScannerViewController.mapDecisionToOutput(decision)

        guard case .qr(let payload)? = output else {
            Issue.record("Expected QR output from QR decision")
            return
        }

        #expect(payload == "https://spoolman.example/spool/100")
    }

    @Test func mapsOcrDecisionToUnifiedOcrOutput() {
        let candidate = OCRParsedCandidate(
            material: "PLA",
            brand: "Polymaker",
            colorHex: "FFFFFF",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            confidenceByField: [:],
            rawLines: ["PLA", "Polymaker"]
        )
        let decision = SmartScanDecision.acceptOCR(candidate)

        let output = UnifiedSmartScannerViewController.mapDecisionToOutput(decision)

        guard case .ocr(let selected)? = output else {
            Issue.record("Expected OCR output from OCR decision")
            return
        }

        #expect(selected.material == "PLA")
        #expect(selected.brand == "Polymaker")
    }

    @Test func mapsWaitDecisionToNilOutput() {
        let output = UnifiedSmartScannerViewController.mapDecisionToOutput(.wait)
        #expect(output == nil)
    }

    @Test func stateEmitsSingleOutputOnlyOnce() {
        var state = UnifiedSmartScannerDecisionState()
        let start = Date(timeIntervalSince1970: 100)
        state.begin(now: start)

        let first = state.applyQRCode(
            SmartScanQRCodeCandidate(payload: "https://spoolman.example/spool/1", confidence: 1.0),
            now: start,
            profile: .default
        )

        guard case .qr(let payload)? = first else {
            Issue.record("Expected first output to be QR")
            return
        }
        #expect(payload == "https://spoolman.example/spool/1")

        let second = state.applyOCRCandidate(
            OCRParsedCandidate(
                material: "PLA",
                brand: "Anycubic",
                colorHex: "FFFFFF",
                minNozzleTemp: 200,
                maxNozzleTemp: 220,
                minBedTemp: 55,
                maxBedTemp: 65,
                confidenceByField: [:],
                rawLines: ["PLA"]
            ),
            now: start.addingTimeInterval(5),
            profile: .default
        )

        #expect(second == nil)
    }

    @Test func cancelMarksStateTerminalAndPreventsOutput() {
        var state = UnifiedSmartScannerDecisionState()
        let start = Date(timeIntervalSince1970: 200)
        state.begin(now: start)

        let firstCancel = state.cancel()
        let secondCancel = state.cancel()

        #expect(firstCancel == true)
        #expect(secondCancel == false)

        let outputAfterCancel = state.applyQRCode(
            SmartScanQRCodeCandidate(payload: "https://spoolman.example/spool/2", confidence: 1.0),
            now: start,
            profile: .default
        )

        #expect(outputAfterCancel == nil)
    }

    @Test func callbackDispatcherRoutesStatusOutputAndCancelThroughScheduler() {
        var schedulerCallCount = 0
        let dispatcher = UnifiedSmartScannerCallbackDispatcher { work in
            schedulerCallCount += 1
            work()
        }

        var statusMessages: [String] = []
        var outputs: [UnifiedSmartScanOutput] = []
        var cancelCalls = 0

        dispatcher.emitStatus("Scanning", to: { statusMessages.append($0) })
        dispatcher.emitOutput(.qr("https://spoolman.example/spool/3"), to: { outputs.append($0) })
        dispatcher.emitCancel(to: { cancelCalls += 1 })

        #expect(schedulerCallCount == 3)
        #expect(statusMessages == ["Scanning"])
        #expect(cancelCalls == 1)

        guard outputs.count == 1 else {
            Issue.record("Expected one output callback")
            return
        }
        guard case .qr(let payload) = outputs[0] else {
            Issue.record("Expected QR output callback")
            return
        }
        #expect(payload == "https://spoolman.example/spool/3")
    }

    // MARK: - Diagnostics label image

    // The archive's label image is encoded once, from the last frame the
    // scanner processed, not on every frame. These pin that the image it gets
    // is the one it always got: long side capped at 1600 px, aspect kept.
    @Test func archiveJPEGCapsTheLongSideAt1600() throws {
        let jpeg = try #require(UnifiedSmartScannerViewController.archiveJPEG(
            from: try Self.pixelBuffer(width: 3200, height: 1800),
            context: CIContext()
        ))
        let size = try Self.pixelSize(of: jpeg)
        #expect(size.width == 1600)
        #expect(size.height == 900)
    }

    @Test func archiveJPEGKeepsASmallFrameAtFullSize() throws {
        let jpeg = try #require(UnifiedSmartScannerViewController.archiveJPEG(
            from: try Self.pixelBuffer(width: 1000, height: 800),
            context: CIContext()
        ))
        let size = try Self.pixelSize(of: jpeg)
        #expect(size.width == 1000)
        #expect(size.height == 800)
    }

    private static func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        #expect(status == kCVReturnSuccess)
        return try #require(buffer)
    }

    private static func pixelSize(of jpeg: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    // MARK: - Fallback button copy

    /// The button says what tapping it will give, so an unsettled reading is
    /// never accepted unseen.
    @Test func fallbackSubtitleNamesBrandAndFilament() {
        var candidate = Self.candidate(material: "PLA", brand: "Polymaker")
        #expect(UnifiedSmartScannerViewController.fallbackSubtitle(for: candidate) == "Polymaker · PLA")
        candidate.filamentName = "PLA Silk Gold"
        #expect(UnifiedSmartScannerViewController.fallbackSubtitle(for: candidate) == "Polymaker · PLA Silk Gold")
    }

    @Test func fallbackSubtitleIsNilWhenNothingNamesTheFilament() {
        #expect(UnifiedSmartScannerViewController.fallbackSubtitle(for: Self.candidate(material: nil, brand: nil)) == nil)
    }

    private static func candidate(material: String?, brand: String?) -> OCRParsedCandidate {
        OCRParsedCandidate(
            material: material,
            brand: brand,
            colorHex: nil,
            minNozzleTemp: nil,
            maxNozzleTemp: nil,
            minBedTemp: nil,
            maxBedTemp: nil,
            confidenceByField: [:],
            rawLines: []
        )
    }
}
