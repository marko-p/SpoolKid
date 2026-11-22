//
//  BackendCapabilitiesTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct BackendCapabilitiesTests {
    @Test func localDeclaresOnDeviceStorageAndQuota() {
        let caps = BackendCapabilities.local

        #expect(caps.kind == .local)
        #expect(caps.displayName == "Library")
        #expect(caps.tabSymbol == "books.vertical")
        #expect(caps.isOnDeviceStorage)
        #expect(caps.spoolCapacity == Entitlement.localCapacity)
        #expect(caps.supportsCurrencySetting == false)
    }

    @Test func spoolmanIsUncappedServerWithCurrency() {
        let caps = BackendCapabilities.spoolman

        #expect(caps.kind == .spoolman)
        #expect(caps.displayName == "Spoolman")
        #expect(caps.tabSymbol == "server.rack")
        #expect(caps.isOnDeviceStorage == false)
        #expect(caps.spoolCapacity == nil)
        #expect(caps.supportsCurrencySetting)
    }

    @Test func filamanIsUncappedServerWithNoCurrencySetting() {
        let caps = BackendCapabilities.filaman

        #expect(caps.kind == .filaman)
        #expect(caps.displayName == "FilaMan")
        #expect(caps.tabSymbol == "server.rack")
        #expect(caps.isOnDeviceStorage == false)
        #expect(caps.spoolCapacity == nil)
        #expect(caps.supportsCurrencySetting == false)
    }

    @Test func onlyLocalStoresOnDevice() {
        let all: [BackendCapabilities] = [.local, .spoolman, .filaman]
        let onDevice = all.filter(\.isOnDeviceStorage)

        #expect(onDevice.map(\.kind) == [.local])
    }

    @Test func capacityIsNilExactlyWhenNotOnDevice() {
        for caps in [BackendCapabilities.local, .spoolman, .filaman] {
            #expect((caps.spoolCapacity == nil) == !caps.isOnDeviceStorage)
        }
    }

    /// The Backend picker has to describe a kind the app is not currently
    /// running — `store.capabilities` answers only for the active one. Every
    /// case must map to its own row, or the picker's footer would describe the
    /// wrong backend.
    @Test func everyKindMapsToItsOwnCapabilities() {
        for kind in BackendKind.allCases {
            #expect(BackendCapabilities.for(kind).kind == kind)
        }
    }

    // MARK: - trustAllCerts (I2)

    /// Every server backend owns its OWN flag. `FilaManService` read
    /// Spoolman's until 2026-08-25, and Spoolman's only writer renders solely
    /// when the backend is Spoolman — so the FilaMan transport consulted a
    /// flag no FilaMan user could set.
    @Test func everyServerBackendHasItsOwnTrustAllCertsKey() {
        let keys = BackendKind.allCases
            .map { BackendCapabilities.for($0) }
            .filter { !$0.isOnDeviceStorage }
            .map(\.trustAllCertsKey)

        #expect(keys.allSatisfy { $0 != nil })
        #expect(Set(keys.compactMap { $0 }).count == keys.count, "two backends share a trust-all key")
    }

    /// On-device storage has no transport, so there is nothing to trust.
    @Test func onDeviceStorageHasNoTrustAllCertsKeyAndNeverTrusts() {
        #expect(BackendCapabilities.local.trustAllCertsKey == nil)
        #expect(BackendCapabilities.local.trustsAllCerts == false)
    }

    @Test func noServerBackendReadsAnothersTrustAllKey() {
        #expect(BackendCapabilities.spoolman.trustAllCertsKey != BackendCapabilities.filaman.trustAllCertsKey)
    }

    /// Read by capability, never by identity. FilaMan is the only backend with
    /// a location ENTITY, so it is the only one with a row that can carry the
    /// tag's UID — Spoolman's locations are strings on spools and the Library's
    /// are derived. A flag with no consumer is a bug report about its
    /// would-be consumer, so this also pins that the consumer exists.
    @Test func onlyFilaManHasALocationRowThatCanCarryATagUID() {
        #expect(BackendCapabilities.filaman.storesLocationTagUID)
        #expect(!BackendCapabilities.spoolman.storesLocationTagUID)
        #expect(!BackendCapabilities.local.storesLocationTagUID)
    }

    /// Each backend's manufacturer picker lists its own public catalogue —
    /// FilaManDB on FilaMan, SpoolmanDB elsewhere (owner, 2026-10-12).
    @Test func eachBackendNamesItsManufacturerCatalogue() {
        #expect(BackendCapabilities.spoolman.manufacturerCatalog == .spoolmanDB)
        #expect(BackendCapabilities.local.manufacturerCatalog == .spoolmanDB)
        #expect(BackendCapabilities.filaman.manufacturerCatalog == .filamanDB)
        #expect(ManufacturerCatalogSource.spoolmanDB.displayName == "SpoolmanDB")
        #expect(ManufacturerCatalogSource.filamanDB.displayName == "FilaManDB")
    }
}
