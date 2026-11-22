//
//  LocationArrangementStateTests.swift
//  SpoolKidTests
//
//  Purpose: Every drop semantic, decided without a device. A location drag
//  clamps; only a spool drag can miss.
//

import CoreGraphics
import Testing
@testable import SpoolKid

struct LocationArrangementStateTests {
    /// Three 60pt headers stacked from y=0: Unassigned, Shelf A, Shelf B.
    private let headers = [
        HeaderFrame(name: "", rect: CGRect(x: 0, y: 0, width: 320, height: 60)),
        HeaderFrame(name: "Shelf A", rect: CGRect(x: 0, y: 60, width: 320, height: 60)),
        HeaderFrame(name: "Shelf B", rect: CGRect(x: 0, y: 120, width: 320, height: 60))
    ]

    private func drop(_ x: CGFloat, _ y: CGFloat, _ grabbed: LocationArrangementState.Grabbed) -> LocationArrangementState.Drop {
        LocationArrangementState.drop(for: CGPoint(x: x, y: y), grabbed: grabbed, headers: headers)
    }

    // MARK: - Location drags

    @Test func aLocationDroppedOverTheFirstReorderableSlotLandsAtZero() {
        #expect(drop(160, 70, .location("Shelf B")) == .reorder(0))
    }

    @Test func aLocationDroppedBelowTheOtherShelfLandsAfterIt() {
        #expect(drop(160, 175, .location("Shelf A")) == .reorder(1))
    }

    @Test func aLocationDraggedFarBelowTheListClampsToTheEnd() {
        #expect(drop(160, 9_000, .location("Shelf A")) == .reorder(1))
    }

    @Test func aLocationDraggedFarAboveTheListClampsToTheStart() {
        #expect(drop(160, -9_000, .location("Shelf B")) == .reorder(0))
    }

    @Test func unassignedIsNotAReorderTargetSoItNeverConsumesAnIndex() {
        // y=30 is inside the Unassigned header; the only reorderable shelf
        // above the point is none, so the index is still 0.
        #expect(drop(160, 30, .location("Shelf B")) == .reorder(0))
    }

    @Test func aLocationDragWithNoOtherShelvesStaysPut() {
        let only = [HeaderFrame(name: "Shelf A", rect: CGRect(x: 0, y: 0, width: 320, height: 60))]

        let result = LocationArrangementState.drop(
            for: CGPoint(x: 160, y: 30), grabbed: .location("Shelf A"), headers: only
        )

        #expect(result == .reorder(0))
    }

    @Test func aLocationDragWithNoHeadersAtAllCancels() {
        let result = LocationArrangementState.drop(
            for: CGPoint(x: 160, y: 30), grabbed: .location("Shelf A"), headers: []
        )

        #expect(result == .cancel)
    }

    // MARK: - Spool drags

    @Test func aSpoolDroppedOnAnotherShelfAssignsIt() {
        #expect(drop(160, 150, .spool(10, from: "Shelf A")) == .assign("Shelf B"))
    }

    @Test func aSpoolDroppedOnItsOwnShelfCancels() {
        #expect(drop(160, 90, .spool(10, from: "Shelf A")) == .cancel)
    }

    @Test func ownShelfIsMatchedIgnoringCaseAndSpace() {
        #expect(drop(160, 90, .spool(10, from: "  shelf a ")) == .cancel)
    }

    @Test func aSpoolDroppedOnUnassignedClearsItsLocation() {
        #expect(drop(160, 30, .spool(10, from: "Shelf A")) == .unassign)
    }

    @Test func anAlreadyUnassignedSpoolDroppedOnUnassignedCancels() {
        #expect(drop(160, 30, .spool(40, from: "")) == .cancel)
    }

    @Test func aSpoolDroppedOnNothingCancels() {
        #expect(drop(160, 400, .spool(10, from: "Shelf A")) == .cancel)
    }

    @Test func aSpoolDroppedBesideTheListHorizontallyCancels() {
        #expect(drop(900, 150, .spool(10, from: "Shelf A")) == .cancel)
    }
}
