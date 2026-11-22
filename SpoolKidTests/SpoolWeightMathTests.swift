import Testing
@testable import SpoolKid

struct SpoolWeightMathTests {

    // MARK: - parseWeight

    @Test func parseWeight_acceptsPlainNumber() {
        #expect(SpoolWeightMath.parseWeight("1238") == 1238)
    }

    @Test func parseWeight_acceptsCommaDecimal() {
        #expect(SpoolWeightMath.parseWeight("1,5") == 1.5)
    }

    @Test func parseWeight_trimsWhitespace() {
        #expect(SpoolWeightMath.parseWeight("  750  ") == 750)
    }

    @Test func parseWeight_rejectsEmpty() {
        #expect(SpoolWeightMath.parseWeight("   ") == nil)
    }

    @Test func parseWeight_rejectsNonNumeric() {
        #expect(SpoolWeightMath.parseWeight("abc") == nil)
    }

    // MARK: - formatWeight

    @Test func formatWeight_dropsTrailingZeroOnWholeNumber() {
        #expect(SpoolWeightMath.formatWeight(1000) == "1000")
    }

    @Test func formatWeight_keepsFraction() {
        #expect(SpoolWeightMath.formatWeight(1000.5) == "1000.5")
    }

    // A weight box is an unbounded `.decimalPad`: twenty digits parse to a
    // Double no `Int` can hold, and `Int(_:)` traps on it. These three inputs
    // each crashed the weigh session's log row before the guard.

    @Test func formatWeight_survivesAValueTooLargeForAnInt() {
        #expect(SpoolWeightMath.formatWeight(1e20) == "1e+20")
    }

    @Test func formatWeight_survivesInfinity() {
        #expect(SpoolWeightMath.formatWeight(.infinity) == "inf")
    }

    @Test func formatWeight_survivesNaN() {
        #expect(SpoolWeightMath.formatWeight(.nan) == "nan")
    }

    // MARK: - netFromGross

    @Test func netFromGross_subtractsTheCore() {
        #expect(SpoolWeightMath.netFromGross(gross: 1238, emptySpoolWeight: 238) == 1000)
    }

    @Test func netFromGross_canGoNegativeRatherThanClamping() {
        // A reading lighter than the stated core is a data problem the caller
        // must surface, not one this function may quietly hide by clamping.
        #expect(SpoolWeightMath.netFromGross(gross: 100, emptySpoolWeight: 238) == -138)
    }

    // MARK: - displayWeight (shown, never typed: rounded to 0.1 g)

    @Test func displayWeight_roundsToATenth() {
        #expect(SpoolWeightMath.displayWeight(812.34) == "812.3")
        #expect(SpoolWeightMath.displayWeight(812.35000001) == "812.4")
    }

    @Test func displayWeight_dropsTheZeroTenth() {
        #expect(SpoolWeightMath.displayWeight(759.96) == "760")
    }

    @Test func displayWeight_aTinyNegativeIsZero() {
        #expect(SpoolWeightMath.displayWeight(-0.04) == "0")
    }
}
