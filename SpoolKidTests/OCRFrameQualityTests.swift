import Testing
@testable import SpoolKid

struct OCRFrameQualityTests {

    // MARK: - Core hint evaluation

    @Test func overExposedStats_returnsGlareHint() {
        let stats = OCRFrameQuality.Stats(glareFraction: 0.20, luminanceSpread: 0.50)
        #expect(OCRFrameQuality.evaluate(stats) == .glare)
    }

    @Test func lowSpreadStats_returnsContrastHint() {
        let stats = OCRFrameQuality.Stats(glareFraction: 0.00, luminanceSpread: 0.10)
        #expect(OCRFrameQuality.evaluate(stats) == .contrast)
    }

    @Test func normalStats_returnsNil() {
        let stats = OCRFrameQuality.Stats(glareFraction: 0.02, luminanceSpread: 0.50)
        #expect(OCRFrameQuality.evaluate(stats) == nil)
    }

    // MARK: - Threshold boundaries

    @Test func glareFractionBelowThreshold_noGlareHint() {
        let stats = OCRFrameQuality.Stats(
            glareFraction: OCRFrameQuality.glarePixelFraction - 0.001,
            luminanceSpread: 0.50
        )
        #expect(OCRFrameQuality.evaluate(stats) != .glare)
    }

    @Test func glareHintPrecedesContrastHint() {
        // Both conditions true — glare is checked first and wins.
        let stats = OCRFrameQuality.Stats(
            glareFraction: OCRFrameQuality.glarePixelFraction + 0.01,
            luminanceSpread: OCRFrameQuality.contrastMinSpread - 0.01
        )
        #expect(OCRFrameQuality.evaluate(stats) == .glare)
    }

    @Test func spreadAtMinimum_noContrastHint() {
        // Spread exactly at threshold (not below) → no hint.
        let stats = OCRFrameQuality.Stats(
            glareFraction: 0.00,
            luminanceSpread: OCRFrameQuality.contrastMinSpread
        )
        #expect(OCRFrameQuality.evaluate(stats) == nil)
    }
}
