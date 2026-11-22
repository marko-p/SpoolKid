import Testing
@testable import SpoolKid

struct OCRSubtypeNormalizerTests {
    @Test func normalizesKnownSubtypeAliasesToCanonicalValues() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "  matte pla ") == "Matte")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "Silk finish") == "Silk")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "High Speed PLA") == "HF")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "SnapSpeed PLA") == "SnapSpeed")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "Snap Speed PLA") == "SnapSpeed")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "PVA support") == "Support")
    }

    @Test func normalizes95AAnd95AHFWithCorrectPrecedence() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "TPU 95A") == "95A")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "TPU 95A HF") == "95A HF")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "95a high flow") == "95A HF")
    }

    @Test func returnsHFWhenOnlyHFSignalExists() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "PLA-HF") == "HF")
    }

    @Test func handlesPunctuationAndSpacingAroundSignals() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "(HF)") == "HF")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "pva))") == "Support")
    }

    @Test func returnsNilForUnknownSubtype() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "Standard blend") == nil)
        #expect(OCRSubtypeNormalizer.normalize(rawText: nil) == nil)
    }

    // Regression (scanId 17A7C06E): "support" appearing in a contact email or a help-desk
    // phrase must NOT be read as the Support subtype. A genuine "PVA support" still is.
    @Test func ignoresSupportInEmailAndHelpDeskContext() {
        #expect(OCRSubtypeNormalizer.normalize(rawText: "please contact: support@3djayo.com") == nil)
        #expect(OCRSubtypeNormalizer.normalize(rawText: "For any questions or technical support") == nil)
        #expect(OCRSubtypeNormalizer.normalize(rawText: "PVA support") == "Support")
        #expect(OCRSubtypeNormalizer.normalize(rawText: "PLA+ Support") == "Support")
    }
}
