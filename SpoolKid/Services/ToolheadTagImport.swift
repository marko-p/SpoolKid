//
//  ToolheadTagImport.swift
//  SpoolKid
//
//  Purpose: A tag the U1's own reader read (MIFARE Classic included, which
//  the iPhone can't), turned into what the Library needs to add or link it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum ToolheadTagImport {
    nonisolated enum Offer: Equatable, Sendable {
        case none
        /// No spool claims the tag, and the printer counts usage into the
        /// app's backend: Add Spool and Link to Spool are offered.
        case unlinked(uid: String)
        /// A spool claims it; the sheet's big action is Assign Spool.
        case linked(spoolID: Int)
    }

    /// A tag a filament or a location holds is left alone (one tag, one
    /// owner). Server-down greying is the view's, through `ServerLink`.
    static func offer(for toolhead: ToolheadState, owner: TagOwner, route: PrinterUsageRoute?, supportsTagMapping: Bool, writesLinks: Bool) -> Offer {
        guard let uid = toolhead.tagUID else { return .none }
        switch owner {
        case .spool(let id, _): return .linked(spoolID: id)
        case .filament, .location: return .none
        // Without tag links (Spool ID mode, Neither) a new spool would be
        // saved without its tag and the offer would come back.
        case .none: return route != nil && supportsTagMapping && writesLinks ? .unlinked(uid: uid) : .none
        }
    }

    /// Nil without a decoded tag. What the printer didn't report is left
    /// for the forms' own defaults; temperatures it didn't report are
    /// placeholders marked not stated, as OpenSpool's are.
    static func tagData(from toolhead: ToolheadState) -> FilamentTagData? {
        guard let tag = toolhead.tag, let first = tag.colorHexes.first else { return nil }
        let nozzle = range(tag.hotendMinTemp, tag.hotendMaxTemp)
        let bed = tag.bedTemp
        var data = FilamentTagData(
            material: tag.material,
            subtype: tag.subtype,
            brand: tag.vendor ?? "Generic",
            colorHex: first,
            additionalColorHexes: tag.colorHexes.count > 1 ? Array(tag.colorHexes.dropFirst()) : nil,
            minNozzleTemp: nozzle?.min ?? 200,
            maxNozzleTemp: nozzle?.max ?? 220,
            minBedTemp: bed ?? 60,
            maxBedTemp: bed ?? 80,
            diameter: tag.diameter,
            nominalNetWeight: tag.weight,
            colorAlpha: tag.alpha < FilamentOpacity.opaque ? tag.alpha : nil
        )
        data.nozzleTempsStated = nozzle != nil
        data.bedTempsStated = bed != nil
        return data
    }

    /// The offer for a toolhead as the app sees it now.
    static func offer(for toolhead: ToolheadState, printer: PrinterService, store: SpoolDataStore) -> Offer {
        offer(
            for: toolhead, owner: toolhead.tagUID.map { store.owner(ofTagUID: $0) } ?? .none,
            route: printer.usageRoute(connectionTarget: store.connectionTarget),
            supportsTagMapping: store.capabilities.supportsTagMapping,
            writesLinks: store.tagIdentity.writesLinks
        )
    }

    nonisolated enum AddStart: Equatable, Sendable {
        case newFilament
        case spool(filamentID: Int)
        case filamentSearch
    }

    /// Where Add Spool opens. A tag without filament data opens the filament
    /// search, never a form holding the last-used filament.
    static func addStart(tagData: FilamentTagData?, filaments: [Filament]) -> AddStart {
        guard let tagData else { return .filamentSearch }
        return filament(for: tagData, in: filaments).map { .spool(filamentID: $0.id) } ?? .newFilament
    }

    /// The spools Link to Spool lists first, best first and each once: a
    /// medium match or better. The picker lists the rest of the Library below.
    static func linkMatches(for tag: FilamentTagData, in spools: [Spool]) -> [FilamentMatchResult] {
        var seen = Set<Int>()
        return FilamentMatchService.rank(tag: tag, spools: spools).filter { result in
            result.confidence >= 60 && seen.insert(result.spool.id).inserted
        }
    }

    /// The backend filament Add Spool reuses: the same vendor and material
    /// (any case), the same subtype when the tag names one (the filament's
    /// `variant`), the same number of colours, each one "looks the same"
    /// (ΔE2000 < 2, the planner's band). The closest wins; nil means a new
    /// filament is made from the tag.
    static func filament(for tag: FilamentTagData, in filaments: [Filament]) -> Filament? {
        let tagHexes = [tag.colorHex] + (tag.additionalColorHexes ?? [])
        func same(_ a: String?, _ b: String) -> Bool { (a ?? "").caseInsensitiveCompare(b) == .orderedSame }
        return filaments.compactMap { filament -> (Filament, Double)? in
            guard same(filament.vendor?.name, tag.brand), same(filament.material, tag.material) else { return nil }
            if let subtype = tag.subtype, !same(filament.variant, subtype) { return nil }
            let hexes = filament.colors.hexes
            guard hexes.count == tagHexes.count else { return nil }
            var worst = 0.0
            for (a, b) in zip(hexes, tagHexes) {
                guard let labA = ColorMatching.lab(from: a), let labB = ColorMatching.lab(from: b) else { return nil }
                worst = max(worst, ColorMatching.deltaE2000(labA, labB))
            }
            return worst < 2 ? (filament, worst) : nil
        }
        .min { $0.1 < $1.1 }?.0
    }

    private static func range(_ min: Int?, _ max: Int?) -> (min: Int, max: Int)? {
        guard let lower = min ?? max, let upper = max ?? min else { return nil }
        return (lower, upper)
    }
}
