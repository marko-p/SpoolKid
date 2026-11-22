//
//  FilamentOpacityTests.swift
//  SpoolKidTests
//
//  Pins the TD → alpha table in the 2026-11-07 filament opacity spec.
//

import Testing
import Foundation
@testable import SpoolKid

struct FilamentOpacityTests {
    @Test(arguments: [
        (0.5, 252), (1.5, 200), (3.0, 137), (5.0, 94), (10.0, 52), (20.0, 28), (100.0, 6)
    ])
    func alphaMatchesTheSpecTable(td: Double, alpha: Int) {
        #expect(FilamentOpacity.alpha(forTD: td) == alpha)
    }

    @Test func noTDIsOpaque() {
        #expect(FilamentOpacity.alpha(forTD: nil) == 255)
    }

    @Test(arguments: [0.0, -1.0, 0.04, 100.1, Double.nan, Double.infinity])
    func invalidTDIsOpaque(td: Double) {
        #expect(FilamentOpacity.alpha(forTD: td) == 255)
    }

    @Test(arguments: [(255, nil), (0, nil), (300, nil), (-1, nil), (94, 94), (1, 1), (254, 254)] as [(Int, Int?)])
    func statedAlpha(raw: Int, expected: Int?) {
        #expect(FilamentOpacity.stated(alpha: raw) == expected)
    }

    @Test func displayTextIsAPercentage() {
        #expect(FilamentOpacity.displayText(alpha: 140) == "Opacity 55%")
    }

    @Test func writesTheTDAlphaWhenOn() {
        #expect(FilamentOpacity.alphaToWrite(td: 5, carried: nil, format: .tigerTag, enabled: true) == 94)
    }

    @Test func tdBeatsACarriedAlpha() {
        #expect(FilamentOpacity.alphaToWrite(td: 5, carried: 10, format: .openSpool, enabled: true) == 94)
    }

    @Test func keepsACarriedAlphaWithoutTD() {
        #expect(FilamentOpacity.alphaToWrite(td: nil, carried: 140, format: .openSpool, enabled: true) == 140)
    }

    @Test func preferenceOffWritesOpaque() {
        #expect(FilamentOpacity.alphaToWrite(td: 5, carried: 140, format: .openSpool, enabled: false) == nil)
    }

    @Test(arguments: [TagFormat.anycubicACE, .elegoo])
    func formatsWithoutAlphaWriteNone(format: TagFormat) {
        #expect(FilamentOpacity.alphaToWrite(td: 5, carried: 140, format: format, enabled: true) == nil)
    }

    @Test func theFormOffersTheSwitchForAnyTD() {
        #expect(FilamentOpacity.offersWriteSwitch(td: 5, format: .openSpool))
        // Opaque in practice, but it has a TD.
        #expect(FilamentOpacity.offersWriteSwitch(td: 0.1, format: .openSpool))
    }

    @Test func theFormHidesTheSwitchWithoutATDOrAlpha() {
        #expect(!FilamentOpacity.offersWriteSwitch(td: nil, format: .openSpool))
        #expect(!FilamentOpacity.offersWriteSwitch(td: 0, format: .openSpool))
        #expect(!FilamentOpacity.offersWriteSwitch(td: 5, format: .elegoo))
    }

    @Test(arguments: [TagFormat.openSpool, .openPrintTag, .openTag3D, .tigerTag])
    func formatsWithAlphaCarryIt(format: TagFormat) {
        #expect(format.carriesAlpha)
    }

    // MARK: TD on the toolhead sheet

    @Test(arguments: [(94, 5.0), (137, 3.0), (52, 10.1), (254, 0.4), (6, 96.7)] as [(Int, Double)])
    func anAlphaGivesAnEstimatedTD(alpha: Int, td: Double) {
        #expect(FilamentOpacity.estimatedTD(alpha: alpha) == td)
    }

    @Test(arguments: [255, 0, 5, -1, 300])
    func anAlphaOutsideTheTDRangeGivesNone(alpha: Int) {
        #expect(FilamentOpacity.estimatedTD(alpha: alpha) == nil)
    }

    @Test func theLibrarysTDIsShownAsMeasured() {
        #expect(FilamentOpacity.toolheadText(alpha: 94, libraryTD: 3.2) == "TD 3.2 mm · Opacity 37%")
        #expect(FilamentOpacity.toolheadText(alpha: 255, libraryTD: 3.2) == "TD 3.2 mm")
    }

    @Test func withoutALibraryTDTheTDIsEstimated() {
        #expect(FilamentOpacity.toolheadText(alpha: 94, libraryTD: nil) == "TD ≈ 5.0 mm · Opacity 37%")
        #expect(FilamentOpacity.toolheadText(alpha: 94, libraryTD: 0) == "TD ≈ 5.0 mm · Opacity 37%")
    }

    @Test func noTDNoText() {
        #expect(FilamentOpacity.toolheadText(alpha: 255, libraryTD: nil) == nil)
        #expect(FilamentOpacity.toolheadText(alpha: 5, libraryTD: nil) == "Opacity 2%")
    }
}
