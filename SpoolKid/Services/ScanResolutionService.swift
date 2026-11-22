//
//  ScanResolutionService.swift
//  SpoolKid
//
//  Purpose: Owns the scan resolution cascade — determines what a scan result
//  maps to (authoritative spool, UID-mapped spool, heuristic matches, unknown
//  tag, or no-match fallback). Runs against any SpoolDataRepository (backend-
//  agnostic). Extracted from ScanResultHubView per spec 010; migrated to the
//  repository per spec 051.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "ScanResolution")

@MainActor
class ScanResolutionService {

    /// How a mapping-tier hit was stored. `cardUIDs` is the SpoolLink
    /// `card_uids` field; `onDeviceLedger` is SpoolKid's own UID→spool record,
    /// reached only on a `card_uids` miss.
    /// `nonisolated` so the hub's nonisolated caption helpers can compare it.
    nonisolated enum CardUIDResolutionSource: Equatable, Sendable {
        case cardUIDs
        case onDeviceLedger
        /// Linked during this scan from the spool ID on the tag (Tag Links, spec §3).
        case spoolIDMigration
    }

    enum Resolution {
        case authoritativeSpool(Spool)
        case cardUIDSpool(Spool, source: CardUIDResolutionSource)
        case matchResults([FilamentMatchResult])
        case unknownTag
        case noMatch
        case needsWebChallenge(URL)
        case parsedWebData(FilamentTagData)
        /// Tag Links: the tag carries a spool ID whose spool's filament
        /// differs (or the automatic link failed). `otherwise` is what the
        /// scan resolves to without it — heuristics only; the ledger is not
        /// asked, because the card is the answer.
        indirect case spoolIDMismatch(SpoolIDMismatch, otherwise: Resolution)
        /// Spec 4: the tag is linked to a filament type.
        case filamentTag(Filament)
        /// A printed backend label that names nothing here.
        case backendLabelProblem(BackendLabelProblem)
    }

    /// Why a printed label resolved to nothing. Never a guess: a label's ID
    /// is looked up only in the backend that printed it.
    nonisolated enum BackendLabelProblem: Equatable, Sendable {
        /// Printed by a backend other than the active one.
        case otherBackend(BackendLabel.Origin)
        /// Printed here, but no such record exists (deleted, or another server).
        case notFound(BackendLabel.Record)
    }

    enum NewSpoolSource: Identifiable {
        case local(Filament)
        case spoolmanDB(SpoolmanDBFilament)

        var id: String {
            switch self {
            case .local(let filament):
                return "local-\(filament.id)"
            case .spoolmanDB(let filament):
                return "db-\(filament.id)"
            }
        }
    }

    /// How the catalogue answered a candidate load, so the list can say so
    /// instead of reading a missing answer as "nothing found".
    nonisolated enum CatalogueAnswer: Equatable {
        /// The catalogue was asked and replied, or the ask was cancelled (its
        /// list is gone, so there is nothing to tell).
        case answered
        /// Nothing to ask: the tag has no brand, or FilaManDB lists no such
        /// manufacturer.
        case noBrand
        /// The catalogue was asked and did not reply.
        case failed
    }

    /// The candidates for the list, and how the catalogue answered. The local
    /// candidates stand in every case.
    struct CandidateLoad {
        let candidates: [NewSpoolSource]
        let catalogue: CatalogueAnswer
    }

    enum SpoolIDMigrationStep {
        case skip
        case link(Spool)
        case ask(SpoolIDMismatch)
    }

    /// Tag Links only (the caller checks): what the spool ID on an unlinked
    /// tag leads to. Matching uses the hub's "tag differs" rule — material,
    /// colour, brand; never the name — the same one `staleSpoolID` uses.
    static func spoolIDMigrationStep(
        tagData: FilamentTagData?, uid: String?, activeSpools: [Spool], owner: TagOwner
    ) -> SpoolIDMigrationStep {
        guard let tagData, let id = tagData.spoolmanId,
              let uid, !SpoolMappingService.normalizeUID(uid).isEmpty,
              owner == .none,
              let spool = activeSpools.first(where: { $0.id == id })
        else { return .skip }
        guard HubActionPlan.tagDiffers(tagData: tagData, filament: spool.filament) else { return .link(spool) }
        return .ask(SpoolIDMismatch(spool: spool, tagData: tagData, linkError: nil))
    }

    private let repository: any SpoolDataRepository
    /// What the last `findOrCreateFilament` CREATE succeeded with but could not
    /// fully do (e.g. "TD was not saved: …"); nil after a match or a clean
    /// create. The caller posts it — a success must not hide it.
    private(set) var lastCreateCaveat: String?
    private let spoolmanDBService: SpoolmanDBService
    private let webParserService: WebSpoolParserService
    private let identity: TagIdentityPolicy
    private let ledger: TagAssociationStore
    private let filamanDB: FilaManDBCatalog

    init(
        repository: any SpoolDataRepository,
        spoolmanDBService: SpoolmanDBService,
        webParserService: WebSpoolParserService,
        identity: TagIdentityPolicy,
        ledger: TagAssociationStore = .shared,
        filamanDB: FilaManDBCatalog = .live
    ) {
        self.repository = repository
        self.spoolmanDBService = spoolmanDBService
        self.webParserService = webParserService
        self.identity = identity
        self.ledger = ledger
        self.filamanDB = filamanDB
    }

    func resolve(
        _ scan: ScanResult,
        effectiveTagData: FilamentTagData?
    ) async -> Resolution {
        if let label = scan.backendLabel {
            return await resolve(label)
        }

        if scan.format == .webUrl, let url = scan.url, effectiveTagData == nil {
            do {
                if let parsed = try await webParserService.parse(url: url) {
                    WorkflowTraceStore.log(path: "hub", step: "resolve.web-parsed", details: [
                        "url": url.absoluteString
                    ])
                    return .parsedWebData(parsed)
                } else {
                    return .unknownTag
                }
            } catch WebSpoolParserError.requiresWebChallenge(let challengeUrl) {
                return .needsWebChallenge(challengeUrl)
            } catch {
                logger.error("Failed to parse web URL spool data: \(error.localizedDescription, privacy: .public)")
                return .unknownTag
            }
        }

        let tagData = effectiveTagData ?? scan.tagData

        WorkflowTraceStore.log(path: "hub", step: "resolve.backend-state", details: [
            "spoolCount": String(repository.spools.count),
            "filamentCount": String(repository.filaments.count)
        ])

        if let mapped = await mappedSpool(scan, tagData: tagData) {
            return mapped
        }

        return await heuristicResolution(scan, tagData: tagData)
    }

    /// A printed label: its record in the backend that printed it, in every
    /// identity mode — the ID is the backend's own, not something on a tag.
    private func resolve(_ label: BackendLabel) async -> Resolution {
        guard label.origin == repository.capabilities.labelOrigin else {
            return .backendLabelProblem(.otherBackend(label.origin))
        }
        switch label.record {
        case .spool(let id):
            if !repository.spools.contains(where: { $0.id == id }) { await repository.fetchSpools() }
            if let spool = repository.spools.first(where: { $0.id == id }) { return .authoritativeSpool(spool) }
        case .filament(let id):
            if !repository.filaments.contains(where: { $0.id == id }) { await repository.fetchFilaments() }
            if let filament = repository.filaments.first(where: { $0.id == id }) { return .filamentTag(filament) }
        }
        return .backendLabelProblem(.notFound(label.record))
    }

    /// What a scan resolves to when no stored mapping claims it: the heuristic
    /// ranking, then the uid-only and no-match tails. Extracted from `resolve`
    /// so the spool-ID mismatch can carry it as `otherwise`.
    private func heuristicResolution(_ scan: ScanResult, tagData: FilamentTagData?) async -> Resolution {
        if let td = tagData {
            if repository.spools.isEmpty {
                await repository.fetchSpools()
            }
            if repository.filaments.isEmpty {
                await repository.fetchFilaments()
            }

            let ranked = FilamentMatchService.rank(tag: td, spools: repository.activeSpools)
            let top = ranked.prefix(5).map { "\($0.spool.id):\($0.confidence)" }.joined(separator: ",")
            WorkflowTraceStore.log(path: "hub", step: "resolve.heuristic-ranked", details: [
                "material": td.material,
                "brand": td.brand,
                "name": td.name ?? "",
                "tagColorHex": td.colorHex,
                "spoolsEvaluated": String(repository.spools.count),
                "topCandidates": top
            ])
            if !ranked.isEmpty {
                WorkflowTraceStore.log(path: "hub", step: "resolve.heuristic-hit", details: [
                    "topSpoolId": String(ranked[0].spool.id),
                    "topConfidence": String(ranked[0].confidence)
                ])
                return .matchResults(ranked)
            }
        }

        if scan.cardUID != nil, tagData == nil {
            WorkflowTraceStore.log(path: "hub", step: "resolve.uid-only", details: [
                "uid": scan.cardUID ?? ""
            ])
            return .unknownTag
        }

        WorkflowTraceStore.log(path: "hub", step: "resolve.no-match")
        return .noMatch
    }

    /// The stored-identity tiers in the order `identity.effectiveMode` gives
    /// them — spec §3 — and nothing else. Which tiers run, and in what order,
    /// follows `identity`: a spool id written on the tag counts only in Spool
    /// ID mode, while a link and the on-device ledger resolve in every mode.
    /// `nil` means no stored mapping claims this tag; it does NOT mean the tag
    /// is unknown, only that answering needs a guess (a heuristic filament
    /// match, a web page).
    ///
    /// Extracted from `resolve` so `resolveMappedSpool` can offer exactly these
    /// tiers without the rest, rather than a second copy of the same cascade.
    private func mappedSpool(
        _ scan: ScanResult,
        tagData: FilamentTagData?
    ) async -> Resolution? {
        if identity.honorsSpoolID, let spool = await embeddedSpool(scan, tagData: tagData) {
            return .authoritativeSpool(spool)
        }
        if let linked = await linkedSpool(scan) { return linked }
        if let filament = await linkedFilament(scan) { return .filamentTag(filament) }
        if identity.effectiveMode == .tagLinks, let migrated = await migrateSpoolID(scan, tagData: tagData) {
            return migrated
        }
        return await ledgerSpool(scan)
    }

    /// Tier: the spool ID written on the tag. Spool ID mode only.
    private func embeddedSpool(_ scan: ScanResult, tagData: FilamentTagData?) async -> Spool? {
        guard let spoolId = tagData?.spoolmanId else { return nil }
        await repository.fetchSpools()
        // Ignore archived spools when resolving a scan — they surface only in
        // the Manage Spools "Show Archived" list, never as scan results.
        guard let spool = repository.activeSpools.first(where: { $0.id == spoolId }) else { return nil }
        if let uid = scan.cardUID { ledger.record(uid: uid, spoolId: spool.id) }
        WorkflowTraceStore.log(path: "hub", step: "resolve.authoritative-hit", details: [
            "spoolId": String(spool.id)
        ])
        return spool
    }

    /// Tier: a link (Spoolman Tags, `card_uids`). Every mode.
    private func linkedSpool(_ scan: ScanResult) async -> Resolution? {
        guard let uid = scan.cardUID else { return nil }
        if repository.spools.isEmpty {
            await repository.fetchSpools()
        }
        // findSpool searches the full set (card_uid is single-owner even for
        // archived spools); skip the hit if that owner is archived.
        guard let spool = repository.findSpool(byCardUID: uid), spool.archived != true else { return nil }
        repairTagStoresIfNeeded(uid: uid, spool: spool)
        ledger.record(uid: uid, spoolId: spool.id)
        WorkflowTraceStore.log(path: "hub", step: "resolve.uid-hit", details: [
            "uid": uid,
            "spoolId": String(spool.id)
        ])
        return .cardUIDSpool(spool, source: .cardUIDs)
    }

    /// Tier (spec 4): a filament link — Spoolman 0.27's own filament tags or
    /// the Library's. After spool links, because a spool's claim is what a
    /// printer resolves. Every mode.
    private func linkedFilament(_ scan: ScanResult) async -> Filament? {
        guard let uid = scan.cardUID else { return nil }
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return nil }
        if repository.filaments.isEmpty {
            await repository.fetchFilaments()
        }
        guard let filament = repository.filaments.first(where: { $0.mappedTagUIDs.contains(normalized) }) else {
            return nil
        }
        WorkflowTraceStore.log(path: "hub", step: "resolve.filament-tag", details: [
            "uid": normalized,
            "filamentId": String(filament.id)
        ])
        return filament
    }

    /// Tag Links: link a spool-ID tag to its spool when the filament matches
    /// (awaited — the scan resolves as linked only if the link landed), or
    /// hand the hub the mismatch. `nil` when the step does not apply.
    ///
    /// A double is not a `SpoolDataStore`: it has no owners (`.none`), and
    /// the link — the one step that writes — needs the facade, so `.ask`
    /// works against a double and `.link` does not.
    private func migrateSpoolID(_ scan: ScanResult, tagData: FilamentTagData?) async -> Resolution? {
        guard let tagData else { return nil }
        let store = repository as? SpoolDataStore
        let owner = scan.cardUID.flatMap { store?.owner(ofTagUID: $0) } ?? .none
        switch Self.spoolIDMigrationStep(
            tagData: tagData, uid: scan.cardUID, activeSpools: repository.activeSpools, owner: owner
        ) {
        case .skip:
            return nil
        case .link(let spool):
            guard let store, let uid = scan.cardUID else { return nil }
            let outcome = await TagLinkService.assign(uid, to: spool, in: store, personInitiated: false)
            WorkflowTraceStore.log(path: "hub", step: "resolve.spool-id-migration", details: [
                "spoolId": String(spool.id), "linked": String(outcome.didWrite)
            ])
            guard outcome.didWrite else {
                let mismatch = SpoolIDMismatch(
                    spool: spool, tagData: tagData,
                    linkError: outcome.failure ?? "The tag could not be linked to \(spool.listTitle)."
                )
                return .spoolIDMismatch(mismatch, otherwise: await heuristicResolution(scan, tagData: tagData))
            }
            let linked = repository.spools.first { $0.id == spool.id } ?? spool
            ledger.record(uid: uid, spoolId: linked.id)
            return .cardUIDSpool(linked, source: .spoolIDMigration)
        case .ask(let mismatch):
            return .spoolIDMismatch(mismatch, otherwise: await heuristicResolution(scan, tagData: tagData))
        }
    }

    /// Tier: the on-device ledger (G15), only on a link miss — a UID the local
    /// ledger knows resolves to its recorded spool when the links didn't. A
    /// link always wins (this is only reached on a link miss). Archived owners
    /// are skipped. Every mode; identifies, never links.
    private func ledgerSpool(_ scan: ScanResult) async -> Resolution? {
        guard let uid = scan.cardUID else { return nil }
        if repository.spools.isEmpty {
            await repository.fetchSpools()
        }
        let norm = SpoolMappingService.normalizeUID(uid)
        guard let spoolId = ledger.snapshot()[norm],
              let spool = repository.activeSpools.first(where: { $0.id == spoolId })
        else { return nil }
        WorkflowTraceStore.log(path: "hub", step: "resolve.ledger-hit", details: [
            "uid": norm, "spoolId": String(spool.id)
        ])
        return .cardUIDSpool(spool, source: .onDeviceLedger)
    }

    /// The spool a stored mapping claims, WITHOUT the web fetch.
    ///
    /// `resolve` answers a web-URL tag by fetching and
    /// parsing the page BEFORE it reaches any of the tiers above, so a tag
    /// already mapped to a spool still paid for a network round trip to a
    /// third-party site, and paid it again on the second pass. On the bench
    /// that was a visible wait against an OpenSpool tag's instant answer
    /// (owner, 2026-09-05).
    ///
    /// A stored mapping is authoritative and a parsed web page is a guess, so
    /// asking in that order is also the more correct sequence. Callers that
    /// need the tag's CONTENT — the hub, which offers to write that data —
    /// still want the parse, which is why `resolve` keeps its order rather than
    /// this becoming the one true path.
    func resolveMappedSpool(_ scan: ScanResult) async -> Spool? {
        switch await mappedSpool(scan, tagData: scan.tagData) {
        case .authoritativeSpool(let spool), .cardUIDSpool(let spool, _): return spool
        default: return nil
        }
    }

    // MARK: - Repair

    /// paxx12-parity repair on a native-tag server: copy the link into any
    /// target store that lacks it and drop stale `card_uids` copies
    /// elsewhere. Background: the scan's answer does not wait on it.
    ///
    /// `TagLinkService` needs the facade (owner checks, refresh), and every
    /// live resolver is built with `repository: store`; a test double simply
    /// gets no repair.
    private func repairTagStoresIfNeeded(uid: String, spool: Spool) {
        let available = repository.availableTagStores
        let targets = identity.linkTargets
        guard identity.writesLinks, TagWriteTargets.needsRepair(
            uid: uid, resolved: spool, spools: repository.spools, targets: targets, available: available
        ), let store = repository as? SpoolDataStore else { return }
        WorkflowTraceStore.log(path: "hub", step: "resolve.tag-store-heal", details: [
            "uid": uid,
            "spoolId": String(spool.id)
        ])
        Task { _ = await TagLinkService.assign(uid, to: spool, in: store, personInitiated: false) }
    }

    func parseWebChallengeHTML(_ html: String, url: URL) throws -> FilamentTagData {
        try webParserService.parse(html: html, url: url)
    }

    /// Candidates for the "Search ‹catalogue› for Similar Filaments" list (the
    /// catalogue is SpoolmanDB, or FilaManDB on FilaMan) — scored local
    /// filaments and catalogue entries, best first — and how the catalogue
    /// answered. Deliberately NOT used to preselect anything: since 2026-09-09
    /// a scanned filament's spool creation finds-or-creates parents from the
    /// tag data instead, so a heuristic suggestion can no longer decide the
    /// preselection. The list calls this when it opens, not the hub on every
    /// resolve: on FilaMan it is up to fifteen requests.
    func newSpoolSourceCandidates(for tagData: FilamentTagData) async -> CandidateLoad {
        let catalogue = await catalogueEntries(for: tagData)
        var scored: [(source: NewSpoolSource, score: Int)] = []

        scored.append(contentsOf: repository.filaments.compactMap { filament in
            let score = FilamentMatchService.scoreFilament(
                tag: tagData,
                name: filament.name,
                material: filament.material,
                brand: filament.vendor?.name,
                colorHexes: filament.colors.hexes
            )
            guard score > 0 else { return nil }
            return (.local(filament), score)
        })

        scored.append(contentsOf: catalogue.entries.compactMap { filament in
            let score = FilamentMatchService.scoreFilament(
                tag: tagData,
                name: filament.name,
                material: filament.material,
                brand: filament.manufacturer,
                colorHexes: filament.colors.hexes
            )
            guard score > 0 else { return nil }
            return (.spoolmanDB(filament), score)
        })

        scored.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.source.id < rhs.source.id }
            return lhs.score > rhs.score
        }

        return CandidateLoad(candidates: scored.map { $0.source }, catalogue: catalogue.answer)
    }

    /// The most pages of one brand's FilaManDB filaments read (200 rows each);
    /// the largest brand, SUNLU, has 979 filaments, 5 pages.
    private static let filamanDBMaxPages = 10

    /// The catalogue entries worth scoring against `tagData`, by the
    /// backend's catalogue: SpoolmanDB's whole list, or on FilaMan the tag
    /// brand's FilaManDB filaments (the SpoolmanDB list is not used there, so
    /// it is not downloaded), and how the catalogue answered. A blank or
    /// unknown brand, or a catalogue that fails, leaves no entries — the local
    /// candidates still stand.
    private func catalogueEntries(
        for tagData: FilamentTagData
    ) async -> (entries: [SpoolmanDBFilament], answer: CatalogueAnswer) {
        switch repository.capabilities.manufacturerCatalog {
        case .spoolmanDB:
            await spoolmanDBService.fetchFilaments(for: repository)
            // `fetchFilaments` clears the message when it starts, so a message
            // now is this fetch's.
            return (spoolmanDBService.filaments, spoolmanDBService.errorMessage == nil ? .answered : .failed)
        case .filamanDB:
            do {
                guard let manufacturerID = try await filamanDB.manufacturerID(named: tagData.brand) else {
                    return ([], .noBrand)
                }
                let entries = try await filamanDB.filaments(
                    manufacturerID: manufacturerID, maxPages: Self.filamanDBMaxPages
                )
                return (entries, .answered)
            } catch {
                // A closed list cancels its lookup: not a failure.
                if error.isCancellation { return ([], .answered) }
                logger.error("FilaManDB candidates failed: \(error.localizedDescription, privacy: .public)")
                return ([], .failed)
            }
        }
    }

    // MARK: - Filament identity (find-or-create)

    /// The repository filament that IS the scanned one: same vendor, same
    /// material, same colour. Name is deliberately ignored — names differ
    /// across ecosystems for the same physical filament, and a heuristic
    /// near-match deciding a preselection is exactly the bug this seam
    /// replaces (owner, 2026-09-09).
    ///
    /// Colors: an exact ordered match wins. Failing that, when the tag was
    /// read from a known `format` and holds exactly that format's color
    /// capacity, it may have been truncated on write, so a filament whose
    /// LEADING colors equal the tag's matches too (a 2-color filament written
    /// to an ACE tag, a 4-color one to TigerTag). Without a format the scan
    /// cannot tell, and only the exact rule applies.
    nonisolated static func findExistingFilament(
        tagData: FilamentTagData,
        filaments: [Filament],
        format: TagFormat? = nil
    ) -> Filament? {
        // The tag's valid colors, RGB, in order. Two or more make a multi-color
        // identity, compared as the same ordered list.
        let tagColors = tagData.trimmedColors(max: FilamentColors.maxEditableColors)
        let sameProduct = filaments.filter { filament in
            guard let vendorName = filament.vendor?.name,
                  ManufacturerName.key(vendorName) == ManufacturerName.key(tagData.brand)
            else { return false }
            guard let material = filament.material,
                  material.localizedCaseInsensitiveCompare(tagData.material) == .orderedSame
            else { return false }
            return true
        }
        func rgbColors(_ filament: Filament) -> [String] {
            filament.colors.hexes.compactMap { hex in
                FilamentColors.normalizedHex(hex).map { String($0.prefix(6)) }
            }
        }
        let exact = sameProduct.first { filament in
            if tagColors.count >= 2 { return rgbColors(filament) == tagColors }
            // A single-color tag never matches a multi-color filament.
            guard !filament.colors.isMulti else { return false }
            return ColorMatching.normalize(filament.colors.primaryHex)
                == ColorMatching.normalize(tagData.colorHex)
        }
        if let exact { return exact }
        guard let format, !tagColors.isEmpty, tagColors.count == format.maxColors else { return nil }
        return sameProduct.first { Array(rgbColors($0).prefix(tagColors.count)) == tagColors }
    }

    /// Find-or-create the scanned filament's parents in the active backend:
    /// the filament if the identity above matches, otherwise a vendor from
    /// the tag's brand and then the filament from the tag data. Returns nil
    /// when a needed create failed — the caller reports that, never a
    /// success for work that did not happen.
    func findOrCreateFilament(for tagData: FilamentTagData, format: TagFormat? = nil) async -> Filament? {
        lastCreateCaveat = nil
        if repository.filaments.isEmpty {
            await repository.fetchFilaments()
        }
        if let existing = Self.findExistingFilament(
            tagData: tagData, filaments: repository.filaments, format: format
        ) {
            return existing
        }

        let brand = tagData.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        var vendorId: Int?
        if !brand.isEmpty {
            if repository.vendors.isEmpty {
                await repository.fetchVendors()
            }
            if let vendor = ManufacturerName.vendor(named: brand, in: repository.vendors) {
                vendorId = vendor.id
            } else if let created = await repository.addVendor(name: brand) {
                vendorId = created.id
            } else {
                // A filament created anyway would be a manufacturer-less
                // stand-in for the scanned one, reported as found.
                return nil
            }
        }

        // A tag's colors: one, or several for a multi-color spool (Coextruded).
        // Only valid colors, so one junk extra cannot cost the primary.
        let color = FilamentColors(
            hexes: tagData.trimmedColors(max: FilamentColors.maxEditableColors)
        ).draftFields(loaded: nil)
        let draft = FilamentDraft(
            name: Self.filamentName(from: tagData),
            vendorId: vendorId.map { SpoolmanPatchValue.set($0) } ?? .ignore,
            material: tagData.material,
            // ACE, ELEGOO and OpenSpool tags carry no density, but Spoolman
            // refuses a create without one: the material's typical density,
            // else the same PLA default the form seeds.
            density: FilamentTagData.statedMeasurement(tagData.density)
                ?? TigerTagRegistry.materialDensity(for: tagData.material)
                ?? AppConfig.Defaults.density,
            // FilaMan refuses a create without a diameter: the tag's
            // (OpenPrintTag states one), else the 1.75 mm every form seeds.
            diameter: FilamentTagData.statedMeasurement(tagData.diameter) ?? AppConfig.Defaults.diameter,
            // The product's nominal net weight, not this spool's actual fill.
            weight: FilamentTagData.statedMeasurement(tagData.nominalNetWeight).map { .set($0) } ?? .ignore,
            // A Prusament tag knows its own spool; the catalogue only knows the name.
            spoolWeight: FilamentTagData.statedMeasurement(tagData.emptyContainerWeight).map { .set($0) } ?? .ignore,
            // The form seeds temps the same way; a tag stating none leaves them
            // unset, as Spoolman and the Library allow.
            extruderTemp: tagData.statedExtruderTemp.map { .set($0) } ?? .ignore,
            bedTemp: tagData.statedBedTemp.map { .set($0) } ?? .ignore,
            colorHex: color.colorHex,
            multiColorHexes: color.multiColorHexes,
            multiColorDirection: color.multiColorDirection,
            // Only a filament created here takes the tag's TD; a matched one
            // keeps its own.
            transmissionDistance: tagData.transmissionDistance
                .flatMap { TransmissionDistance.isValid($0) ? .set(TransmissionDistance.rounded($0)) : nil } ?? .ignore
        )
        let created = await repository.addFilament(draft: draft)
        if created != nil { lastCreateCaveat = repository.errorMessage }
        return created
    }

    /// The same name the filament form seeds from tag data, with a
    /// material+subtype fallback for tags that carry none (brand is NOT part
    /// of a filament name — the vendor holds it, per the 044 naming rule).
    nonisolated static func filamentName(from tagData: FilamentTagData) -> String? {
        if let name = tagData.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let parts = [tagData.material, tagData.subtype]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func importDBFilamentIfNeeded(_ dbFilament: SpoolmanDBFilament) async -> Filament? {
        let existing = repository.filaments.first { filament in
            ManufacturerName.key(filament.vendor?.name ?? "") == ManufacturerName.key(dbFilament.manufacturer)
            && (filament.name ?? "").localizedCaseInsensitiveCompare(dbFilament.name) == .orderedSame
            && (filament.material ?? "").localizedCaseInsensitiveCompare(dbFilament.material) == .orderedSame
        }
        if let existing { return existing }

        var vendorId = ManufacturerName.vendor(named: dbFilament.manufacturer, in: repository.vendors)?.id

        if vendorId == nil {
            if let newVendor = await repository.addVendor(name: dbFilament.manufacturer) {
                vendorId = newVendor.id
            } else {
                return nil
            }
        }

        guard let finalVendorId = vendorId else { return nil }

        let draft = dbFilament.filamentDraft(vendorId: finalVendorId)

        let imported = await repository.addFilament(draft: draft)
        return imported
    }
}

/// A spool-ID tag the hub must ask about (spec §3).
struct SpoolIDMismatch: Sendable {
    let spool: Spool
    let tagSummary: String
    let spoolSummary: String
    let linkError: String?

    init(spool: Spool, tagData: FilamentTagData, linkError: String?) {
        self.init(
            spool: spool,
            tagSummary: Self.summary(brand: tagData.brand, material: tagData.material, colorHex: tagData.colorHex),
            spoolSummary: Self.summary(
                brand: spool.filament.vendor?.name, material: spool.filament.material, colorHex: spool.filament.colors.primaryHex
            ),
            linkError: linkError
        )
    }

    private init(spool: Spool, tagSummary: String, spoolSummary: String, linkError: String?) {
        self.spool = spool
        self.tagSummary = tagSummary
        self.spoolSummary = spoolSummary
        self.linkError = linkError
    }

    func withLinkError(_ message: String) -> SpoolIDMismatch {
        SpoolIDMismatch(spool: spool, tagSummary: tagSummary, spoolSummary: spoolSummary, linkError: message)
    }

    /// "Elegoo PLA · #FF0000".
    nonisolated static func summary(brand: String?, material: String?, colorHex: String?) -> String {
        let name = [brand, material]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard let hex = ColorMatching.normalize(colorHex) else { return name }
        return name.isEmpty ? "#\(hex)" : "\(name) · #\(hex)"
    }
}
