//
//  ManufacturerCatalogServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Catalogue manufacturer names — de-duplication, FilaManDB
//  pagination, the session cache, and switching catalogues.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

/// Serves FilaManDB pages from memory and records which were asked for.
@MainActor
private final class FakeFilaManDB {
    var pages: [Int: Data] = [:]
    var calls: [Int] = []
    /// Throws on the first N calls, then serves.
    var failuresLeft = 0
    /// Throws a `CancellationError` on the first N calls, before any failure.
    var cancellationsLeft = 0
    /// While true, `page` waits for `release()` before answering.
    var holdsPages = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var askedWaiters: [CheckedContinuation<Void, Never>] = []

    /// Returns once `page` has been called at least once.
    func waitUntilAsked() async {
        if !calls.isEmpty { return }
        await withCheckedContinuation { askedWaiters.append($0) }
    }

    /// The FilaManDB client over this fake: each request is answered by the
    /// page its `page` query asks for.
    var catalog: FilaManDBCatalog {
        FilaManDBCatalog(fetch: { url in
            let number = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 0
            return try await self.page(number)
        })
    }

    func release() {
        holdsPages = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    func page(_ number: Int) async throws -> Data {
        calls.append(number)
        let asked = askedWaiters
        askedWaiters = []
        for continuation in asked { continuation.resume() }
        if holdsPages {
            await withCheckedContinuation { held.append($0) }
        }
        if cancellationsLeft > 0 {
            cancellationsLeft -= 1
            throw CancellationError()
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.notConnectedToInternet)
        }
        guard let data = pages[number] else { throw URLError(.badServerResponse) }
        return data
    }

    /// `items`: name and `is_active` (nil leaves the key out).
    static func json(_ items: [(String, Bool?)], total: Int) -> Data {
        let rows = items.map { name, active in
            if let active { return "{\"id\":1,\"name\":\"\(name)\",\"is_active\":\(active)}" }
            return "{\"id\":1,\"name\":\"\(name)\"}"
        }
        return Data("{\"items\":[\(rows.joined(separator: ","))],\"total\":\(total),\"page\":1,\"page_size\":200}".utf8)
    }
}

@MainActor
struct ManufacturerCatalogServiceTests {
    private func dbFilament(_ manufacturer: String) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: UUID().uuidString, manufacturer: manufacturer, name: "PLA", material: "PLA",
            spoolType: nil, density: 1.24, weight: 1000, spoolWeight: nil, diameter: 1.75,
            colorHex: nil, extruderTemp: nil, bedTemp: nil
        )
    }

    /// An on-device repository: it serves no catalogue of its own, so
    /// `SpoolmanDBService` falls back to the injected public one.
    private func makeBackend() throws -> LocalRepository {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LocalRepository(context: ModelContext(container))
    }

    /// A service over `fake`'s FilaManDB, loaded once.
    private func loaded(_ fake: FakeFilaManDB) async throws -> ManufacturerCatalogService {
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { [] }),
            filamanDB: fake.catalog
        )
        await service.load(source: .filamanDB, backend: try makeBackend())
        return service
    }

    @Test func loadReadsPagesUntilTotalAndDropsInactive() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true), ("Gone", false)], total: 3)
        fake.pages[2] = FakeFilaManDB.json([("Elegoo", nil)], total: 3)

        let service = try await loaded(fake)

        #expect(service.names == ["Elegoo", "Sunlu"])
        #expect(!service.didFail)
        #expect(fake.calls == [1, 2])
    }

    @Test func loadStopsOnAnEmptyPage() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true)], total: 50)
        fake.pages[2] = FakeFilaManDB.json([], total: 50)

        let service = try await loaded(fake)

        #expect(service.names == ["Sunlu"])
        #expect(fake.calls == [1, 2])
    }

    @Test func loadStopsAfterTwentyPages() async throws {
        let fake = FakeFilaManDB()
        for number in 1...30 { fake.pages[number] = FakeFilaManDB.json([("Brand\(number)", true)], total: 10_000) }

        let service = try await loaded(fake)

        #expect(service.names.count == 20)
        #expect(fake.calls.count == 20)
    }

    @Test func aRowWithoutANameIsSkipped() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = Data(
            #"{"items":[{"id":1,"name":null,"is_active":true},{"id":2,"name":"Sunlu","is_active":true}],"total":2,"page":1,"page_size":200}"#.utf8
        )

        let service = try await loaded(fake)

        #expect(service.names == ["Sunlu"])
        #expect(fake.calls == [1])
    }

    @Test func aFailingPageFailsTheLoad() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true)], total: 2)
        // No page 2: the fake throws.

        let service = try await loaded(fake)

        #expect(service.didFail)
        #expect(service.names.isEmpty)
    }

    @Test func filaManDBIsFetchedOncePerSession() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true), ("Elegoo", true)], total: 2)
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { [] }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        await service.load(source: .filamanDB, backend: backend)
        await service.load(source: .filamanDB, backend: backend)

        #expect(service.names == ["Elegoo", "Sunlu"])
        #expect(!service.didFail)
        #expect(fake.calls == [1])
    }

    /// An empty answer is not worth keeping for the session: the next
    /// picker asks again.
    @Test func anEmptyResultIsNotCached() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([], total: 0)
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { [] }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        await service.load(source: .filamanDB, backend: backend)
        await service.load(source: .filamanDB, backend: backend)

        #expect(service.names.isEmpty)
        #expect(!service.didFail)
        #expect(fake.calls == [1, 1])
    }

    @Test func aFailedFilaManDBFetchIsRetriedNextTime() async throws {
        let fake = FakeFilaManDB()
        fake.failuresLeft = 1
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true)], total: 1)
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { [] }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        await service.load(source: .filamanDB, backend: backend)
        #expect(service.didFail)
        #expect(service.names.isEmpty)

        await service.load(source: .filamanDB, backend: backend)
        #expect(!service.didFail)
        #expect(service.names == ["Sunlu"])
    }

    /// A picker that closes mid-load cancels it: that is not a failure, and
    /// nothing is kept, so the next picker fetches again.
    @Test func aCancelledFilaManDBLoadIsNotAFailure() async throws {
        let fake = FakeFilaManDB()
        fake.cancellationsLeft = 1
        fake.pages[1] = FakeFilaManDB.json([("Sunlu", true)], total: 1)
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { [] }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        await service.load(source: .filamanDB, backend: backend)
        #expect(!service.didFail)
        #expect(service.names.isEmpty)

        await service.load(source: .filamanDB, backend: backend)
        #expect(service.names == ["Sunlu"])
        #expect(!service.didFail)
        #expect(fake.calls == [1, 1])
    }

    @Test func spoolmanDBNamesComeFromTheFilamentCatalogue() async throws {
        let catalogue = [dbFilament("Sunlu"), dbFilament("sunlu "), dbFilament("Elegoo")]
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { catalogue }),
            filamanDB: FilaManDBCatalog(fetch: { _ in throw URLError(.badURL) })
        )

        let backend = try makeBackend()
        await service.load(source: .spoolmanDB, backend: backend)

        #expect(service.names == ["Elegoo", "Sunlu"])
        #expect(!service.didFail)
    }

    @Test func switchingBackendsSwitchesCatalogues() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Rosa3D", true)], total: 1)
        let catalogue = [dbFilament("Sunlu")]
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { catalogue }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        await service.load(source: .filamanDB, backend: backend)
        #expect(service.names == ["Rosa3D"])
        await service.load(source: .spoolmanDB, backend: backend)
        #expect(service.names == ["Sunlu"])
        await service.load(source: .filamanDB, backend: backend)
        #expect(service.names == ["Rosa3D"])
        #expect(fake.calls == [1])
    }

    /// A picker opened on another backend while a load is still running gets
    /// that backend's catalogue, not the running load's.
    @Test func aLoadForAnotherSourceSupersedesTheRunningOne() async throws {
        let fake = FakeFilaManDB()
        fake.pages[1] = FakeFilaManDB.json([("Rosa3D", true)], total: 1)
        fake.holdsPages = true
        let catalogue = [dbFilament("Sunlu")]
        let service = ManufacturerCatalogService(
            spoolmanDB: SpoolmanDBService(publicCatalog: { catalogue }),
            filamanDB: fake.catalog
        )
        let backend = try makeBackend()

        let slow = Task { await service.load(source: .filamanDB, backend: backend) }
        await fake.waitUntilAsked()
        await service.load(source: .spoolmanDB, backend: backend)
        fake.release()
        await slow.value

        #expect(service.names == ["Sunlu"])
        #expect(!service.isLoading)
        #expect(!service.didFail)
    }
}
