//
//  FilamentTagLinkingTests.swift
//  SpoolKidTests
//
//  Spec 4: the store is the one place a filament link is written — Tag
//  Links only, never over another holder — and unlinking runs in every mode.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct FilamentTagLinkingTests {
    private func makeRepository() throws -> LocalRepository {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LocalRepository(context: ModelContext(container))
    }

    private func defaults(mode: TagIdentityMode) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(mode.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return defaults
    }

    private func linkedUIDs(of filamentId: Int, in store: SpoolDataStore) -> [String]? {
        store.filaments.first { $0.id == filamentId }?.mappedTagUIDs
    }

    @Test func theLibraryLinksAFilamentTag() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA Basic")))

        #expect(store.filamentTagStore == .cardUIDs)
        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04aabbcc") == .linked)
        #expect(linkedUIDs(of: filament.id, in: store) == ["04AABBCC"])
        guard case .filament(let id, _) = store.owner(ofTagUID: "04AABBCC") else {
            Issue.record("the tag has no filament owner")
            return
        }
        #expect(id == filament.id)

        // Linking it again changes nothing.
        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04AABBCC") == .linked)
        #expect(linkedUIDs(of: filament.id, in: store) == ["04AABBCC"])
    }

    @Test func outsideTagLinksNoFilamentLinkIsWritten() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .neither))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA Basic")))

        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04AA")
            == .failed(TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel)))
        #expect(linkedUIDs(of: filament.id, in: store) == [])
    }

    /// One tag, one owner: a spool's tag is not taken, and nothing is written.
    @Test func aTagASpoolHoldsIsAConflictNamingTheSpool() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await store.setCardUIDs(spoolId: spool.id, uids: ["04AA"]))

        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04AA") == .heldBySpool(spool.id))
        #expect(linkedUIDs(of: filament.id, in: store) == [])
    }

    @Test func aTagAnotherFilamentHoldsIsAConflictNamingIt() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let first = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let second = try #require(await store.addFilament(draft: FilamentDraft(name: "PETG")))
        #expect(await store.linkFilamentTag(filamentId: first.id, uid: "04AA") == .linked)

        #expect(await store.linkFilamentTag(filamentId: second.id, uid: "04AA") == .heldByFilament(first.id))
        #expect(linkedUIDs(of: second.id, in: store) == [])
    }

    /// Unlinking runs in every mode: a wrong link must stay removable.
    @Test func unlinkingRunsInEveryMode() async throws {
        let repository = try makeRepository()
        let linking = SpoolDataStore(repository: repository, defaults: defaults(mode: .tagLinks))
        let filament = try #require(await linking.addFilament(draft: FilamentDraft(name: "PLA")))
        #expect(await linking.linkFilamentTag(filamentId: filament.id, uid: "04AA") == .linked)

        let neither = SpoolDataStore(repository: repository, defaults: defaults(mode: .neither))
        #expect(await neither.unlinkFilamentTag(filamentId: filament.id, uid: "04aa"))
        #expect(linkedUIDs(of: filament.id, in: neither) == [])
    }

    /// A copy written over a filament's tag takes it from the filament, as
    /// it does from a spool or a shelf.
    @Test func releasingAClonedTagUnlinksItsFilament() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        #expect(await store.linkFilamentTag(filamentId: filament.id, uid: "04F1AE7C") == .linked)

        #expect(await TagCloneService.releasePreviousOwner(uid: "04F1AE7C", store: store) == nil)
        #expect(store.owner(ofTagUID: "04F1AE7C") == .none)
        #expect(linkedUIDs(of: filament.id, in: store) == [])
    }

    /// A backend with no filament store (FilaMan, Spoolman before 0.27).
    @Test func noFilamentStoreNoLink() async {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        let store = SpoolDataStore(repository: writer, defaults: defaults(mode: .tagLinks))

        #expect(store.filamentTagStore == nil)
        #expect(await store.linkFilamentTag(filamentId: 1, uid: "04AA")
            == .failed(TagStoreText.noFilamentStoreNote(displayName: store.capabilities.displayName)))
        #expect(writer.linkFilamentTagCalls.isEmpty)
    }

    /// Spoolman's 409 names whatever holds the tag.
    @Test func aConflictNamesASpoolOrAFilamentHolder() {
        #expect(SpoolmanService.conflictOutcome(from: Data(#"{"message":"x","spool_id":3,"filament_id":null}"#.utf8))
            == .heldBySpool(3))
        #expect(SpoolmanService.conflictOutcome(from: Data(#"{"message":"x","spool_id":null,"filament_id":7}"#.utf8))
            == .heldByFilament(7))
        #expect(SpoolmanService.conflictOutcome(from: Data(#"{"message":"Held elsewhere"}"#.utf8))
            == .failed("Held elsewhere"))
    }
}
