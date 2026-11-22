//
//  CatalogSpoolWeightTests.swift
//  SpoolKidTests
//
//  Purpose: The empty-spool weight a filament lacks, taken from its public
//  catalogue when a new spool needs it: the match rule, which weight goes back
//  to the filament, how the spool form's follow rule treats a late answer, and
//  the FilaManDB lookup. No test touches the network; every FilaManDB call
//  goes through an injected fetch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

/// Records the URLs asked for and answers each from `answer`.
private nonisolated final class RecordingFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private let answer: @Sendable (URL) throws -> Data

    init(answer: @escaping @Sendable (URL) throws -> Data) {
        self.answer = answer
    }

    var requested: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    var catalog: FilaManDBCatalog {
        FilaManDBCatalog(fetch: { url in
            self.record(url)
            return try self.answer(url)
        })
    }

    private func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }
}

struct CatalogSpoolWeightTests {
    // MARK: - Fixtures

    private static func entry(
        manufacturer: String = "Prusament", name: String = "Galaxy Black", material: String = "PLA",
        diameter: Double = 1.75, weight: Double? = 1000, spoolWeight: Double? = 193
    ) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: UUID().uuidString, manufacturer: manufacturer, name: name, material: material,
            spoolType: nil, density: 1.24, weight: weight, spoolWeight: spoolWeight, diameter: diameter,
            colorHex: nil, extruderTemp: nil, bedTemp: nil
        )
    }

    private static func match(
        manufacturer: String? = "Prusament", name: String? = "Galaxy Black", material: String? = "PLA",
        diameter: Double? = 1.75, netWeight: Double? = 1000,
        in entries: [SpoolmanDBFilament]
    ) -> Double? {
        CatalogSpoolWeight.match(
            manufacturer: manufacturer, name: name, material: material,
            diameter: diameter, netWeight: netWeight, in: entries
        )
    }

    // MARK: - Match rule

    @Test func exactlyOneWeightFills() {
        #expect(Self.match(in: [Self.entry(), Self.entry()]) == 193)
    }

    /// Review focus 3: one product in several sizes with different spool weights.
    @Test func severalDifferentWeightsFillNothing() {
        let entries = [Self.entry(spoolWeight: 193), Self.entry(spoolWeight: 250)]
        #expect(Self.match(netWeight: nil, in: entries) == nil)
    }

    @Test func matchIgnoresCaseAndSpacesAndUsesTheBrandKey() {
        #expect(Self.match(manufacturer: "Prusament ", name: "galaxy black", in: [Self.entry()]) == 193)
        #expect(Self.match(manufacturer: "PRUSAMENT", name: "  GALAXY BLACK  ", material: " pla", in: [Self.entry()]) == 193)
    }

    @Test func anotherBrandOrNameIsNotAMatch() {
        #expect(Self.match(manufacturer: "Prusa", in: [Self.entry()]) == nil)
        #expect(Self.match(name: "Galaxy Silver", in: [Self.entry()]) == nil)
        #expect(Self.match(name: "Galaxy", in: [Self.entry()]) == nil)
    }

    @Test func materialAndDiameterMustAgree() {
        #expect(Self.match(material: "PETG", in: [Self.entry(material: "PLA")]) == nil)
        #expect(Self.match(diameter: 2.85, in: [Self.entry(diameter: 1.75)]) == nil)
        #expect(Self.match(diameter: 1.75, in: [Self.entry(diameter: 1.75)]) == 193)
        // Within 0.01 mm is the same diameter.
        #expect(Self.match(diameter: 1.749, in: [Self.entry(diameter: 1.75)]) == 193)
    }

    @Test func netWeightDecidesOnlyWhenBothStateIt() {
        let sizes = [Self.entry(weight: 1000, spoolWeight: 193), Self.entry(weight: 2000, spoolWeight: 250)]
        #expect(Self.match(netWeight: 1000, in: sizes) == 193)
        #expect(Self.match(netWeight: 2000, in: sizes) == 250)
        // No net weight on the filament: both sizes match, so it is ambiguous.
        #expect(Self.match(netWeight: nil, in: sizes) == nil)
        #expect(Self.match(netWeight: 0, in: sizes) == nil)
        // An entry stating none is not disqualified.
        #expect(Self.match(netWeight: 1000, in: [Self.entry(weight: nil, spoolWeight: 193)]) == 193)
        #expect(Self.match(netWeight: 1000, in: [Self.entry(weight: 0, spoolWeight: 193)]) == 193)
        // A size the filament does not state is no match.
        #expect(Self.match(netWeight: 750, in: sizes) == nil)
    }

    @Test func noWeightNoFill() {
        #expect(Self.match(in: [Self.entry(spoolWeight: nil)]) == nil)
        #expect(Self.match(in: [Self.entry(spoolWeight: 0)]) == nil)
        #expect(Self.match(in: [Self.entry(spoolWeight: nil), Self.entry(spoolWeight: 0)]) == nil)
        #expect(Self.match(in: []) == nil)
    }

    /// An entry that states no weight does not make a stated one ambiguous.
    @Test func anEntryWithoutAWeightDoesNotBlockAStatedOne() {
        #expect(Self.match(in: [Self.entry(spoolWeight: nil), Self.entry(spoolWeight: 193)]) == 193)
    }

    @Test func aFilamentMissingWhatItIsMatchedOnMatchesNothing() {
        let entries = [Self.entry()]
        #expect(Self.match(manufacturer: nil, in: entries) == nil)
        #expect(Self.match(manufacturer: "  ", in: entries) == nil)
        #expect(Self.match(name: nil, in: entries) == nil)
        #expect(Self.match(name: " ", in: entries) == nil)
        #expect(Self.match(material: nil, in: entries) == nil)
        #expect(Self.match(diameter: nil, in: entries) == nil)
    }

    // MARK: - What goes back to the filament

    @Test func weightToSaveOnlyWhenKept() {
        let answer: (filamentId: Int, grams: Double) = (filamentId: 7, grams: 193)
        #expect(CatalogSpoolWeight.weightToSave(lookedUp: answer, savedFilamentId: 7, savedSpoolWeight: 193) == 193)
        // A spool saved under another filament.
        #expect(CatalogSpoolWeight.weightToSave(lookedUp: answer, savedFilamentId: 8, savedSpoolWeight: 193) == nil)
        // The user changed the weight.
        #expect(CatalogSpoolWeight.weightToSave(lookedUp: answer, savedFilamentId: 7, savedSpoolWeight: 200) == nil)
        #expect(CatalogSpoolWeight.weightToSave(lookedUp: answer, savedFilamentId: 7, savedSpoolWeight: nil) == nil)
        // Nothing was looked up.
        #expect(CatalogSpoolWeight.weightToSave(lookedUp: nil, savedFilamentId: 7, savedSpoolWeight: 193) == nil)
    }

    /// Review focus 5: the spool is saved, the filament write failed, and the
    /// notice says so.
    @Test func writeBackFailureNotice() {
        #expect(
            CatalogSpoolWeight.writeBackFailedNote
                == "The spool was saved, but its empty spool weight could not be saved to the filament."
        )
    }

    // MARK: - The spool form's follow rule

    /// Review focus 1: the user typed or picked a weight, then the answer arrived.
    @Test func aLateCatalogueAnswerNeverReplacesATypedWeight() {
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "180", autoFilled: "250", isNewSpool: true,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0"
        ) == nil)
        // A picked or applied weight clears autoFilled.
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "250", autoFilled: nil, isNewSpool: true,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0"
        ) == nil)
    }

    @Test func aLateCatalogueAnswerFillsAnUntouchedField() {
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "250", autoFilled: "250", isNewSpool: true,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0"
        ) == "193")
    }

    /// Review focus 2: no answer (unreachable, ambiguous, unknown) leaves the
    /// library's value in place.
    @Test func noCatalogueAnswerFallsBackToTheLibrary() {
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: nil, entryWeight: 250, lastUsed: "0") == "250")
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: nil, entryWeight: nil, lastUsed: "180") == "180")
    }

    // MARK: - The scanned tag's own weight (2026-10-20)

    /// The tag describes this physical spool: an NFC Prusament spool weighs
    /// more than the 193 g a SpoolmanDB import states.
    @Test func theTagsWeightWinsForTheFilamentTheFormOpenedWith() {
        let tag: (filamentId: Int, grams: Double) = (filamentId: 6, grams: 277)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: tag, filamentId: 6, own: 193, catalogue: nil) == 277)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: tag, filamentId: 6, own: nil, catalogue: 219) == 277)
    }

    @Test func anotherFilamentIgnoresTheTagsWeight() {
        let tag: (filamentId: Int, grams: Double) = (filamentId: 6, grams: 277)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: tag, filamentId: 7, own: 193, catalogue: nil) == 193)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: tag, filamentId: 7, own: 0, catalogue: 219) == 219)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: tag, filamentId: nil, own: nil, catalogue: nil) == nil)
    }

    @Test func withoutATagTheFilamentsOwnWinsOverTheCatalogue() {
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: nil, filamentId: 7, own: 193, catalogue: 219) == 193)
        #expect(SpoolFormView.filamentAccountWeight(tagOffer: nil, filamentId: 7, own: nil, catalogue: 219) == 219)
    }

    /// The tag's weight goes back to the filament it was offered for, under
    /// the catalogue rule; a spool saved under another filament uses that
    /// filament's catalogue answer.
    @Test func theWriteBackOfferIsTheTagsForItsFilament() {
        let tag: (filamentId: Int, grams: Double) = (filamentId: 6, grams: 277)
        let lookedUp: (filamentId: Int, grams: Double) = (filamentId: 7, grams: 193)
        #expect(SpoolFormView.writeBackOffer(tagOffer: tag, lookedUp: lookedUp, savedFilamentId: 6)?.grams == 277)
        #expect(SpoolFormView.writeBackOffer(tagOffer: tag, lookedUp: lookedUp, savedFilamentId: 7)?.grams == 193)
        #expect(SpoolFormView.writeBackOffer(tagOffer: nil, lookedUp: lookedUp, savedFilamentId: 7)?.grams == 193)
        #expect(SpoolFormView.writeBackOffer(tagOffer: tag, lookedUp: nil, savedFilamentId: 7) == nil)
    }

    // MARK: - FilaManDB lookup

    fileprivate static let manufacturerPage = Data("""
    {"total":2,"page":1,"page_size":200,"items":[{"id":689,"name":"Prusament"},{"id":953,"name":"Prusamentos"}]}
    """.utf8)

    fileprivate static func filamentRow(id: Int, name: String, spoolWeight: Double?) -> String {
        let profile = spoolWeight.map {
            "{\"id\":1,\"name\":\"Spool\",\"empty_weight_g\":\($0),\"spool_material\":\"Plastic\"}"
        } ?? "null"
        return """
        {"id":\(id),"color_name":"\(name)","designation":"x","hex_color":"#1A1A1A",
         "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
         "manufacturer":{"id":689,"name":"Prusament"},"material":{"id":11,"key":"pla","name":"PLA"},
         "spool_profile":\(profile)}
        """
    }

    fileprivate static func filamentPage(rows: [String], total: Int) -> Data {
        Data("{\"total\":\(total),\"page\":1,\"page_size\":200,\"items\":[\(rows.joined(separator: ","))]}".utf8)
    }

    private nonisolated static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    fileprivate static func filamanDBAnswer(_ url: URL) -> Data {
        if url.path.hasSuffix("/manufacturers") { return manufacturerPage }
        return filamentPage(rows: [filamentRow(id: 1, name: "Galaxy Black", spoolWeight: 193)], total: 1)
    }

    private static func filamanDBWeight(
        _ fetch: RecordingFetch, manufacturer: String? = "Prusament", name: String? = "Galaxy Black"
    ) async throws -> Double? {
        try await CatalogSpoolWeight.filamanDBWeight(
            manufacturer: manufacturer, name: name, material: "PLA", diameter: 1.75, netWeight: 1000,
            catalog: fetch.catalog
        )
    }

    @Test func filamanDBIsAskedForTheBrandThenItsMatches() async throws {
        let fetch = RecordingFetch { Self.filamanDBAnswer($0) }

        let weight = try await Self.filamanDBWeight(fetch)

        #expect(weight == 193)
        #expect(fetch.requested.count == 2)
        #expect(fetch.requested[0].path.hasSuffix("/manufacturers"))
        #expect(Self.query(fetch.requested[0], "search") == "Prusament")
        #expect(fetch.requested[1].path.hasSuffix("/filaments"))
        #expect(Self.query(fetch.requested[1], "search") == "Galaxy Black")
        #expect(Self.query(fetch.requested[1], "manufacturer_id") == "689")
        #expect(Self.query(fetch.requested[1], "page_size") == "200")
    }

    /// The pagination amendment: a brand's matches run to several 200-row pages.
    @Test func filamanDBReadsEveryPageOfTheBrandsMatches() async throws {
        let fetch = RecordingFetch { url in
            if url.path.hasSuffix("/manufacturers") { return Self.manufacturerPage }
            let page = Int(Self.query(url, "page") ?? "") ?? 0
            if page == 1 {
                let filler = (1...200).map { Self.filamentRow(id: $0, name: "Other \($0)", spoolWeight: 100) }
                return Self.filamentPage(rows: filler, total: 201)
            }
            return Self.filamentPage(
                rows: [Self.filamentRow(id: 999, name: "Galaxy Black", spoolWeight: 193)], total: 201
            )
        }

        let weight = try await Self.filamanDBWeight(fetch)

        #expect(weight == 193)
        #expect(fetch.requested.filter { $0.path.hasSuffix("/filaments") }.count == 2)
    }

    @Test func filamanDBSeveralWeightsFillNothing() async throws {
        let fetch = RecordingFetch { url in
            if url.path.hasSuffix("/manufacturers") { return Self.manufacturerPage }
            return Self.filamentPage(rows: [
                Self.filamentRow(id: 1, name: "Galaxy Black", spoolWeight: 193),
                Self.filamentRow(id: 2, name: "Galaxy Black", spoolWeight: 250)
            ], total: 2)
        }

        #expect(try await Self.filamanDBWeight(fetch) == nil)
    }

    @Test func filamanDBBrandItDoesNotKnowAsksNoFilaments() async throws {
        let fetch = RecordingFetch { _ in Self.manufacturerPage }

        #expect(try await Self.filamanDBWeight(fetch, manufacturer: "Nobody") == nil)
        #expect(fetch.requested.allSatisfy { $0.path.hasSuffix("/manufacturers") })
    }

    @Test func filamanDBWithoutABrandOrNameAsksNothing() async throws {
        let fetch = RecordingFetch { Self.filamanDBAnswer($0) }

        #expect(try await Self.filamanDBWeight(fetch, manufacturer: nil) == nil)
        #expect(try await Self.filamanDBWeight(fetch, name: nil) == nil)
        #expect(try await Self.filamanDBWeight(fetch, name: "  ") == nil)
        #expect(fetch.requested.isEmpty)
    }

    @Test func filamanDBFailureIsAnErrorNotAnEmptyAnswer() async {
        let fetch = RecordingFetch { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: (any Error).self) {
            _ = try await Self.filamanDBWeight(fetch)
        }
    }
}

/// The lookup reads the store and builds `Filament`s, which live on the main actor.
@MainActor
struct CatalogSpoolWeightLookupTests {
    private static func filament(id: Int = 7) -> Filament {
        Filament(
            id: id, name: "Galaxy Black", material: "PLA",
            vendor: Vendor(id: 1, name: "Prusament"), diameter: 1.75, weight: 1000
        )
    }

    /// FilaMan reads FilaManDB, chosen by capability, never by the backend's identity.
    @Test func theLookupAnswersFromFilaManDBOnFilaMan() async {
        let store = SpoolDataStore(repository: FilaManRepository(service: FilaManService()))
        let fetch = RecordingFetch { CatalogSpoolWeightTests.filamanDBAnswer($0) }

        let weight = await lookUpCatalogSpoolWeight(for: Self.filament(), store: store, filamanDB: fetch.catalog)

        #expect(store.capabilities.manufacturerCatalog == .filamanDB)
        #expect(weight == 193)
    }

    /// Review focus 2: FilaManDB unreachable. The form gets nil and carries on.
    @Test func anUnreachableFilaManDBAnswersNil() async {
        let store = SpoolDataStore(repository: FilaManRepository(service: FilaManService()))
        let fetch = RecordingFetch { _ in throw URLError(.timedOut) }

        let weight = await lookUpCatalogSpoolWeight(for: Self.filament(), store: store, filamanDB: fetch.catalog)

        #expect(weight == nil)
        #expect(!fetch.requested.isEmpty)
    }
}
