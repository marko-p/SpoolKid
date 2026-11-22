//
//  DragAutoScrollTests.swift
//  SpoolKidTests
//
//  Purpose: The edge zones and the seed index, decided without a device.
//

import CoreGraphics
import Testing
@testable import SpoolKid

struct DragAutoScrollTests {
    /// A list 600pt tall starting 100pt down, the way it sits under a nav bar.
    private let bounds = CGRect(x: 0, y: 100, width: 320, height: 600)

    private func edge(_ x: CGFloat, _ y: CGFloat) -> DragAutoScroll.Edge? {
        DragAutoScroll.edge(for: CGPoint(x: x, y: y), in: bounds)
    }

    // MARK: - Edge zones

    @Test func theMiddleOfTheListAsksForNothing() {
        #expect(edge(160, 400) == nil)
    }

    @Test func withinNinetyPointsOfTheTopAsksToScrollUp() {
        #expect(edge(160, 150) == .top)
    }

    @Test func withinNinetyPointsOfTheBottomAsksToScrollDown() {
        #expect(edge(160, 650) == .bottom)
    }

    @Test func theZoneBoundariesAreExclusiveOfTheNeutralBand() {
        #expect(edge(160, 189) == .top)
        #expect(edge(160, 190) == nil)
        #expect(edge(160, 610) == nil)
        #expect(edge(160, 611) == .bottom)
    }

    @Test func aFingerDraggedPastTheBottomEdgeStillAsksToScrollDown() {
        #expect(edge(160, 740) == .bottom)
    }

    @Test func theUnstartedDragAtTheOriginAsksForNothing() {
        // (0, 0) is what `dragLocation` holds before the first gesture update.
        #expect(edge(0, 0) == nil)
    }

    @Test func aPointBesideTheListAsksForNothing() {
        #expect(edge(900, 650) == nil)
    }

    @Test func anEmptyListAsksForNothing() {
        #expect(DragAutoScroll.edge(for: CGPoint(x: 160, y: 150), in: .zero) == nil)
    }

    @Test func aShortListKeepsANeutralBandInTheMiddle() {
        // 120pt tall: a full 90pt zone at each end would cover it twice over.
        let short = CGRect(x: 0, y: 0, width: 320, height: 120)

        #expect(DragAutoScroll.edge(for: CGPoint(x: 160, y: 20), in: short) == .top)
        #expect(DragAutoScroll.edge(for: CGPoint(x: 160, y: 60), in: short) == nil)
        #expect(DragAutoScroll.edge(for: CGPoint(x: 160, y: 100), in: short) == .bottom)
    }

    // MARK: - Seed index

    private let frames = [
        "": CGRect(x: 0, y: 100, width: 320, height: 60),
        "Shelf A": CGRect(x: 0, y: 160, width: 320, height: 60),
        "Shelf B": CGRect(x: 0, y: 220, width: 320, height: 60)
    ]
    private let names = ["", "Shelf A", "Shelf B", "Shelf C"]

    @Test func theNearestHeaderToTheFingerSeedsTheCount() {
        #expect(DragAutoScroll.nearestIndex(to: 250, orderedNames: names, frames: frames) == 2)
        #expect(DragAutoScroll.nearestIndex(to: 105, orderedNames: names, frames: frames) == 0)
    }

    @Test func anUnmeasuredRowIsSkippedRatherThanGuessedAt() {
        // "Shelf C" has scrolled out of the lazy list and has no frame, so the
        // nearest MEASURED header wins even for a point well below it.
        #expect(DragAutoScroll.nearestIndex(to: 9_000, orderedNames: names, frames: frames) == 2)
    }

    @Test func nothingMeasuredMeansNoSeedAtAll() {
        #expect(DragAutoScroll.nearestIndex(to: 250, orderedNames: names, frames: [:]) == nil)
    }
}
