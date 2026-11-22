//
//  HubActionPlan.swift
//  SpoolKid
//
//  Purpose: What the Scan Result Hub offers for one resolved scan — its
//  sections, tiles and ⋯ menu items. Every visibility decision the hub makes
//  lives here, so each approved state is a unit test rather than a device
//  pass.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A hub tile, identified by what it does; the hub maps the id to its action.
nonisolated enum HubTileID: String, Equatable, Sendable {
    case weigh, transferTag, unlink, addAnotherTag, linkTag
    case createNewSpool, spoolsWithFilament, searchSpoolmanDB, revertToTagData
    /// The Spool page's own tiles (2026-11-03); the hub never emits them.
    case writeTag, setLocation
}

extension HubTileID {
    /// Greyed out while the server can't be reached: the tile writes to it.
    var needsServer: Bool {
        switch self {
        case .weigh, .transferTag, .unlink, .addAnotherTag, .linkTag, .createNewSpool, .writeTag, .setLocation:
            return true
        case .spoolsWithFilament, .searchSpoolmanDB, .revertToTagData:
            return false
        }
    }
}

/// An item in the hub's ⋯ menu (D10).
nonisolated enum HubMenuItemID: String, Equatable, Sendable {
    case writeSpoolID, writeSpoolDataOntoTag, cloneTag, inspectTag, emptyTag, reviewScannedData
}

extension HubMenuItemID {
    /// Clone and Empty move or release the tag's links on the server.
    var needsServer: Bool { self == .cloneTag || self == .emptyTag }

    var title: String {
        switch self {
        case .writeSpoolID: return "Write Spool ID to Tag"
        case .writeSpoolDataOntoTag: return "Write a Spool's Data onto This Tag"
        case .cloneTag: return "Clone Tag"
        case .inspectTag: return "Inspect Tag"
        case .emptyTag: return "Empty This Tag…"
        case .reviewScannedData: return "Review Scanned Data"
        }
    }

    var systemImage: String {
        switch self {
        case .writeSpoolID: return "tag"
        case .writeSpoolDataOntoTag: return "square.and.pencil"
        case .cloneTag: return "doc.on.doc"
        case .inspectTag: return "info.circle"
        case .emptyTag: return "eraser"
        case .reviewScannedData: return "text.viewscan"
        }
    }
}

nonisolated struct HubAction: Equatable, Sendable {
    let id: HubTileID
    let title: String
    let systemImage: String
    var isPrimary = false
    var isEnabled = true
    /// A second line under the title (D14). Nil for almost every tile.
    var detail: String? = nil
}

nonisolated enum HubSectionKind: Equatable, Sendable {
    case spool, filament
}

nonisolated struct HubSection: Equatable, Sendable {
    let kind: HubSectionKind
    let tiles: [HubAction]
    /// D8: the Tag / backend switch. Filament section only.
    var showsSourceSwitch = false
}

struct HubActionPlan: Equatable {
    /// Tiles every screen draws the same way, wherever they appear.
    static let createTile = HubAction(id: .createNewSpool, title: "Create New Spool", systemImage: "plus", isPrimary: true)
    static let transferTile = HubAction(id: .transferTag, title: "Transfer Tag", systemImage: "arrow.left.arrow.right")
    static let unlinkTile = HubAction(id: .unlink, title: "Unlink", systemImage: "xmark.circle")

    var spoolSection: HubSection?
    var filamentSection: HubSection?
    var menuItems: [HubMenuItemID]

    struct Input {
        let result: UnifiedScanResult
        let linkState: HubLinkState
        let tagFormat: ScanResult.DetectedFormat?
        let identity: TagIdentityPolicy
        let secondTagState: ScanResultHubView.UIDMappingActionState
        let isSecondTagScanning: Bool
        let workingFilamentId: Int?
        let hasAdoptedFilament: Bool
        let offersClone: Bool
        let offersErase: Bool
        let offersScanReview: Bool
        var offersInspect = false
        /// The catalogue the backend reads, as the search tile names it.
        var catalogName = "SpoolmanDB"
    }

    static func make(_ input: Input) -> HubActionPlan {
        let linkTag = HubAction(id: .linkTag, title: "Link Tag…", systemImage: "link")
        // Creating links follows the mode; Unlink never does (links are read
        // in every mode, so a wrong one must stay removable). Spec §2.
        let offersLinkTag = input.identity.writesLinks && input.linkState.offersLinkTag
        // Outside Tag Links an unlinked tag is claimed by WRITING a spool onto
        // it, so a scan that carried a UID always offers that.
        let claimsByWriting = !input.identity.writesLinks && !(input.result.uid ?? "").isEmpty
        let unlink = unlinkTile
        let create = createTile
        let maintenance = maintenanceItems(
            offersClone: input.offersClone, offersInspect: input.offersInspect, offersErase: input.offersErase
        )

        switch input.result {
        case .spool(let spool, let tagData, _):
            // "Known" means the tag belongs to the spool the hub shows — the
            // only case where Transfer and the tag-move checklist apply.
            var isKnown = false
            if case .mapped(let spoolID, _) = input.linkState { isKnown = spoolID == spool.id }

            // The link action (Unlink or Link Tag) takes the first slot and
            // Weigh the last, in every state (owner, 2026-09-27).
            var tiles: [HubAction] = []
            var menu: [HubMenuItemID] = []
            if isKnown {
                if input.linkState.unlinkSpoolID != nil { tiles.append(unlink) }
                if input.identity.writesLinks {
                    // Only a tag SpoolKid can release can move (I1): an
                    // `rfid_uid` link would stay on this spool.
                    if case .mapped(_, true) = input.linkState {
                        tiles.append(transferTile)
                    }
                    if case .scanSecondTag(let enabled) = input.secondTagState {
                        tiles.append(HubAction(
                            id: .addAnotherTag,
                            title: input.isSecondTagScanning ? "Scanning…" : "Add Another Tag",
                            systemImage: "wave.3.right",
                            isEnabled: enabled
                        ))
                    }
                }
                if shouldShowWriteSpoolIdButton(
                    result: input.result, tagFormat: input.tagFormat, writeSpoolIdEnabled: input.identity.writesSpoolID
                ) {
                    menu.append(.writeSpoolID)
                }
            } else {
                if offersLinkTag { tiles.append(linkTag) }
                if input.linkState.unlinkSpoolID != nil { tiles.append(unlink) }
                menu.append(.writeSpoolDataOntoTag)
            }
            tiles.append(HubAction(id: .weigh, title: "Weigh", systemImage: "scalemass"))
            return HubActionPlan(
                spoolSection: HubSection(kind: .spool, tiles: tiles),
                filamentSection: HubSection(kind: .filament, tiles: [create], showsSourceSwitch: tagData != nil),
                menuItems: menu + maintenance
            )

        case .filament:
            var spoolSection: HubSection?
            if shouldShowMapToExistingSpoolButton(result: input.result) {
                var tiles: [HubAction] = []
                if offersLinkTag { tiles.append(linkTag) }
                if input.linkState.unlinkSpoolID != nil { tiles.append(unlink) }
                if !tiles.isEmpty { spoolSection = HubSection(kind: .spool, tiles: tiles) }
            }
            var tiles = [create]
            tiles.append(input.workingFilamentId != nil
                ? HubAction(id: .spoolsWithFilament, title: "Spools with This Filament", systemImage: "shippingbox")
                : HubAction(id: .searchSpoolmanDB, title: "Search \(input.catalogName)", systemImage: "magnifyingglass"))
            if input.hasAdoptedFilament {
                tiles.append(HubAction(id: .revertToTagData, title: "Revert to Tag Data", systemImage: "arrow.uturn.backward"))
            }
            // Review Scanned Data is offered only here because every OCR scan
            // resolves to `.filament` (no UID).
            return HubActionPlan(
                spoolSection: spoolSection,
                filamentSection: HubSection(kind: .filament, tiles: tiles),
                menuItems: (claimsByWriting ? [.writeSpoolDataOntoTag] : [])
                    + (input.offersScanReview ? [.reviewScannedData] : []) + maintenance
            )

        case .uidOnly:
            var tiles = [create]
            if offersLinkTag { tiles.append(linkTag) }
            if input.linkState.unlinkSpoolID != nil { tiles.append(unlink) }
            return HubActionPlan(
                spoolSection: HubSection(kind: .spool, tiles: tiles),
                filamentSection: nil,
                menuItems: (claimsByWriting ? [.writeSpoolDataOntoTag] : []) + maintenance
            )
        }
    }

    /// Clone, Inspect, then Empty: the destructive item always comes last (D10).
    nonisolated static func maintenanceItems(
        offersClone: Bool, offersInspect: Bool = false, offersErase: Bool
    ) -> [HubMenuItemID] {
        (offersClone ? [.cloneTag] : []) + (offersInspect ? [.inspectTag] : []) + (offersErase ? [.emptyTag] : [])
    }

    /// The "From Backend" half's two text lines. Swapped mode (an Anycubic
    /// scan) headlines the vendor•material•variant descriptor and puts the
    /// filament's name below it; normal mode reproduces the half's original
    /// rendering exactly, including the "Unknown Filament" fallback.
    static func backendLabels(
        spool: Spool,
        tagData: FilamentTagData?,
        nameBelowDescriptor: Bool
    ) -> (headline: String, secondary: String?) {
        let descriptor = [
            spool.filament.vendor?.name ?? tagData?.brand ?? "Generic",
            spool.filament.material ?? tagData?.material ?? "PLA",
            spool.filament.variant,
        ]
        .joined(separator: " • ")
        let name = spool.filament.name

        if nameBelowDescriptor {
            return (descriptor, name)
        }
        return (name ?? tagData?.displayName ?? "Unknown Filament", descriptor)
    }

    // MARK: - Row text

    /// The spool row's second line: remaining weight, location, and either
    /// how many tags the spool holds or that the scanned tag is not one of them.
    static func spoolRowSubtitle(spool: Spool, scannedUID: String?, isLinked: Bool) -> String {
        var parts: [String] = []
        if let remaining = spool.remainingWeight { parts.append("\(Int(remaining)) g left") }
        if let location = spool.location, !location.isEmpty { parts.append(location) }
        if scannedUID == nil || isLinked {
            let count = spool.mappedCardUIDs.count
            if count > 0 { parts.append(count == 1 ? "1 tag" : "\(count) tags") }
        } else {
            parts.append("this tag isn't linked")
        }
        return parts.joined(separator: " · ")
    }

    /// The Spool row when the scan resolved to no spool. It names the spool
    /// that holds the tag rather than guessing why resolution passed it by:
    /// it used to say "an archived spool", which was false the moment the
    /// hub's own Create or Link Tag wrote the tag (final review, 2026-09-27).
    nonisolated static func unresolvedSpoolRowTitle(linkState: HubLinkState, spools: [Spool]) -> String {
        let spoolID: Int
        switch linkState {
        case .notLinked:
            return "No spool uses this tag"
        case .mapped(let id, _), .ledger(let id):
            spoolID = id
        }
        guard let spool = spools.first(where: { $0.id == spoolID }) else { return "Linked to a spool" }
        return "Linked to \(spool.listTitle)"
    }

    /// D8: the tag disagrees with the backend on material, colour or brand.
    /// A field is compared only when both sides have it; the name never is,
    /// because names differ across ecosystems for the same filament.
    static func tagDiffers(tagData: FilamentTagData, filament: Filament) -> Bool {
        func differ(_ a: String?, _ b: String?) -> Bool {
            let lhs = a?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rhs = b?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !lhs.isEmpty, !rhs.isEmpty else { return false }
            return lhs.caseInsensitiveCompare(rhs) != .orderedSame
        }
        return differ(tagData.material, filament.material)
            || differ(ColorMatching.normalize(tagData.colorHex), ColorMatching.normalize(filament.colors.primaryHex))
            || differ(tagData.brand, filament.vendor?.name)
    }

    // MARK: - Gates for tag-mapping buttons

    /// Whether the `.filament` scenario should offer to map the scanned tag
    /// to an existing spool. True only for a scan that actually carried a UID
    /// (NFC — not QR, a URL, or OCR) on a backend that can store the mapping.
    /// `.spool` and `.uidOnly` render their own mapping buttons and are not
    /// this helper's business.
    ///
    /// Which tiles it holds follows the identity mode (spec §2); an empty
    /// section is not shown.
    nonisolated static func shouldShowMapToExistingSpoolButton(
        result: UnifiedScanResult
    ) -> Bool {
        guard case .filament(_, _, let scannedUID) = result else { return false }
        return !(scannedUID ?? "").isEmpty
    }

    // MARK: - Explanations (D6) and footer (D13)

    /// One line per tile shown, then how to edit. Today's captions, moved into
    /// the section's (i) popover. `unlinkTargetTitle` is the spool Unlink
    /// releases, which is not always the spool the section shows: an
    /// embedded-ID scan can display one spool while its tag is linked to
    /// another.
    static func infoLines(
        for section: HubSection, spoolTitle: String?, unlinkTargetTitle: String?, backendName: String,
        filamentRowCreates: Bool, offersFilamentTargets: Bool = false, catalogName: String = "SpoolmanDB"
    ) -> [String] {
        var lines = section.tiles.map { tile -> String in
            switch tile.id {
            case .weigh:
                return "Weigh — Update this spool's remaining weight from your scale."
            case .transferTag:
                return offersFilamentTargets
                    ? "Transfer Tag — Move this tag to another spool or a filament. You choose which of this spool's tags move."
                    : "Transfer Tag — Move this tag to another spool. You choose which of this spool's tags move."
            case .unlink:
                return "Unlink — Remove this tag from \(unlinkTargetTitle ?? "its spool") in \(backendName). Nothing on the tag is erased."
            case .linkTag:
                return offersFilamentTargets
                    ? "Link Tag — Record this tag against a spool or a filament in \(backendName). The tag itself is not written to."
                    : "Link Tag — Record this tag against a spool in \(backendName). The tag itself is not written to."
            case .addAnotherTag:
                return "Add Another Tag — Link one more tag to this spool, for example the one on its other side."
            case .createNewSpool:
                return section.kind == .spool
                    ? "Create New Spool — Create a spool and link this tag to it."
                    : "Create New Spool — Create a spool of this filament. If this tag belongs to a spool, you choose which tags move to the new one."
            case .spoolsWithFilament:
                return "Spools with This Filament — List the spools in \(backendName) that use this filament."
            case .searchSpoolmanDB:
                return "Search \(catalogName) — Find this filament in the \(catalogName) catalogue and start a spool from it."
            case .revertToTagData:
                return "Revert to Tag Data — Show the tag's values again. The filament you saved stays in \(backendName)."
            case .writeTag:
                return "Write Tag — Write this spool onto a tag."
            case .setLocation:
                return "Location — Put this spool on a shelf, by scanning its location tag or choosing from the list."
            }
        }
        if section.showsSourceSwitch {
            lines.append("Tag / \(backendName) — Switch between what the tag says and what \(backendName) has. \"Tag differs\" means the material, colour or brand disagree.")
        }
        switch section.kind {
        case .spool:
            if spoolTitle != nil { lines.append("Tap the spool to edit it.") }
        case .filament:
            lines.append(filamentRowCreates
                ? "Tap the filament to save it to \(backendName)."
                : "Tap the filament to edit it.")
        }
        return lines
    }

    /// A tag linked to a filament (spec 4; layout 2026-10-11): the filament's
    /// own section, with the tiles the other sections use. Transfer only where
    /// links are written; Unlink wherever the backend keeps filament links,
    /// in every mode.
    static func filamentTagSection(canTransfer: Bool, canUnlink: Bool) -> HubSection {
        var tiles = [createTile]
        if canTransfer { tiles.append(transferTile) }
        if canUnlink { tiles.append(unlinkTile) }
        return HubSection(kind: .filament, tiles: tiles)
    }

    /// The filament-tag section's (i) lines.
    static func filamentTagInfoLines(
        for section: HubSection, filamentTitle: String, backendName: String, offersFilamentTargets: Bool = false
    ) -> [String] {
        var lines = ["This tag identifies this filament."]
        for tile in section.tiles {
            switch tile.id {
            case .createNewSpool:
                lines.append("Create New Spool — Create a spool of this filament. The tag stays with the filament.")
            case .transferTag:
                lines.append(offersFilamentTargets
                    ? "Transfer Tag — Move this tag from the filament to a spool or another filament."
                    : "Transfer Tag — Move this tag from the filament to a spool.")
            case .unlink:
                lines.append("Unlink — Remove this tag from \(filamentTitle) in \(backendName). Nothing on the tag is erased.")
            default:
                break
            }
        }
        lines.append("Tap the filament to edit it, or a spool below to edit that spool.")
        return lines
    }

    /// D13: the footer's second part — how the hub found its answer.
    /// `backendName` names the backend a record-only hit is not linked on.
    nonisolated static func footerResolutionPart(
        _ source: ScanResultHubView.HubResolutionSource?, backendName: String
    ) -> String? {
        switch source {
        // Any link: `card_uids`, Spoolman Tags or the Library's Tags.
        case .spoolLinkMapping: return "found by its tag link"
        case .embeddedSpoolID: return "found by the spool ID on the tag"
        case .onDeviceLedger: return "found only by this iPhone's record of this tag, not linked on \(backendName)"
        case .spoolIDMigration: return "linked using the spool ID on the tag"
        case .backendLabel: return "found by its printed label"
        case .manualChoice: return "spool chosen by you"
        case .heuristicMatch, nil: return nil
        }
    }

    static func shouldShowWriteSpoolIdButton(
        result: UnifiedScanResult,
        tagFormat: ScanResult.DetectedFormat?,
        writeSpoolIdEnabled: Bool
    ) -> Bool {
        guard case .spool(_, let tagData, _) = result else { return false }
        guard writeSpoolIdEnabled else { return false }
        guard tagFormat == .openSpool else { return false }
        guard tagData?.spoolmanId == nil else { return false }
        return true
    }
}
