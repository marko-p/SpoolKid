import Testing
import CoreGraphics
@testable import SpoolKid

struct OCRLineOrdererTests {
    private func item(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.05)
        -> (text: String, box: CGRect) {
        (text, CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func emptyAndSinglePassThrough() {
        #expect(OCRLineOrderer.order([]) == [])
        #expect(OCRLineOrderer.order([item("only", x: 0.1, y: 0.5)]) == ["only"])
    }

    @Test func singleColumnReadsTopToBottom() {
        // One column, deliberately supplied bottom-up; output must be top-down (midY descending).
        let items = [item("bottom", x: 0.1, y: 0.1), item("top", x: 0.1, y: 0.9), item("mid", x: 0.1, y: 0.5)]
        #expect(OCRLineOrderer.order(items) == ["top", "mid", "bottom"])
    }

    @Test func twoColumnsReadColumnMajorNotRowMajor() {
        // Left column (x≈0.1) and right column (x≈0.6), supplied row-interleaved as Vision often
        // returns them. Correct reading order keeps each label with the value beneath it.
        let items = [
            item("Diameter",  x: 0.10, y: 0.80), item("Net Weight", x: 0.60, y: 0.80),
            item("1.75mm",    x: 0.10, y: 0.70), item("1 kg",       x: 0.60, y: 0.70),
        ]
        #expect(OCRLineOrderer.order(items) == ["Diameter", "1.75mm", "Net Weight", "1 kg"])
    }

    @Test func wideTitleAboveTwoColumnsStaysFirst() {
        let items = [
            item("ANYCUBIC",  x: 0.10, y: 0.95, w: 0.8),   // spans both columns, top
            item("Diameter",  x: 0.10, y: 0.80), item("Length", x: 0.60, y: 0.80),
            item("1.75mm",    x: 0.10, y: 0.70), item("330m",   x: 0.60, y: 0.70),
        ]
        let out = OCRLineOrderer.order(items)
        #expect(out.first == "ANYCUBIC")
        #expect(out == ["ANYCUBIC", "Diameter", "1.75mm", "Length", "330m"])
    }

    @Test func orderedItemsKeepsEachTextPairedWithItsBox() {
        let items = [
            item("Diameter", x: 0.10, y: 0.80), item("Net Weight", x: 0.60, y: 0.80),
            item("1.75mm",   x: 0.10, y: 0.70), item("1 kg",       x: 0.60, y: 0.70),
        ]
        let ordered = OCRLineOrderer.orderedItems(items)
        #expect(ordered.map(\.text) == ["Diameter", "1.75mm", "Net Weight", "1 kg"])
        // Each returned pair's box is the one originally supplied for that text.
        for pair in ordered {
            let original = items.first { $0.text == pair.text }
            #expect(pair.box == original?.box)
        }
    }
}
