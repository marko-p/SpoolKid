//
//  ColorFilterServiceTests.swift
//  SpoolKidTests
//
//  Tests for the color filter: harmony derivation, matching, grouping,
//  availability islands, and map position math.
//

import Testing
import Foundation
@testable import SpoolKid

struct ColorFilterServiceTests {

    // MARK: - ColorHarmony model

    @Test func harmonyHasNineCases() {
        #expect(ColorHarmony.allCases.count == 9)
    }

    @Test func hueBandModes() {
        #expect(ColorHarmony.shades.isHueBand)
        #expect(ColorHarmony.monochromatic.isHueBand)
        #expect(!ColorHarmony.single.isHueBand)
        #expect(!ColorHarmony.complementary.isHueBand)
    }

    @Test func chromaticAnchorRequirement() {
        #expect(ColorHarmony.complementary.requiresChromaticAnchor)
        #expect(ColorHarmony.square.requiresChromaticAnchor)
        #expect(!ColorHarmony.single.requiresChromaticAnchor)
        #expect(!ColorHarmony.shades.requiresChromaticAnchor)
        #expect(!ColorHarmony.monochromatic.requiresChromaticAnchor)
    }

    // MARK: - Harmony targets

    private func targetHexes(_ harmony: ColorHarmony, anchor: String = "FF0000") -> [String] {
        ColorFilterService.targets(for: ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 18, harmony: harmony)).map(\.hex)
    }

    @Test func singleTargetsAnchorOnly() {
        let targets = ColorFilterService.targets(for: ColorFilterSpec(anchorHex: "#ff0000", toleranceDeltaE: 18, harmony: .single))
        #expect(targets.map(\.hex) == ["FF0000"])
        #expect(targets.map(\.role) == ["Matches"])
    }

    @Test func complementaryTargets() {
        let targets = ColorFilterService.targets(for: ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 18, harmony: .complementary))
        #expect(targets.map(\.hex) == ["FF0000", "00FFFF"])
        #expect(targets.map(\.role) == ["Anchor", "Complement"])
    }

    @Test func analogousTargets() {
        #expect(targetHexes(.analogous) == ["FF0000", "FF0080", "FF8000"])
    }

    @Test func splitComplementaryTargets() {
        #expect(targetHexes(.splitComplementary) == ["FF0000", "00FF80", "0080FF"])
    }

    @Test func triadTargets() {
        #expect(targetHexes(.triad) == ["FF0000", "00FF00", "0000FF"])
    }

    @Test func squareTargets() {
        #expect(targetHexes(.square) == ["FF0000", "80FF00", "00FFFF", "8000FF"])
    }

    @Test func compoundTargets() {
        #expect(targetHexes(.compound) == ["FF0000", "FF8000", "00FFFF", "0080FF"])
    }

    @Test func hueBandModesReturnAnchorOnlyForDrawing() {
        #expect(targetHexes(.shades) == ["FF0000"])
        #expect(targetHexes(.monochromatic) == ["FF0000"])
    }

    @Test func rotationWrapsPast360() {
        // Hue tolerance, not exact hex: the anchor round-trips through 8-bit
        // RGB, and 350°+30° lands the blue channel on an exact .5 rounding
        // boundary — byte-exact equality is numerically fragile there.
        let anchor = ColorMatching.hex(h: 350, s: 1, l: 0.5)
        let targets = ColorFilterService.targets(for: ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 18, harmony: .analogous))
        let rotated = ColorMatching.hsl(from: targets[2].hex)!
        #expect(ColorFilterService.hueDistance(rotated.h, 20) < 2)
    }

    @Test func invalidAnchorYieldsNoTargets() {
        #expect(targetHexes(.complementary, anchor: "zzz").isEmpty)
    }

    // MARK: - Achromatic detection + hue distance

    @Test func achromaticDetection() {
        #expect(ColorFilterService.isAchromatic("808080"))
        #expect(ColorFilterService.isAchromatic("FFFFFF"))
        #expect(!ColorFilterService.isAchromatic("1D9E75"))
        #expect(!ColorFilterService.isAchromatic("not-a-hex"))
    }

    @Test func hueDistanceIsCircular() {
        #expect(ColorFilterService.hueDistance(350, 10) == 20)
        #expect(ColorFilterService.hueDistance(10, 350) == 20)
        #expect(ColorFilterService.hueDistance(0, 180) == 180)
        #expect(ColorFilterService.hueDistance(90, 90) == 0)
    }

    // MARK: - Matching + grouping

    private func makeSpool(id: Int, colorHex: String? = nil, multi: String? = nil) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id * 10, name: "F\(id)", material: "PLA", colorHex: colorHex, multiColorHexes: multi),
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func swatchesCombineMainAndMultiDropInvalid() {
        let spool = makeSpool(id: 1, colorHex: "#1d9e75", multi: "C62828, zzz ,0000FF")
        #expect(ColorFilterService.swatches(of: spool) == ["1D9E75", "C62828", "0000FF"])
    }

    @Test func swatchesEmptyForColorlessSpool() {
        #expect(ColorFilterService.swatches(of: makeSpool(id: 1)).isEmpty)
    }

    @Test func exactColorMatchesSingle() {
        let spec = ColorFilterSpec(anchorHex: "1D9E75", toleranceDeltaE: 5, harmony: .single)
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 1, colorHex: "1D9E75"), spec: spec) == "Matches")
    }

    @Test func distantColorDoesNotMatchAtTightTolerance() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 10, harmony: .single)
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 1, colorHex: "00FF00"), spec: spec) == nil)
    }

    @Test func geometryMatchesInsideCircleRegardlessOfSaturation() {
        // Muted and vivid at the same hue/lightness share a map position.
        let anchor = ColorMatching.hex(h: 160, s: 1, l: 0.5)
        let spec = ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 10, harmony: .single)
        let muted = makeSpool(id: 1, colorHex: ColorMatching.hex(h: 160, s: 0.3, l: 0.5))
        #expect(ColorFilterService.matchRole(spool: muted, spec: spec) == "Matches")
    }

    @Test func circleBoundaryInUnitSpace() {
        // r = 0.10; hue offset 30° → dx = 30/360 ≈ 0.0833 (inside);
        // hue offset 45° → dx = 0.125 (outside).
        let anchor = ColorMatching.hex(h: 100, s: 1, l: 0.5)
        let spec = ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 10, harmony: .single)
        let inside = makeSpool(id: 1, colorHex: ColorMatching.hex(h: 130, s: 1, l: 0.5))
        let outside = makeSpool(id: 2, colorHex: ColorMatching.hex(h: 145, s: 1, l: 0.5))
        #expect(ColorFilterService.matchRole(spool: inside, spec: spec) == "Matches")
        #expect(ColorFilterService.matchRole(spool: outside, spec: spec) == nil)
    }

    @Test func harmonyUnionMatchesTargetCircleOnly() {
        // Swatch near the complement, far from the anchor.
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 10, harmony: .complementary)
        let nearComplement = makeSpool(id: 1, colorHex: ColorMatching.hex(h: 195, s: 1, l: 0.5))
        #expect(ColorFilterService.matchRole(spool: nearComplement, spec: spec) == "Complement")
    }

    @Test func unitDistanceWrapsHueSeam() {
        let a = ColorFilterService.unitPoint(forHex: ColorMatching.hex(h: 350, s: 1, l: 0.5))!
        let b = ColorFilterService.unitPoint(forHex: ColorMatching.hex(h: 10, s: 1, l: 0.5))!
        #expect(abs(ColorFilterService.unitDistance(a, b) - 20.0 / 360.0) < 0.005)
    }

    @Test func unitRadiusAndAspect() {
        #expect(ColorFilterService.unitRadius(tolerance: 18) == 0.18)
        #expect(ColorFilterService.mapAspectHeight == 0.5)
        #expect(ColorFilterService.unitPoint(forHex: "808080") == nil)
    }

    @Test func achromaticAnchorMatchesStripInterval() {
        let spec = ColorFilterSpec(anchorHex: "808080", toleranceDeltaE: 10, harmony: .single)
        let near = makeSpool(id: 1, colorHex: "6A6A6A")
        let far = makeSpool(id: 2, colorHex: "F5F5F5")
        let chromatic = makeSpool(id: 3, colorHex: "1D9E75")
        #expect(ColorFilterService.matchRole(spool: near, spec: spec) == "Matches")
        #expect(ColorFilterService.matchRole(spool: far, spec: spec) == nil)
        #expect(ColorFilterService.matchRole(spool: chromatic, spec: spec) == nil)
    }

    @Test func shadesAcceptsDarkerAnySaturation() {
        let anchor = ColorMatching.hex(h: 160, s: 0.7, l: 0.5)
        let spec = ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 18, harmony: .shades)
        let darker = makeSpool(id: 1, colorHex: ColorMatching.hex(h: 160, s: 0.7, l: 0.3))
        let lighter = makeSpool(id: 2, colorHex: ColorMatching.hex(h: 160, s: 0.7, l: 0.8))
        let desaturatedDarker = makeSpool(id: 3, colorHex: ColorMatching.hex(h: 160, s: 0.2, l: 0.3))
        #expect(ColorFilterService.matchRole(spool: darker, spec: spec) == "Darker")
        #expect(ColorFilterService.matchRole(spool: lighter, spec: spec) == nil)
        #expect(ColorFilterService.matchRole(spool: desaturatedDarker, spec: spec) == "Darker")
    }

    @Test func multiColorSwatchMatchesAnySide() {
        let spec = ColorFilterSpec(anchorHex: "0000FF", toleranceDeltaE: 10, harmony: .single)
        let dual = makeSpool(id: 1, colorHex: "FF0000", multi: "0000FF")
        #expect(ColorFilterService.matchRole(spool: dual, spec: spec) == "Matches")
    }

    @Test func complementAssignsClosestRole() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 15, harmony: .complementary)
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 1, colorHex: "00FFFF"), spec: spec) == "Complement")
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 2, colorHex: "FF0000"), spec: spec) == "Anchor")
    }

    @Test func groupedMatchesOrdersByRoleAndSkipsEmpty() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 15, harmony: .complementary)
        let spools = [
            makeSpool(id: 1, colorHex: "00FFFF"),
            makeSpool(id: 2, colorHex: "FF0000"),
            makeSpool(id: 3, colorHex: "888888"),
            makeSpool(id: 4)
        ]
        let groups = ColorFilterService.groupedMatches(spools, spec: spec)
        #expect(groups.map(\.role) == ["Anchor", "Complement"])
        #expect(groups[0].spools.map(\.id) == [2])
        #expect(groups[1].spools.map(\.id) == [1])
        #expect(groups[1].swatchHex == "00FFFF")
    }

    // MARK: - Hue-band modes

    @Test func monochromaticBucketsByLightness() {
        let anchor = ColorMatching.hex(h: 160, s: 0.7, l: 0.4)
        let spec = ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 18, harmony: .monochromatic)
        let lighter = makeSpool(id: 1, colorHex: ColorMatching.hex(h: 160, s: 0.3, l: 0.7))
        let darker = makeSpool(id: 2, colorHex: ColorMatching.hex(h: 165, s: 0.9, l: 0.2))
        let same = makeSpool(id: 3, colorHex: ColorMatching.hex(h: 158, s: 0.7, l: 0.42))
        let otherHue = makeSpool(id: 4, colorHex: ColorMatching.hex(h: 220, s: 0.7, l: 0.4))
        #expect(ColorFilterService.matchRole(spool: lighter, spec: spec) == "Lighter")
        #expect(ColorFilterService.matchRole(spool: darker, spec: spec) == "Darker")
        #expect(ColorFilterService.matchRole(spool: same, spec: spec) == "Anchor")
        #expect(ColorFilterService.matchRole(spool: otherHue, spec: spec) == nil)
    }

    @Test func hueBandExcludesAchromaticSwatchesForChromaticAnchor() {
        let spec = ColorFilterSpec(anchorHex: "1D9E75", toleranceDeltaE: 35, harmony: .monochromatic)
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 1, colorHex: "808080"), spec: spec) == nil)
    }

    @Test func achromaticAnchorMatchesGreysOnly() {
        let spec = ColorFilterSpec(anchorHex: "808080", toleranceDeltaE: 18, harmony: .monochromatic)
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 1, colorHex: "F0F0F0"), spec: spec) == "Lighter")
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 2, colorHex: "202020"), spec: spec) == "Darker")
        #expect(ColorFilterService.matchRole(spool: makeSpool(id: 3, colorHex: "1D9E75"), spec: spec) == nil)
    }

    @Test func hueBandRoleOrderProvidesHeaderSwatches() {
        // Component tolerances, not exact hex: the anchor round-trips through
        // 8-bit RGB, so recovered hue/sat can shift the bucket hex by a byte.
        let anchor = ColorMatching.hex(h: 160, s: 0.7, l: 0.4)
        let spec = ColorFilterSpec(anchorHex: anchor, toleranceDeltaE: 18, harmony: .monochromatic)
        let order = ColorFilterService.roleOrder(for: spec)
        #expect(order.map(\.role) == ["Lighter", "Anchor", "Darker"])
        #expect(order[1].hex == anchor)
        let lighter = ColorMatching.hsl(from: order[0].hex)!
        let darker = ColorMatching.hsl(from: order[2].hex)!
        #expect(abs(lighter.l - 0.6) < 0.02)
        #expect(abs(darker.l - 0.2) < 0.02)
        #expect(ColorFilterService.hueDistance(lighter.h, 160) < 2)
    }

    // MARK: - Summary + tolerance label

    @Test func matchSummaryFormats() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 15, harmony: .complementary)
        let groups = ColorFilterService.groupedMatches(
            [makeSpool(id: 1, colorHex: "FF0000"), makeSpool(id: 2, colorHex: "FF0000"), makeSpool(id: 3, colorHex: "00FFFF")],
            spec: spec
        )
        #expect(ColorFilterService.matchSummary(groups: groups) == "3 spools match · 2 anchor, 1 complement")
        #expect(ColorFilterService.matchSummary(groups: []) == "No spools match")
    }

    @Test func toleranceLabelSwitchesUnitByMode() {
        #expect(ColorFilterService.toleranceLabel(harmony: .single, tolerance: 18) == "18 %")
        #expect(ColorFilterService.toleranceLabel(harmony: .shades, tolerance: 18) == "± 18°")
    }

    // MARK: - Islands

    @Test func islandsDedupeAndCount() {
        let spools = [
            makeSpool(id: 1, colorHex: "1D9E75"),
            makeSpool(id: 2, colorHex: "#1d9e75"),
            makeSpool(id: 3, colorHex: "C62828"),
            makeSpool(id: 4, colorHex: "808080"),
            makeSpool(id: 5)
        ]
        let islands = ColorFilterService.islands(for: spools)
        #expect(islands.count == 3)
        let teal = islands.first { $0.hex == "1D9E75" }
        #expect(teal?.spoolCount == 2)
        #expect(teal?.hue != nil)
        let grey = islands.first { $0.hex == "808080" }
        #expect(grey?.hue == nil)
        #expect(abs(grey!.lightness - 0.502) < 0.001)
    }

    // MARK: - Map math

    @Test func mapPointHexRoundTrip() {
        let size = CGSize(width: 300, height: 180)
        let point = CGPoint(x: 150, y: 45)
        let hex = ColorFilterService.hex(atMapPoint: point, in: size)
        let back = ColorFilterService.mapPoint(forHex: hex, in: size)
        #expect(abs(back!.x - point.x) < 2)
        #expect(abs(back!.y - point.y) < 2)
    }

    @Test func mapPointNilForAchromatic() {
        #expect(ColorFilterService.mapPoint(forHex: "808080", in: CGSize(width: 300, height: 180)) == nil)
    }

    @Test func mapTapClampsToBounds() {
        let size = CGSize(width: 300, height: 180)
        #expect(ColorFilterService.hex(atMapPoint: CGPoint(x: -10, y: -10), in: size) == "FFFFFF")
        #expect(ColorFilterService.hex(atMapPoint: CGPoint(x: 10, y: 500), in: size) == "000000")
    }

    @Test func stripMapping() {
        #expect(ColorFilterService.hex(atStripFraction: 0) == "FFFFFF")
        #expect(ColorFilterService.hex(atStripFraction: 1) == "000000")
        #expect(ColorFilterService.stripX(forLightness: 1, width: 200) == 0)
        #expect(ColorFilterService.stripX(forLightness: 0, width: 200) == 200)
    }

    // MARK: - Snapping

    @Test func snapPicksNearestIslandWithinRadius() {
        let size = CGSize(width: 360, height: 180)
        let islands = ColorFilterService.islands(for: [makeSpool(id: 1, colorHex: "FF0000")])
        let center = ColorFilterService.mapPoint(forHex: "FF0000", in: size)!
        let near = CGPoint(x: center.x + 10, y: center.y + 5)
        #expect(ColorFilterService.snappedHex(nearMapPoint: near, islands: islands, in: size) == "FF0000")
        let far = CGPoint(x: center.x + 100, y: center.y)
        #expect(ColorFilterService.snappedHex(nearMapPoint: far, islands: islands, in: size) == nil)
    }

    @Test func snapWrapsAcrossHueSeam() {
        let size = CGSize(width: 360, height: 180)
        let islands = ColorFilterService.islands(for: [makeSpool(id: 1, colorHex: "FF0000")])
        let nearRightEdge = CGPoint(x: size.width - 4, y: 90)
        #expect(ColorFilterService.snappedHex(nearMapPoint: nearRightEdge, islands: islands, in: size) == "FF0000")
    }

    @Test func stripSnapMatchesAchromaticIslandsOnly() {
        let islands = ColorFilterService.islands(for: [makeSpool(id: 1, colorHex: "808080"), makeSpool(id: 2, colorHex: "FF0000")])
        let x = ColorFilterService.stripX(forLightness: 0.502, width: 200)
        #expect(ColorFilterService.snappedHex(nearStripX: x + 5, islands: islands, width: 200) == "808080")
        #expect(ColorFilterService.snappedHex(nearStripX: x + 50, islands: islands, width: 200) == nil)
    }

    // MARK: - Sizing

    @Test func islandDiameterGrowsAndCaps() {
        #expect(ColorFilterService.islandDiameter(spoolCount: 1, baseDiameter: 12) == 12)
        #expect(ColorFilterService.islandDiameter(spoolCount: 3, baseDiameter: 12) == 18)
        #expect(ColorFilterService.islandDiameter(spoolCount: 20, baseDiameter: 12) == 24)
    }

    @Test func islandDiameterClampsBaseToBounds() {
        #expect(ColorFilterService.islandDiameter(spoolCount: 1, baseDiameter: 2) == 8)
        #expect(ColorFilterService.islandDiameter(spoolCount: 1, baseDiameter: 99) == 20)
    }
}
