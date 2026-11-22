//
//  ScanResultHubLocationTests.swift
//  SpoolKidTests
//
//  Purpose: The hub's location-tag resolution — the uuid is authoritative, the
//  on-tag name is a cached label, and a tag written on another device still
//  works.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct ScanResultHubLocationTests {
    private func makeRegistry() throws -> LocationRegistry {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self,
            configurations: config
        )
        return LocationRegistry(context: ModelContext(container), backendKind: .spoolman)
    }

    @Test func aRenamedLocationResolvesByUUIDNotByTheNameOnTheTag() throws {
        let registry = try makeRegistry()
        let record = try #require(registry.add(name: "Shelf A"))
        registry.rename(from: "Shelf A", to: "Shelf Alpha")

        let payload = LocationTagPayload(uuid: record.uuid, name: "Shelf A")

        #expect(ScanResultHubView.resolvedLocationName(for: payload, registry: registry) == "Shelf Alpha")
    }

    @Test func anUnknownUUIDFallsBackToTheNameOnTheTag() throws {
        let registry = try makeRegistry()
        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf Z")

        #expect(ScanResultHubView.resolvedLocationName(for: payload, registry: registry) == "Shelf Z")
    }

    @Test func aNilRegistryFallsBackToTheNameOnTheTag() {
        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf Z")

        #expect(ScanResultHubView.resolvedLocationName(for: payload, registry: nil) == "Shelf Z")
    }

    /// After a name-collision adoption the entry keeps its own uuid, so the
    /// adopted tag is recognised by its hardware UID or not at all — and being
    /// unrecognised is what made "Add" repeat forever.
    @Test func aTagAdoptedIntoAnExistingNameResolvesByItsHardwareUID() throws {
        let registry = try makeRegistry()
        let existing = try #require(registry.add(name: "Shelf A"))
        registry.adopt(uuid: UUID(), name: "Shelf A", tagUID: "AABBCCDD")

        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf A")

        #expect(ScanResultHubView.registryRecord(
            for: payload, scannedUID: "aabbccdd", registry: registry
        )?.uuid == existing.uuid)
    }

    @Test func anUnknownTagResolvesToNoRecordAtAll() throws {
        let registry = try makeRegistry()
        registry.add(name: "Shelf A")

        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf Z")

        #expect(ScanResultHubView.registryRecord(
            for: payload, scannedUID: "11223344", registry: registry
        ) == nil)
    }

    @Test func theAdoptButtonNamesWhatItActuallyDoes() {
        #expect(ScanResultHubView.adoptButtonTitle(
            name: "Shelf A", nameIsAlreadyRegistered: false
        ) == "Add Shelf A")
        #expect(ScanResultHubView.adoptButtonTitle(
            name: "Shelf A", nameIsAlreadyRegistered: true
        ) == "Link This Tag to Shelf A")
    }

    @Test func readingASpoolTagReleasesAUIDTheRegistryStillClaimed() throws {
        let registry = try makeRegistry()
        let record = try #require(registry.add(name: "Shelf A"))
        registry.attachTag(uid: "AABBCCDD", to: record.uuid)

        // The tag has since been rewritten as a spool tag: it now decodes as
        // filament data under the same hardware UID.
        ScanResultHubView.healRegistry(afterReadingSpoolTagWithUID: "aabbccdd", registry: registry)

        #expect(registry.records.first?.tagUIDs.isEmpty == true)
    }

    @Test func healingLeavesOtherRecordsAlone() throws {
        let registry = try makeRegistry()
        let a = try #require(registry.add(name: "Shelf A"))
        let b = try #require(registry.add(name: "Shelf B"))
        registry.attachTag(uid: "AABBCCDD", to: a.uuid)
        registry.attachTag(uid: "11223344", to: b.uuid)

        ScanResultHubView.healRegistry(afterReadingSpoolTagWithUID: "AABBCCDD", registry: registry)

        #expect(registry.record(forTagUID: "11223344")?.uuid == b.uuid)
        #expect(registry.record(forTagUID: "AABBCCDD") == nil)
    }
}
