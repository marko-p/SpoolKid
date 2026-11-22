//
//  SpoolmanDBServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Covers where SpoolmanDBService loads the catalogue from — the
//  active backend's own, else the public one — and when it reloads.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolmanDBServiceTests {
    private struct Boom: Error {}

    private static func entry(_ id: String) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: id, manufacturer: "Maker", name: id, material: "PLA",
            spoolType: nil, density: 1.24, weight: 1000, spoolWeight: nil, diameter: 1.75,
            colorHex: nil, extruderTemp: nil, bedTemp: nil
        )
    }

    private static let publicEntry = entry("public")
    private static let forkEntry = entry("fork")

    /// Stands in for the public catalogue's download, counting its loads.
    @MainActor
    private final class PublicCatalog {
        var result: Result<[SpoolmanDBFilament], Error> = .success([SpoolmanDBServiceTests.publicEntry])
        private(set) var loads = 0
        func load() throws -> [SpoolmanDBFilament] {
            loads += 1
            return try result.get()
        }
    }

    /// A public catalogue whose first load waits for `release()`, and whose
    /// later loads answer at once — two loads that overlap, as when a second
    /// screen asks for the catalogue while the first is still downloading.
    @MainActor
    private final class OverlappingCatalog {
        var first: Result<[SpoolmanDBFilament], Error>
        var second: Result<[SpoolmanDBFilament], Error>
        private(set) var loads = 0
        private var gate: CheckedContinuation<Void, Never>?
        private var heldWaiters: [CheckedContinuation<Void, Never>] = []

        init(first: Result<[SpoolmanDBFilament], Error>, second: Result<[SpoolmanDBFilament], Error>) {
            self.first = first
            self.second = second
        }

        /// Returns once the first load is waiting at the gate.
        func waitUntilHeld() async {
            if gate != nil { return }
            await withCheckedContinuation { heldWaiters.append($0) }
        }

        func release() {
            gate?.resume()
            gate = nil
        }

        func load() async throws -> [SpoolmanDBFilament] {
            loads += 1
            if loads == 1 {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    let waiting = heldWaiters
                    heldWaiters = []
                    for waiter in waiting { waiter.resume() }
                }
                return try first.get()
            }
            return try second.get()
        }
    }

    private func makeService(_ publicCatalog: PublicCatalog) -> SpoolmanDBService {
        SpoolmanDBService(publicCatalog: { try publicCatalog.load() })
    }

    @Test func backendCatalogueWinsOverThePublicOne() async {
        let backend = MockMigrationWriter()
        backend.filamentCatalogResult = .success([Self.forkEntry])
        let publicCatalog = PublicCatalog()
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: backend)

        #expect(service.filaments == [Self.forkEntry])
        #expect(publicCatalog.loads == 0)
    }

    @Test func backendWithoutACatalogueUsesThePublicOne() async {
        let backend = MockMigrationWriter(capabilities: .local)
        let service = makeService(PublicCatalog())

        await service.fetchFilaments(for: backend)

        #expect(service.filaments == [Self.publicEntry])
    }

    /// Owner's call (2026-10-04): a Spoolman that never synced its catalogue
    /// must not cost the user the public one they had before.
    @Test func failedBackendCatalogueFallsBackToThePublicOne() async {
        let backend = MockMigrationWriter()
        backend.filamentCatalogResult = .failure(Boom())
        let service = makeService(PublicCatalog())

        await service.fetchFilaments(for: backend)

        #expect(service.filaments == [Self.publicEntry])
        #expect(service.errorMessage == nil)
    }

    @Test func bothCataloguesFailingReportsAnError() async {
        let backend = MockMigrationWriter()
        backend.filamentCatalogResult = .failure(Boom())
        let publicCatalog = PublicCatalog()
        publicCatalog.result = .failure(Boom())
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: backend)

        #expect(service.filaments.isEmpty)
        #expect(service.errorMessage != nil)
        #expect(service.isLoading == false)
    }

    /// A screen that closes cancels its load; that is not a failure to show.
    @Test func aCancelledLoadIsNotAnError() async {
        for cancellation in [CancellationError() as Error, URLError(.cancelled)] {
            let backend = MockMigrationWriter()
            backend.filamentCatalogResult = .failure(cancellation)
            let publicCatalog = PublicCatalog()
            publicCatalog.result = .failure(cancellation)
            let service = makeService(publicCatalog)

            await service.fetchFilaments(for: backend)

            #expect(service.filaments.isEmpty)
            #expect(service.errorMessage == nil)
            #expect(service.isLoading == false)
        }
    }

    /// Two loads overlap: one fails while the other, started first, is still
    /// downloading. When that one succeeds the catalogue is there, so no
    /// error stays up beside it.
    @Test func aSuccessfulLoadClearsAnEarlierError() async {
        let backend = MockMigrationWriter()
        let catalog = OverlappingCatalog(first: .success([Self.publicEntry]), second: .failure(Boom()))
        let service = SpoolmanDBService(publicCatalog: { try await catalog.load() })

        let slow = Task { await service.fetchFilaments(for: backend) }
        await catalog.waitUntilHeld()
        await service.fetchFilaments(for: backend)
        #expect(service.errorMessage != nil)

        catalog.release()
        await slow.value

        #expect(service.filaments == [Self.publicEntry])
        #expect(service.errorMessage == nil)
    }

    /// The same overlap the other way round: the failure lands after the
    /// catalogue loaded. A later call finds the catalogue loaded, returns
    /// early, and takes the stale error down with it — its Retry works.
    @Test func aLoadedCatalogueClearsAStaleError() async {
        let backend = MockMigrationWriter()
        let catalog = OverlappingCatalog(first: .failure(Boom()), second: .success([Self.publicEntry]))
        let service = SpoolmanDBService(publicCatalog: { try await catalog.load() })

        let slow = Task { await service.fetchFilaments(for: backend) }
        await catalog.waitUntilHeld()
        await service.fetchFilaments(for: backend)
        catalog.release()
        await slow.value
        #expect(service.filaments == [Self.publicEntry])
        #expect(service.errorMessage != nil)

        await service.fetchFilaments(for: backend)

        #expect(service.errorMessage == nil)
        #expect(catalog.loads == 2)
    }

    @Test func sameBackendLoadsOnce() async {
        let backend = MockMigrationWriter(capabilities: .local)
        let publicCatalog = PublicCatalog()
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: backend)
        await service.fetchFilaments(for: backend)

        #expect(publicCatalog.loads == 1)
    }

    /// A backend switch, or a retyped server address, changes the connection
    /// target — and with it which catalogue applies.
    @Test func changedConnectionTargetReloads() async {
        let backend = MockMigrationWriter()
        backend.connectionTarget = "spoolman|http://a"
        let service = makeService(PublicCatalog())

        await service.fetchFilaments(for: backend)
        #expect(service.filaments == [Self.publicEntry])

        backend.connectionTarget = "spoolman|http://b"
        backend.filamentCatalogResult = .success([Self.forkEntry])
        await service.fetchFilaments(for: backend)

        #expect(service.filaments == [Self.forkEntry])
    }

    /// One entry exactly as Spoolman 0.23.1 serves `GET /api/v1/external/filament`
    /// (probed 2026-10-04): explicit nulls, plus keys SpoolKid does not read.
    @Test func decodesSpoolmansServedShape() throws {
        let json = #"""
        [{"id": "3d-fuel_pla+_almond_1000_175_n", "manufacturer": "3D-Fuel", "name": "Almond",
          "material": "PLA+", "density": 1.22, "weight": 1000.0, "spool_weight": 225.0,
          "spool_type": null, "diameter": 1.75, "color_hex": "CFBCAE", "color_hexes": null,
          "extruder_temp": 220, "bed_temp": 60, "finish": null, "multi_color_direction": null,
          "pattern": null, "translucent": false, "glow": false}]
        """#
        let decoded = try JSONDecoder().decode([SpoolmanDBFilament].self, from: Data(json.utf8))

        #expect(decoded.count == 1)
        #expect(decoded.first?.manufacturer == "3D-Fuel")
        #expect(decoded.first?.spoolType == nil)
        #expect(decoded.first?.extruderTemp == 220)
    }
}
