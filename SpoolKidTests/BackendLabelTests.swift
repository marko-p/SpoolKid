//
//  BackendLabelTests.swift
//  SpoolKidTests
//
//  Purpose: Printed Spoolman/FilaMan label QR codes — parsing, routing from
//  the camera scanner, and resolution against the backend that printed them.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct BackendLabelTests {
    private func parse(_ payload: String, spoolman: String = "", filaman: String = "") -> BackendLabel? {
        BackendLabel.parse(payload, spoolmanURL: spoolman, filamanURL: filaman)
    }

    // MARK: - Parsing (payloads from the owner's sample labels)

    @Test func spoolmanSchemeNamesSpoolsAndFilaments() {
        #expect(parse("WEB+SPOOLMAN:S-4") == BackendLabel(origin: .spoolman, record: .spool(4)))
        #expect(parse("WEB+SPOOLMAN:F-2") == BackendLabel(origin: .spoolman, record: .filament(2)))
        #expect(parse("web+spoolman:s-5") == BackendLabel(origin: .spoolman, record: .spool(5)))
    }

    @Test func malformedSpoolmanSchemeIsNotALabel() {
        #expect(parse("WEB+SPOOLMAN:X-4") == nil)
        #expect(parse("WEB+SPOOLMAN:S-") == nil)
        #expect(parse("WEB+SPOOLMAN:S-0") == nil)
    }

    @Test func filamanURLOnTheConfiguredHostIsALabel() {
        let label = parse("https://filaman.doma/spools/49", filaman: "https://FilaMan.doma")
        #expect(label == BackendLabel(origin: .filaman, record: .spool(49)))
        #expect(parse("https://filaman.doma/filaments/7", filaman: "filaman.doma:443")
            == BackendLabel(origin: .filaman, record: .filament(7)))
    }

    @Test func filamanFilamentLabelNamesTheFilament() {
        #expect(parse("https://filaman.doma/filaments/177", filaman: "https://filaman.doma")
            == BackendLabel(origin: .filaman, record: .filament(177)))
    }

    @Test func spoolmanURLFormOnTheConfiguredHostIsALabel() {
        let server = "http://192.168.20.31:7912"
        #expect(parse("http://192.168.20.31:7912/spool/show/4", spoolman: server)
            == BackendLabel(origin: .spoolman, record: .spool(4)))
        #expect(parse("http://192.168.20.31:7912/filament/show/2", spoolman: server)
            == BackendLabel(origin: .spoolman, record: .filament(2)))
    }

    @Test func urlOnAnotherHostOrPortStaysAWebURL() {
        #expect(parse("https://shop.example/spools/49", filaman: "https://filaman.doma") == nil)
        #expect(parse("https://filaman.doma/spools/49") == nil)
        #expect(parse("http://192.168.20.31:8000/spool/show/4", spoolman: "http://192.168.20.31:7912") == nil)
        #expect(parse("https://filaman.doma/about", filaman: "https://filaman.doma") == nil)
    }

    // MARK: - Camera routing

    @Test func scannerRoutesALabelToTheHub() {
        let action = TagsTabView.smartScannerAction(for: .qr("WEB+SPOOLMAN:S-4"), spoolmanURL: "", filamanURL: "")
        guard case .scanHub(let result) = action else {
            Issue.record("expected the hub, got \(action)")
            return
        }
        #expect(result.format == .backendLabel)
        #expect(result.backendLabel == BackendLabel(origin: .spoolman, record: .spool(4)))
        #expect(result.cardUID == nil)
    }

    @Test func arbitrationAcceptsASpoolmanSchemeLabel() {
        let decision = SmartScanArbitrationService.decide(
            qrCandidate: SmartScanQRCodeCandidate(payload: "WEB+SPOOLMAN:F-2", confidence: 1.0),
            ocrCandidate: nil, elapsed: 0
        )
        guard case .acceptQR("WEB+SPOOLMAN:F-2") = decision else {
            Issue.record("expected the label to win, got \(decision)")
            return
        }
    }

    // MARK: - Resolution

    private let filament = Filament(id: 2, name: "Silk GOLD 18K", material: "PLA")

    private func resolve(_ label: BackendLabel, in writer: MockMigrationWriter) async -> ScanResolutionService.Resolution {
        var scan = ScanResult(cardUID: nil, tagData: nil, format: .backendLabel)
        scan.backendLabel = label
        // Neither mode: a label resolves whatever the identity mode.
        return await ScanResolutionService(
            repository: writer,
            spoolmanDBService: SpoolmanDBService.shared,
            webParserService: WebSpoolParserService.shared,
            identity: TagIdentityPolicy(mode: .neither, linkTargets: []),
            ledger: makeIsolatedLedger()
        ).resolve(scan, effectiveTagData: nil)
    }

    @Test func aSpoolLabelResolvesToItsSpoolInEveryMode() async {
        let spool = Spool(id: 4, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)
        let writer = MockMigrationWriter(serverFilaments: [filament], serverSpools: [spool])
        let result = await resolve(BackendLabel(origin: .spoolman, record: .spool(4)), in: writer)
        guard case .authoritativeSpool(let resolved) = result else {
            Issue.record("expected the spool, got \(result)")
            return
        }
        #expect(resolved.id == 4)
    }

    @Test func aFilamentLabelResolvesToItsFilament() async {
        let writer = MockMigrationWriter(serverFilaments: [filament])
        let result = await resolve(BackendLabel(origin: .spoolman, record: .filament(2)), in: writer)
        guard case .filamentTag(let resolved) = result else {
            Issue.record("expected the filament, got \(result)")
            return
        }
        #expect(resolved.id == 2)
    }

    @Test func aLabelFromAnotherBackendIsNotLookedUp() async {
        let spool = Spool(id: 49, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)
        let writer = MockMigrationWriter(serverSpools: [spool], capabilities: .spoolman)
        let result = await resolve(BackendLabel(origin: .filaman, record: .spool(49)), in: writer)
        guard case .backendLabelProblem(.otherBackend(.filaman)) = result else {
            Issue.record("expected otherBackend, got \(result)")
            return
        }
    }

    @Test func aMissingRecordSaysSo() async {
        let writer = MockMigrationWriter(capabilities: .filaman)
        let result = await resolve(BackendLabel(origin: .filaman, record: .spool(49)), in: writer)
        guard case .backendLabelProblem(.notFound(.spool(49))) = result else {
            Issue.record("expected notFound, got \(result)")
            return
        }
    }

    @Test func problemMessagesNameTheBackends() {
        let other = ScanResultHubView.backendLabelProblemMessage(.otherBackend(.spoolman), capabilities: .filaman)
        #expect(other.contains("printed by Spoolman") && other.contains("using FilaMan"))
        let missing = ScanResultHubView.backendLabelProblemMessage(.notFound(.filament(2)), capabilities: .spoolman)
        #expect(missing.contains("Filament #2") && missing.contains("Spoolman"))
    }
}
