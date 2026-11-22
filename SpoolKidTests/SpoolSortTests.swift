import Testing
import Foundation
@testable import SpoolKid

struct SpoolSortTests {

    private func makeSpool(id: Int, name: String? = nil, vendor: String? = nil,
                           material: String? = nil, remainingWeight: Double? = nil,
                           lastUsed: Date? = nil, location: String? = nil) -> Spool {
        Spool(
            id: id,
            filament: Filament(
                id: id,
                name: name,
                material: material,
                vendor: vendor.map { Vendor(id: id, name: $0) }
            ),
            lastUsed: lastUsed,
            remainingWeight: remainingWeight,
            location: location,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func sortSpoolsByNameAscending() {
        let spools = [
            makeSpool(id: 1, name: "Zebra"),
            makeSpool(id: 2, name: "Apple"),
            makeSpool(id: 3, name: "Mango")
        ]

        let sorted = spools.sorted { SpoolSortOption.name.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.name == "Apple")
        #expect(sorted[1].filament.name == "Mango")
        #expect(sorted[2].filament.name == "Zebra")
    }

    @Test func sortSpoolsByNameDescending() {
        let spools = [
            makeSpool(id: 1, name: "Zebra"),
            makeSpool(id: 2, name: "Apple"),
            makeSpool(id: 3, name: "Mango")
        ]

        let sorted = spools.sorted { !SpoolSortOption.name.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.name == "Zebra")
        #expect(sorted[1].filament.name == "Mango")
        #expect(sorted[2].filament.name == "Apple")
    }

    @Test func sortSpoolsByIdAscending() {
        let spools = [
            makeSpool(id: 3),
            makeSpool(id: 1),
            makeSpool(id: 2)
        ]

        let sorted = spools.sorted { SpoolSortOption.id.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].id == 1)
        #expect(sorted[1].id == 2)
        #expect(sorted[2].id == 3)
    }

    @Test func sortSpoolsByIdDescending() {
        let spools = [
            makeSpool(id: 3),
            makeSpool(id: 1),
            makeSpool(id: 2)
        ]

        let sorted = spools.sorted { !SpoolSortOption.id.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].id == 3)
        #expect(sorted[1].id == 2)
        #expect(sorted[2].id == 1)
    }

    @Test func sortSpoolsByRemainingWeightAscending() {
        let spools = [
            makeSpool(id: 1, remainingWeight: 500),
            makeSpool(id: 2, remainingWeight: 100),
            makeSpool(id: 3, remainingWeight: 900)
        ]

        let sorted = spools.sorted { SpoolSortOption.remainingWeight.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].remainingWeight == 100)
        #expect(sorted[1].remainingWeight == 500)
        #expect(sorted[2].remainingWeight == 900)
    }

    @Test func sortSpoolsByVendor() {
        let spools = [
            makeSpool(id: 1, vendor: "Zebra"),
            makeSpool(id: 2, vendor: "Apple"),
            makeSpool(id: 3, vendor: "Mango")
        ]

        let sorted = spools.sorted { SpoolSortOption.vendor.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.vendor?.name == "Apple")
        #expect(sorted[1].filament.vendor?.name == "Mango")
        #expect(sorted[2].filament.vendor?.name == "Zebra")
    }

    @Test func sortSpoolsByMaterial() {
        let spools = [
            makeSpool(id: 1, material: "PETG"),
            makeSpool(id: 2, material: "PLA"),
            makeSpool(id: 3, material: "ABS")
        ]

        let sorted = spools.sorted { SpoolSortOption.material.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.material == "ABS")
        #expect(sorted[1].filament.material == "PETG")
        #expect(sorted[2].filament.material == "PLA")
    }

    @Test func sortSpoolsByLocation() {
        let spools = [
            makeSpool(id: 1, location: "Shelf C"),
            makeSpool(id: 2, location: "Shelf A"),
            makeSpool(id: 3, location: "Shelf B")
        ]

        let sorted = spools.sorted { SpoolSortOption.location.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].location == "Shelf A")
        #expect(sorted[1].location == "Shelf B")
        #expect(sorted[2].location == "Shelf C")
    }

    @Test func sortSpoolsByLastUsed() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        let spools = [
            makeSpool(id: 1, lastUsed: date2),
            makeSpool(id: 2, lastUsed: date3),
            makeSpool(id: 3, lastUsed: date1)
        ]

        let sorted = spools.sorted { SpoolSortOption.lastUsed.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].lastUsed == date1)
        #expect(sorted[1].lastUsed == date2)
        #expect(sorted[2].lastUsed == date3)
    }

    @Test func sortSpoolsHandlesNilValues() {
        let spools = [
            makeSpool(id: 1, name: nil),
            makeSpool(id: 2, name: "Apple"),
            makeSpool(id: 3, name: nil)
        ]

        let sorted = spools.sorted { SpoolSortOption.name.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.name == nil)
        #expect(sorted[1].filament.name == nil)
        #expect(sorted[2].filament.name == "Apple")
    }

    @Test func sortSpoolsByNameLocaleOrdering() {
        let spools = [
            makeSpool(id: 1, name: "apple"),
            makeSpool(id: 2, name: "Banana"),
            makeSpool(id: 3, name: "cherry")
        ]

        let sorted = spools.sorted { SpoolSortOption.name.areInIncreasingOrder($0, $1) }

        #expect(sorted[0].filament.name == "apple")
        #expect(sorted[1].filament.name == "Banana")
        #expect(sorted[2].filament.name == "cherry")
    }
}
