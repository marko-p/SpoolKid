//
//  LocationOrderTests.swift
//  SpoolKidTests
//
//  Purpose: The hand-arranged order of locations is advisory — it may name
//  shelves that no longer exist and omit ones that just appeared, and it must
//  render sensibly either way.
//

import Testing
@testable import SpoolKid

struct LocationOrderTests {
    @Test func anEmptyOrderFallsThroughToCaseInsensitiveNameOrder() {
        let order = LocationOrder()

        #expect(order.arranged(["shelf b", "Shelf A", "Bin C"]) == ["Bin C", "Shelf A", "shelf b"])
    }

    @Test func knownNamesKeepStoredOrderAndUnknownNamesAppendByName() {
        let order = LocationOrder.seed(from: ["Shelf C", "Shelf A"])

        #expect(order.arranged(["Shelf A", "Shelf B", "Shelf C", "Bin Z"]) == ["Shelf C", "Shelf A", "Bin Z", "Shelf B"])
    }

    @Test func arrangedNeverDropsANameItDoesNotKnow() {
        let order = LocationOrder.seed(from: ["Shelf A"])

        let arranged = order.arranged(["Shelf A", "Shelf B", "Shelf C"])

        #expect(Set(arranged) == Set(["Shelf A", "Shelf B", "Shelf C"]))
        #expect(arranged.count == 3)
    }

    @Test func orderMatchesNamesIgnoringCaseAndSurroundingSpace() {
        let order = LocationOrder.seed(from: ["  SHELF B ", "shelf a"])

        #expect(order.arranged(["Shelf A", "Shelf B"]) == ["Shelf B", "Shelf A"])
    }

    @Test func moveSeedsFromWhatIsOnScreenSoADragWhileSortedDoesNotJump() {
        var order = LocationOrder()

        order.move("Shelf C", to: 0, within: ["Shelf A", "Shelf B", "Shelf C"])

        #expect(order.arranged(["Shelf A", "Shelf B", "Shelf C"]) == ["Shelf C", "Shelf A", "Shelf B"])
    }

    @Test func moveToTheEndClampsRatherThanFailing() {
        var order = LocationOrder()

        order.move("Shelf A", to: 99, within: ["Shelf A", "Shelf B"])

        #expect(order.arranged(["Shelf A", "Shelf B"]) == ["Shelf B", "Shelf A"])
    }

    @Test func movingANameThatIsNotVisibleChangesNothing() {
        var order = LocationOrder.seed(from: ["Shelf A", "Shelf B"])

        order.move("Shelf Z", to: 0, within: ["Shelf A", "Shelf B"])

        #expect(order.keys == ["shelf a", "shelf b"])
    }

    @Test func renameCarriesAShelfsPositionWithIt() {
        var order = LocationOrder.seed(from: ["Shelf A", "Shelf B", "Shelf C"])

        order.rename(from: "Shelf B", to: "Bin Beta")

        #expect(order.arranged(["Shelf A", "Bin Beta", "Shelf C"]) == ["Shelf A", "Bin Beta", "Shelf C"])
    }

    @Test func renameOntoANameAlreadyInTheOrderLeavesOnePosition() {
        var order = LocationOrder.seed(from: ["Shelf A", "Shelf B", "Shelf C"])

        order.rename(from: "Shelf A", to: "Shelf C")

        #expect(order.keys == ["shelf c", "shelf b"])
    }

    @Test func pruneForgetsShelvesTheBackendNoLongerLists() {
        var order = LocationOrder.seed(from: ["Shelf A", "Shelf B", "Shelf C"])

        order.prune(keeping: ["Shelf A", "Shelf C"])

        #expect(order.keys == ["shelf a", "shelf c"])
    }

    @Test func blankNamesNeverEnterTheOrder() {
        let order = LocationOrder.seed(from: ["Shelf A", "   ", ""])

        #expect(order.keys == ["shelf a"])
    }
}
