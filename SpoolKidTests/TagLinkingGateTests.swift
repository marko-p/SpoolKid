//
//  TagLinkingGateTests.swift
//  SpoolKidTests
//
//  v0.24 gated every "link this tag" control on the SpoolLink switch. On
//  Spoolman 0.27 the default is Spoolman Tags on and SpoolLink off, and a
//  link still goes somewhere — so the spool form, the hub's Link Tag and the
//  write screen all refused links that would have been stored fine. Since
//  spec 2 the on-device Library keeps links too.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct TagLinkingGateTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func isolatedDefaults(mode: TagIdentityMode) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(mode.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return defaults
    }

    /// Spec 2: the Library keeps its links in `card_uids`, so Tag Links has
    /// somewhere to write there.
    @Test func theLibraryLinksInTagLinks() throws {
        let store = SpoolDataStore(
            repository: LocalRepository(context: try makeContext()), defaults: isolatedDefaults(mode: .tagLinks)
        )
        #expect(store.availableTagStores == [.cardUIDs])
        #expect(store.tagIdentity.linkTargets == [.cardUIDs])
        #expect(store.tagIdentity.writesLinks)
    }

    /// A tag linked on the Library is its spool's: the owner check, which
    /// every claim site and the scan's link tier read, answers with it.
    @Test func aTagLinkedOnTheLibraryIdentifiesItsSpool() async throws {
        let store = SpoolDataStore(
            repository: LocalRepository(context: try makeContext()), defaults: isolatedDefaults(mode: .tagLinks)
        )
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        let outcome = await TagLinkService.assign("04aabbcc", to: spool, in: store)

        #expect(outcome == .saved)
        guard case .spool(let id, _) = store.owner(ofTagUID: "04AABBCC") else {
            Issue.record("the linked tag has no spool owner")
            return
        }
        #expect(id == spool.id)
    }

    /// A write must never report success for work it did not do: with links
    /// off, assign refuses instead of running a plan that adds nothing.
    @Test func assignRefusesWhenLinksAreOff() async throws {
        let store = SpoolDataStore(
            repository: LocalRepository(context: try makeContext()), defaults: isolatedDefaults(mode: .neither)
        )
        let spool = Spool(id: 1, filament: Filament(id: 1, name: "PLA"), statusId: nil, externalId: nil, purchaseDate: nil)
        let outcome = await TagLinkService.assign("04AABBCC", to: spool, in: store)
        #expect(outcome == .notSaved(TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel)))
    }

    // MARK: - SpoolFormView.createCarriesCardUIDs (unchanged by this task)

    @Test func aCardUIDsOnlyBackendSendsTheTagsWithTheNewSpool() {
        #expect(SpoolFormView.createCarriesCardUIDs(linkingActive: true, available: [.cardUIDs], hasUIDs: true))
    }

    @Test func aNativeTagServerLinksAfterCreatingInstead() {
        #expect(SpoolFormView.createCarriesCardUIDs(
            linkingActive: true, available: [.cardUIDs, .spoolmanTags], hasUIDs: true
        ) == false)
    }

    @Test func nothingRidesAlongWhenLinkingIsOffOrThereAreNoTags() {
        #expect(SpoolFormView.createCarriesCardUIDs(linkingActive: false, available: [.cardUIDs], hasUIDs: true) == false)
        #expect(SpoolFormView.createCarriesCardUIDs(linkingActive: true, available: [.cardUIDs], hasUIDs: false) == false)
    }
}
