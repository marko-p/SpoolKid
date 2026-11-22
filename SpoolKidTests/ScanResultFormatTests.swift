import Testing
@testable import SpoolKid

@MainActor
struct ScanResultFormatTests {
    /// Overwrite Tag from Spool writes the tag in its own format.
    @Test func everyWritableFormatMapsToItself() {
        #expect(ScanResult.DetectedFormat.openSpool.tagFormat == .openSpool)
        #expect(ScanResult.DetectedFormat.openPrintTag.tagFormat == .openPrintTag)
        #expect(ScanResult.DetectedFormat.openTag3D.tagFormat == .openTag3D)
        #expect(ScanResult.DetectedFormat.anycubicACE.tagFormat == .anycubicACE)
        #expect(ScanResult.DetectedFormat.elegoo.tagFormat == .elegoo)
        #expect(ScanResult.DetectedFormat.tigerTag.tagFormat == .tigerTag)
        #expect(ScanResult.DetectedFormat.webUrl.tagFormat == nil)
        #expect(ScanResult.DetectedFormat.ocr.tagFormat == nil)
    }
}
