//
//  SpoolmanDBServiceTests.swift
//  SpoolKidTests
//
//  Tests for SpoolmanDBService: the configured Spoolman's own catalogue first,
//  the public one as fallback, and a reload when the server address changes.
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

    private func makeService(_ publicCatalog: PublicCatalog) -> SpoolmanDBService {
        SpoolmanDBService(publicCatalog: { try publicCatalog.load() })
    }

    @Test func serverCatalogueWinsOverThePublicOne() async {
        let publicCatalog = PublicCatalog()
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: "http://spoolman") { [Self.forkEntry] }

        #expect(service.filaments == [Self.forkEntry])
        #expect(publicCatalog.loads == 0)
    }

    /// A Spoolman that never synced its catalogue must not cost the user the
    /// public one they had before.
    @Test func failedServerCatalogueFallsBackToThePublicOne() async {
        let service = makeService(PublicCatalog())

        await service.fetchFilaments(for: "http://spoolman") { throw Boom() }

        #expect(service.filaments == [Self.publicEntry])
        #expect(service.errorMessage == nil)
    }

    @Test func bothCataloguesFailingReportsAnError() async {
        let publicCatalog = PublicCatalog()
        publicCatalog.result = .failure(Boom())
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: "http://spoolman") { throw Boom() }

        #expect(service.filaments.isEmpty)
        #expect(service.errorMessage != nil)
        #expect(service.isLoading == false)
    }

    @Test func sameServerLoadsOnce() async {
        let publicCatalog = PublicCatalog()
        let service = makeService(publicCatalog)

        await service.fetchFilaments(for: "http://spoolman") { throw Boom() }
        await service.fetchFilaments(for: "http://spoolman") { throw Boom() }

        #expect(publicCatalog.loads == 1)
    }

    @Test func changedServerAddressReloads() async {
        let service = makeService(PublicCatalog())

        await service.fetchFilaments(for: "http://a") { throw Boom() }
        #expect(service.filaments == [Self.publicEntry])

        await service.fetchFilaments(for: "http://b") { [Self.forkEntry] }

        #expect(service.filaments == [Self.forkEntry])
    }

    /// One entry exactly as Spoolman 0.23.1 serves `GET /api/v1/external/filament`:
    /// explicit nulls, plus keys SpoolKid does not read.
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
