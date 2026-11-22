//
//  ElegooCanvasCatalogTests.swift
//  SpoolKidTests
//
//  The catalog decides what page 19 of an ELEGOO tag says. Only two of its
//  pairs are evidenced by a real tag — PLA 0/0 (five factory spools) and
//  PLA 0/4 "PLA-CF" (DnG-Crafts' dump) — so those are pinned literally; the
//  rest must at least be internally consistent.
//

import Testing
@testable import SpoolKid

struct ElegooCanvasCatalogTests {

    // MARK: - The table

    @Test func theEvidencedPairsAreInTheTable() {
        #expect(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 0)?.name == "PLA")
        #expect(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 4)?.name == "PLA-CF")
    }

    @Test func everyTypeAndSubtypePairIsListedOnce() {
        let ids = ElegooCanvasCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        let names = ElegooCanvasCatalog.entries.map(\.name)
        #expect(Set(names).count == names.count)
    }

    /// Fifteen types, transcribed from canvasspoolrfidprogrammer's table with
    /// its gaps (no PLA 5/7, no TPU 0, no PC 1).
    @Test func theTableHoldsEveryEntryOfItsSource() {
        #expect(ElegooCanvasCatalog.entries.count == 33)
        #expect(Set(ElegooCanvasCatalog.entries.map(\.typeIndex)) == Set(0...14))
        #expect(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 5) == nil)
        #expect(ElegooCanvasCatalog.entry(typeIndex: 3, subtypeID: 0) == nil)
        #expect(ElegooCanvasCatalog.entry(typeIndex: 3, subtypeID: 1)?.name == "TPU 95A")
        #expect(ElegooCanvasCatalog.entry(typeIndex: 14, subtypeID: 0)?.name == "PPS")
    }

    // MARK: - Tag fields

    @Test func aBaseEntryCarriesNoSubtype() throws {
        let pla = try #require(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 0))
        #expect(ElegooCanvasCatalog.tagFields(for: pla) == ElegooCanvasCatalog.TagFields(material: "PLA", subtype: nil))
    }

    @Test func aSubtypeEntryCarriesItsCanvasName() throws {
        let silk = try #require(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 3))
        #expect(ElegooCanvasCatalog.tagFields(for: silk) == ElegooCanvasCatalog.TagFields(material: "PLA", subtype: "PLA Silk"))
    }

    /// The encoder resolves only what `tagFields` produces, so a write followed
    /// by a read lands on the same entry.
    @Test(arguments: ElegooCanvasCatalog.entries)
    func tagFieldsResolveBackToTheirEntry(entry: ElegooCanvasCatalog.Entry) {
        let fields = ElegooCanvasCatalog.tagFields(for: entry)
        #expect(ElegooCanvasCatalog.entry(forTagMaterial: fields.material, subtype: fields.subtype) == entry)
    }

    @Test func anEmptySubtypeIsTheBaseEntry() {
        #expect(ElegooCanvasCatalog.entry(forTagMaterial: "PLA", subtype: "")?.name == "PLA")
    }

    @Test(arguments: [
        ("PLA", "Glow"), ("Nylon", ""), ("TPU", ""), ("PETG", "PLA Silk")
    ])
    func theExactLookupRefusesWhatTheCatalogDoesNotHold(material: String, subtype: String) {
        #expect(ElegooCanvasCatalog.entry(forTagMaterial: material, subtype: subtype) == nil)
    }

    // MARK: - Prefill suggestion

    @Test(arguments: [
        ("PLA", "", "PLA"),
        ("PLA", "Silk", "PLA Silk"),
        ("pla", "silk", "PLA Silk"),
        ("PLA", "Matte", "PLA Matte"),
        ("PLA", "Basic", "PLA"),
        ("PLA", "PLA Basic", "PLA Basic"),
        ("PLA", "Carbon Fiber", "PLA-CF"),
        ("PETG", "Carbon Fiber", "PETG-CF"),
        ("PETG", "Translucent", "PETG Translucent"),
        ("PETG", "Rapid", "RAPID PETG"),
        ("PLA", "Rapid", "RAPID PLA+"),
        ("PLA", "Red Copper", "PLA Red Copper"),
        ("PLA", "PLA Silk", "PLA Silk"),
        ("PLA+", "", "PLA+"),
        ("Flexible (TPU)", "", "TPU 95A"),
        ("Flexible (TPU)", "Rapid", "RAPID TPU 95A"),
        ("Polycarbonate (PC)", "", "PC"),
        ("Polypropylene (PP)", "", "PP"),
        ("PLA", "Glow", "PLA"),
        ("ABS", "Silk", "ABS")
    ])
    func theSuggestionFollowsTheLadder(material: String, subtype: String, expected: String) {
        #expect(ElegooCanvasCatalog.suggestedEntry(material: material, subtype: subtype)?.name == expected)
    }

    /// "Basic" is SpoolKid's default subtype — the write form starts on it and
    /// `SubtypeOptionService.derive` falls back to it — so it means "plain",
    /// and plain is ID 0, the pair every factory spool carries. "PLA Basic"
    /// (ID 9) needs asking for by name.
    @Test func basicSuggestsTheTypesPlainEntry() {
        #expect(ElegooCanvasCatalog.suggestedEntry(material: "pla", subtype: " BASIC ")?.name == "PLA")
    }

    @Test(arguments: ["Nylon", "PCTG", "PEEK", ""])
    func aMaterialTheCanvasDoesNotKnowSuggestsNothing(material: String) {
        #expect(ElegooCanvasCatalog.suggestedEntry(material: material, subtype: "") == nil)
    }
}
