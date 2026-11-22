import Testing
import Foundation
@testable import SpoolKid

struct SpoolUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let en = Locale(identifier: "en_US")

    private func spool(_ id: Int = 1, filament: Filament = Filament(id: 1, name: "F", material: "PLA"),
                       remaining: Double? = nil, initial: Double? = nil, used: Double? = nil,
                       lastUsed: Date? = nil, archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: filament, lastUsed: lastUsed, remainingWeight: remaining,
              initialWeight: initial, usedWeight: used, archived: archived,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    // effectiveUsedWeight
    @Test func storedUsedWeightWins() { #expect(SpoolUsage.effectiveUsedWeight(of: spool(remaining: 864, initial: 1000, used: 136)) == 136) }
    @Test func usedIsDerivedFromStartingMinusRemaining() { #expect(SpoolUsage.effectiveUsedWeight(of: spool(remaining: 244, initial: 1000)) == 756) }
    @Test func zeroStoredUsedFallsBackToDerivation() {
        let s = spool(filament: Filament(id: 1, weight: 1000), remaining: 244, used: 0)
        #expect(SpoolUsage.effectiveUsedWeight(of: s) == 756)
    }
    @Test func derivedUsedNeverNegative() { #expect(SpoolUsage.effectiveUsedWeight(of: spool(remaining: 1200, initial: 1000)) == 0) }
    @Test func noRemainingAndNoUsedIsUnknown() { #expect(SpoolUsage.effectiveUsedWeight(of: spool(initial: 1000)) == nil) }
    @Test func noBasisIsUnknown() { #expect(SpoolUsage.effectiveUsedWeight(of: spool(remaining: 500)) == nil) }

    // text
    @Test func lastUsedReadsRelative() {
        #expect(SpoolUsage.text(for: spool(lastUsed: now.addingTimeInterval(-2 * 86_400)), now: now, locale: en) == "used 2 days ago")
    }
    @Test func underAMinuteIsJustNow() {
        #expect(SpoolUsage.text(for: spool(lastUsed: now.addingTimeInterval(-30)), now: now, locale: en) == "used just now")
    }
    @Test func aFutureDateIsJustNow() {
        #expect(SpoolUsage.text(for: spool(lastUsed: now.addingTimeInterval(120)), now: now, locale: en) == "used just now")
    }
    @Test func consumedWithoutDateIsUsed() { #expect(SpoolUsage.text(for: spool(remaining: 864, initial: 1000, used: 136), now: now) == "used") }
    @Test func weighedLibrarySpoolIsUsed() { #expect(SpoolUsage.text(for: spool(remaining: 244, initial: 1000), now: now) == "used") }
    @Test func fullSpoolIsUnused() { #expect(SpoolUsage.text(for: spool(remaining: 1000, initial: 1000, used: 0), now: now) == "unused") }
    @Test func emptyRecordIsUnused() { #expect(SpoolUsage.text(for: spool(), now: now) == "unused") }

    // weightText
    @Test(arguments: [(244.2, "244 g"), (818, "818 g"), (0, "0 g"), (-12, "0 g"),
                      (999.6, "1 kg"), (1000, "1 kg"), (2000, "2 kg"), (2800, "2.8 kg"), (4950.4, "5 kg")])
    func weightTextFormats(grams: Double, expected: String) { #expect(SpoolUsage.weightText(grams) == expected) }

    // spokenWeight: what VoiceOver reads, in words.
    @Test(arguments: [(244.2, "244 grams"), (1, "1 gram"), (0, "0 grams"), (-12, "0 grams"),
                      (999.6, "1 kilogram"), (1000, "1 kilogram"), (2000, "2 kilograms"),
                      (2800, "2.8 kilograms"), (1500, "1.5 kilograms"), (4950.4, "5 kilograms")])
    func spokenWeightReadsInWords(grams: Double, expected: String) { #expect(SpoolUsage.spokenWeight(grams) == expected) }

    // spoolCountText
    @Test func spoolCountPluralises() {
        #expect(SpoolUsage.spoolCountText(1) == "1 spool")
        #expect(SpoolUsage.spoolCountText(0) == "0 spools")
        #expect(SpoolUsage.spoolCountText(2) == "2 spools")
    }

    // stock
    @Test func stockCountsActiveSpoolsOnly() {
        let a = Filament(id: 1, name: "A"), b = Filament(id: 2, name: "B")
        let stock = SpoolUsage.stock(of: [
            spool(1, filament: a, remaining: 600, initial: 1000, used: 400),
            spool(2, filament: a, remaining: 1000, initial: 1000, used: 0),
            spool(3, filament: a, remaining: 100, initial: 1000, used: 900, archived: true),
            spool(4, filament: b, remaining: 0, initial: 1000, used: 1000, archived: true),
        ])
        #expect(stock[1] == FilamentStock(spoolCount: 2, remaining: 1600))
        #expect(stock[2] == FilamentStock(spoolCount: 0, remaining: nil))
        #expect(stock[3] == nil)
    }

    // A negative reading is an over-drawn spool, not a debt against its neighbours.
    @Test func stockClampsNegativeRemainingAtZero() {
        let a = Filament(id: 1, name: "A")
        let stock = SpoolUsage.stock(of: [
            spool(1, filament: a, remaining: 500, initial: 1000, used: 500),
            spool(2, filament: a, remaining: -80, initial: 1000, used: 1080),
        ])
        #expect(stock[1] == FilamentStock(spoolCount: 2, remaining: 500))
    }

    @Test func stockRemainingIsNilWhenNoWeightIsKnown() {
        let a = Filament(id: 1, name: "A")
        let stock = SpoolUsage.stock(of: [spool(1, filament: a)])
        #expect(stock[1] == FilamentStock(spoolCount: 1, remaining: nil))
    }
}
