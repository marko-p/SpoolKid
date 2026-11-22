//
//  HubActionPlanTests.swift
//  SpoolKidTests
//
//  One test per approved hub state (spec 2026-09-27, "States") and per gate.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct HubActionPlanTests {
    private static let filament = Filament(
        id: 10, name: "BROWN", material: "PLA", vendor: Vendor(id: 1, name: "AzureFilm"),
        colorHex: "B58548", density: 1.24
    )
    private static let uid = "048B1356C92A81"
    nonisolated static let links = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs])
    nonisolated static let spoolIDMode = TagIdentityPolicy(mode: .spoolID, linkTargets: [])
    nonisolated static let neither = TagIdentityPolicy(mode: .neither, linkTargets: [])

    private static func spool(cardUIDs: [String] = [], remaining: Double? = nil, rfidUID: String? = nil) -> Spool {
        Spool(
            id: 53, filament: filament, remainingWeight: remaining,
            extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            rfidUID: rfidUID, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    private static func tag(spoolmanId: Int? = nil) -> FilamentTagData {
        FilamentTagData(
            name: "BROWN", material: "PLA", subtype: "Basic", brand: "AzureFilm", colorHex: "B58548",
            minNozzleTemp: 200, maxNozzleTemp: 230, minBedTemp: 50, maxBedTemp: 60, spoolmanId: spoolmanId
        )
    }

    private func plan(
        _ result: UnifiedScanResult,
        link: HubLinkState = .notLinked,
        format: ScanResult.DetectedFormat? = .openSpool,
        identity: TagIdentityPolicy = HubActionPlanTests.links,
        secondTag: ScanResultHubView.UIDMappingActionState = .none,
        scanning: Bool = false,
        workingFilamentId: Int? = nil,
        adopted: Bool = false,
        clone: Bool = true,
        erase: Bool = true,
        review: Bool = false,
        inspect: Bool = false,
        catalogName: String = "SpoolmanDB"
    ) -> HubActionPlan {
        HubActionPlan.make(.init(
            result: result, linkState: link, tagFormat: format, identity: identity, secondTagState: secondTag,
            isSecondTagScanning: scanning, workingFilamentId: workingFilamentId,
            hasAdoptedFilament: adopted, offersClone: clone, offersErase: erase, offersScanReview: review,
            offersInspect: inspect, catalogName: catalogName
        ))
    }

    private func ids(_ section: HubSection?) -> [HubTileID] { section?.tiles.map(\.id) ?? [] }

    // MARK: - State 1 · known tag

    @Test func knownTag() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true)
        )
        #expect(ids(p.spoolSection) == [.unlink, .transferTag, .weigh])
        #expect(ids(p.filamentSection) == [.createNewSpool])
        #expect(p.filamentSection?.showsSourceSwitch == true)
        #expect(p.menuItems == [.cloneTag, .emptyTag])
    }

    /// Spool ID mode: the tag can take the spool's ID, but nothing links.
    @Test func knownTagInSpoolIDMode() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            identity: Self.spoolIDMode,
            secondTag: .scanSecondTag(enabled: true)
        )
        #expect(ids(p.spoolSection) == [.unlink, .weigh])
        #expect(p.menuItems == [.writeSpoolID, .cloneTag, .emptyTag])
    }

    @Test func knownTagInNeitherModeOffersOnlyUnlinkAndWeigh() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            identity: Self.neither,
            secondTag: .scanSecondTag(enabled: true)
        )
        #expect(ids(p.spoolSection) == [.unlink, .weigh])
        #expect(p.menuItems == [.cloneTag, .emptyTag])
    }

    @Test func knownTagJustLinkedOffersAnotherTag() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            secondTag: .scanSecondTag(enabled: true)
        )
        #expect(ids(p.spoolSection) == [.unlink, .transferTag, .addAnotherTag, .weigh])
    }

    @Test func anotherTagWaitsWhileAScanRuns() throws {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            secondTag: .scanSecondTag(enabled: false), scanning: true
        )
        let tile = try #require(p.spoolSection?.tiles.first { $0.id == .addAnotherTag })
        #expect(tile.title == "Scanning…")
        #expect(!tile.isEnabled)
    }

    /// A tag linked only through a field SpoolKid cannot write (FilaMan's
    /// `rfid_uid`) can be neither unlinked nor moved (I1, 2026-09-27).
    @Test func aMappingSpoolKidCannotReleaseOffersNoUnlinkOrTransfer() {
        let p = plan(
            .spool(Self.spool(), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: false)
        )
        #expect(ids(p.spoolSection) == [.weigh])
    }

    /// The same, for a tag in `card_uids` AND `rfid_uid` — resolved through
    /// `HubLinkState` rather than stated, so the chain from spool to tiles is
    /// what is pinned (final review FR-3).
    @Test func aDoubleMappedTagOffersNoUnlinkOrTransfer() {
        let spool = Self.spool(cardUIDs: [Self.uid], rfidUID: Self.uid)
        let link = HubLinkState.resolve(uid: Self.uid, resolvedViaLedger: false, spools: [spool], ledger: [:])
        let p = plan(.spool(spool, Self.tag(), scannedUID: Self.uid), link: link)
        #expect(ids(p.spoolSection) == [.weigh])
        #expect(ScanResultHubView.tagMoveOffer(for: .spool(spool, Self.tag(), scannedUID: Self.uid)) == nil)
    }

    /// Final review P-2: a native link wins over a stale `card_uids` copy on
    /// another spool, as in scan resolution.
    @Test func aNativeLinkWinsOverAStaleCardUIDsCopy() {
        let stale = Spool(
            id: 7, filament: Self.spool().filament,
            extra: ["card_uids": CardUIDsCodec.encode([Self.uid])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        let native = Spool(
            id: 8, filament: Self.spool().filament,
            statusId: nil, externalId: nil, purchaseDate: nil, nativeTagUIDs: [Self.uid]
        )
        let link = HubLinkState.resolve(uid: Self.uid, resolvedViaLedger: false, spools: [stale, native], ledger: [:])
        #expect(link == .mapped(spoolID: 8, releasable: true))
        #expect(SpoolMappingService.spool(in: [stale, native], claiming: Self.uid)?.id == 8)
    }

    @Test func writeSpoolIDOnlyWhenTheTagLacksOne() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(spoolmanId: 53), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            identity: Self.spoolIDMode
        )
        #expect(!p.menuItems.contains(.writeSpoolID))
    }

    // MARK: - State 2 · unknown tag carrying a spool ID

    @Test func unknownTagCarryingASpoolID() {
        let p = plan(.spool(Self.spool(), Self.tag(spoolmanId: 53), scannedUID: "04AABBCCDDEE01"))
        #expect(ids(p.spoolSection) == [.linkTag, .weigh])
        #expect(ids(p.filamentSection) == [.createNewSpool])
        #expect(p.menuItems == [.writeSpoolDataOntoTag, .cloneTag, .emptyTag])
    }

    /// Issue #24: only this iPhone's record knows the tag, so nothing on the
    /// backend links it — Link Tag, not Unlink.
    @Test func aLedgerOnlyHitOffersLinkNotUnlink() {
        let p = plan(
            .spool(Self.spool(), Self.tag(), scannedUID: "04AABBCCDDEE01"),
            link: .ledger(spoolID: 53)
        )
        #expect(ids(p.spoolSection) == [.linkTag, .weigh])
    }

    /// An embedded-ID scan can show spool 53 while its tag is linked to spool
    /// 99. The tag is not the shown spool's, so there is nothing to transfer;
    /// Unlink releases spool 99's claim.
    @Test func aTagLinkedToAnotherSpoolIsNotTheShownSpoolsTag() {
        let p = plan(
            .spool(Self.spool(), Self.tag(spoolmanId: 53), scannedUID: "04AABBCCDDEE01"),
            link: .mapped(spoolID: 99, releasable: true)
        )
        #expect(ids(p.spoolSection) == [.unlink, .weigh])
        #expect(p.menuItems.first == .writeSpoolDataOntoTag)
    }

    // MARK: - State 3 · tag with filament data only

    @Test func filamentOnlyWithALibraryMatch() {
        let p = plan(.filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"), workingFilamentId: 10)
        #expect(ids(p.spoolSection) == [.linkTag])
        #expect(ids(p.filamentSection) == [.createNewSpool, .spoolsWithFilament])
        #expect(p.filamentSection?.showsSourceSwitch == false)
        #expect(p.menuItems == [.cloneTag, .emptyTag])
    }

    @Test func filamentOnlyWithoutAMatchSearchesSpoolmanDB() {
        let p = plan(.filament(Self.tag(), nil, scannedUID: "04AABBCCDDEE02"))
        #expect(ids(p.filamentSection) == [.createNewSpool, .searchSpoolmanDB])
    }

    /// The tile and its (i) line name the catalogue the backend reads (FilaManDB
    /// on FilaMan); the tile's id stays `.searchSpoolmanDB`.
    @Test func searchTileNamesTheCatalogue() throws {
        let unified = UnifiedScanResult.filament(Self.tag(), nil, scannedUID: "04AABBCCDDEE02")

        let filaman = plan(unified, catalogName: "FilaManDB")
        let tile = try #require(filaman.filamentSection?.tiles.first { $0.id == .searchSpoolmanDB })
        #expect(tile.title == "Search FilaManDB")

        let usual = plan(unified)
        #expect(usual.filamentSection?.tiles.first { $0.id == .searchSpoolmanDB }?.title == "Search SpoolmanDB")

        let section = HubSection(kind: .filament, tiles: [tile])
        let lines = HubActionPlan.infoLines(
            for: section, spoolTitle: nil, unlinkTargetTitle: nil, backendName: "FilaMan",
            filamentRowCreates: true, catalogName: "FilaManDB"
        )
        #expect(lines.first
            == "Search FilaManDB — Find this filament in the FilaManDB catalogue and start a spool from it.")
        let defaulted = HubActionPlan.infoLines(
            for: section, spoolTitle: nil, unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: true
        )
        #expect(defaulted.first
            == "Search SpoolmanDB — Find this filament in the SpoolmanDB catalogue and start a spool from it.")
    }

    @Test func anAdoptedFilamentCanBeReverted() {
        let p = plan(.filament(Self.tag(), nil, scannedUID: "04AABBCCDDEE02"), workingFilamentId: 99, adopted: true)
        #expect(ids(p.filamentSection) == [.createNewSpool, .spoolsWithFilament, .revertToTagData])
    }

    @Test func aLinkedFilamentOnlyTagOffersUnlinkNotLink() {
        let p = plan(
            .filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"),
            link: .mapped(spoolID: 7, releasable: true), workingFilamentId: 10
        )
        #expect(ids(p.spoolSection) == [.unlink])
        #expect(!ids(p.spoolSection).contains(.linkTag))
    }

    @Test func aRecordOnlyFilamentTagOffersLinkNotUnlink() {
        let p = plan(
            .filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"),
            link: .ledger(spoolID: 7), workingFilamentId: 10
        )
        #expect(ids(p.spoolSection) == [.linkTag])
    }

    // MARK: - State 3b · OCR / QR

    @Test func anOCRScanHasNoSpoolSectionAndReviewsInTheMenu() {
        let p = plan(
            .filament(Self.tag(), nil, scannedUID: nil), format: .ocr,
            clone: false, erase: false, review: true
        )
        #expect(p.spoolSection == nil)
        #expect(ids(p.filamentSection) == [.createNewSpool, .searchSpoolmanDB])
        #expect(p.menuItems == [.reviewScannedData])
    }

    // MARK: - State 4 · UID only

    @Test func uidOnly() {
        let p = plan(.uidOnly("04AABBCCDDEE03"), format: nil, clone: false)
        #expect(ids(p.spoolSection) == [.createNewSpool, .linkTag])
        #expect(p.filamentSection == nil)
        #expect(p.menuItems == [.emptyTag])
    }

    @Test func aLinkedUIDOnlyTagOffersUnlinkNotLink() {
        let p = plan(.uidOnly("04AABBCCDDEE03"), link: .mapped(spoolID: 7, releasable: true), format: nil)
        #expect(ids(p.spoolSection) == [.createNewSpool, .unlink])
    }

    // MARK: - Outside Tag Links

    @Test(arguments: [spoolIDMode, neither])
    func anUnlinkedTagIsClaimedByWritingOutsideTagLinks(identity: TagIdentityPolicy) {
        let unknown = plan(.spool(Self.spool(), Self.tag(spoolmanId: 53), scannedUID: "04AABBCCDDEE01"), identity: identity)
        #expect(ids(unknown.spoolSection) == [.weigh])
        #expect(unknown.menuItems.first == .writeSpoolDataOntoTag)

        let filament = plan(.filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"), identity: identity, workingFilamentId: 10)
        #expect(filament.spoolSection == nil)
        #expect(filament.menuItems.first == .writeSpoolDataOntoTag)

        let uidOnly = plan(.uidOnly("04AABBCCDDEE03"), format: nil, identity: identity, clone: false)
        #expect(ids(uidOnly.spoolSection) == [.createNewSpool])
        #expect(uidOnly.menuItems == [.writeSpoolDataOntoTag, .emptyTag])
    }

    /// Unlink stays in every mode: links are read in every mode.
    @Test(arguments: [links, spoolIDMode, neither])
    func unlinkIsOfferedInEveryMode(identity: TagIdentityPolicy) {
        let p = plan(.uidOnly("04AABBCCDDEE03"), link: .mapped(spoolID: 7, releasable: true), format: nil, identity: identity)
        #expect(ids(p.spoolSection).contains(.unlink))
    }

    /// An OCR scan has no UID, so nothing claims a tag by writing either.
    @Test func anOCRScanOffersNoClaimInAnyMode() {
        let p = plan(.filament(Self.tag(), nil, scannedUID: nil), format: .ocr, identity: Self.neither,
                     clone: false, erase: false, review: true)
        #expect(p.menuItems == [.reviewScannedData])
    }

    // MARK: - Gates

    @Test func exactlyOnePrimaryTileInEveryState() {
        let plans = [
            plan(.spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
                 link: .mapped(spoolID: 53, releasable: true)),
            plan(.spool(Self.spool(), Self.tag(spoolmanId: 53), scannedUID: "04AABBCCDDEE01")),
            plan(.filament(Self.tag(), nil, scannedUID: "04AABBCCDDEE02")),
            plan(.uidOnly("04AABBCCDDEE03"), format: nil),
        ]
        for p in plans {
            let tiles = (p.spoolSection?.tiles ?? []) + (p.filamentSection?.tiles ?? [])
            #expect(tiles.filter(\.isPrimary).map(\.id) == [.createNewSpool])
        }
    }

    @Test func emptyThisTagIsAlwaysTheLastMenuItem() {
        #expect(HubActionPlan.maintenanceItems(offersClone: true, offersErase: true) == [.cloneTag, .emptyTag])
        #expect(HubActionPlan.maintenanceItems(offersClone: false, offersErase: false) == [])
    }

    @Test func menuItemsNameWhatTheyDo() {
        #expect(HubMenuItemID.writeSpoolID.title == "Write Spool ID to Tag")
        #expect(HubMenuItemID.writeSpoolDataOntoTag.title == "Write a Spool's Data onto This Tag")
        #expect(HubMenuItemID.cloneTag.title == "Clone Tag")
        #expect(HubMenuItemID.emptyTag.title == "Empty This Tag…")
        #expect(HubMenuItemID.reviewScannedData.title == "Review Scanned Data")
    }

    // MARK: - Row text

    @Test func spoolRowSubtitleCountsTheSpoolsTags() {
        let spool = Self.spool(cardUIDs: [Self.uid, "04371356C92A81"], remaining: 918)
        #expect(HubActionPlan.spoolRowSubtitle(spool: spool, scannedUID: Self.uid, isLinked: true)
            == "918 g left · 2 tags")
    }

    @Test func spoolRowSubtitleSaysTheScannedTagIsNotLinked() {
        let spool = Self.spool(remaining: 918)
        #expect(HubActionPlan.spoolRowSubtitle(spool: spool, scannedUID: "04AABBCCDDEE01", isLinked: false)
            == "918 g left · this tag isn't linked")
    }

    @Test func spoolRowSubtitleWithoutATagJustCountsTags() {
        let spool = Self.spool(cardUIDs: [Self.uid])
        #expect(HubActionPlan.spoolRowSubtitle(spool: spool, scannedUID: nil, isLinked: false) == "1 tag")
    }

    @Test func anUnresolvedSpoolRowSaysNoSpoolUsesTheTag() {
        #expect(HubActionPlan.unresolvedSpoolRowTitle(linkState: .notLinked, spools: [Self.spool()])
            == "No spool uses this tag")
    }

    /// It names the holder rather than inferring "archived", which was false
    /// right after the hub's own Create or Link Tag wrote the tag.
    @Test func anUnresolvedSpoolRowNamesTheSpoolThatHoldsTheTag() {
        let spools = [Self.spool(cardUIDs: [Self.uid])]
        #expect(HubActionPlan.unresolvedSpoolRowTitle(linkState: .mapped(spoolID: 53, releasable: true), spools: spools)
            == "Linked to AzureFilm BROWN")
        #expect(HubActionPlan.unresolvedSpoolRowTitle(linkState: .ledger(spoolID: 53), spools: spools)
            == "Linked to AzureFilm BROWN")
        #expect(HubActionPlan.unresolvedSpoolRowTitle(linkState: .mapped(spoolID: 99, releasable: false), spools: spools)
            == "Linked to a spool")
    }

    // MARK: - Create adopts the new spool

    @Test func aCreatedSpoolHoldingTheScannedUIDTakesTheTag() {
        #expect(ScanResultHubView.createdSpoolTakesScannedTag(
            scannedUID: "04:8b:13:56:c9:2a:81", created: Self.spool(cardUIDs: [Self.uid])
        ))
    }

    @Test func aCreatedSpoolWithoutTheScannedUIDDoesNotTakeTheTag() {
        // The user removed the tag in the form, or SpoolLink was off so none was posted.
        #expect(!ScanResultHubView.createdSpoolTakesScannedTag(scannedUID: Self.uid, created: Self.spool()))
        #expect(!ScanResultHubView.createdSpoolTakesScannedTag(
            scannedUID: Self.uid, created: Self.spool(cardUIDs: ["04AABBCCDDEE01"])
        ))
        // An OCR or QR scan has no tag.
        #expect(!ScanResultHubView.createdSpoolTakesScannedTag(scannedUID: nil, created: Self.spool(cardUIDs: [Self.uid])))
        #expect(!ScanResultHubView.createdSpoolTakesScannedTag(scannedUID: " ", created: Self.spool(cardUIDs: [Self.uid])))
    }

    // MARK: - "Tag differs" (D8)

    @Test func tagMatchingTheBackendDoesNotDiffer() {
        var tag = Self.tag()
        tag.colorHex = "#b58548"
        tag.brand = "azurefilm"
        #expect(!HubActionPlan.tagDiffers(tagData: tag, filament: Self.filament))
    }

    @Test func materialColourOrBrandMakesTheTagDiffer() {
        var material = Self.tag(); material.material = "PETG"
        var colour = Self.tag(); colour.colorHex = "000000"
        var brand = Self.tag(); brand.brand = "Elegoo"
        #expect(HubActionPlan.tagDiffers(tagData: material, filament: Self.filament))
        #expect(HubActionPlan.tagDiffers(tagData: colour, filament: Self.filament))
        #expect(HubActionPlan.tagDiffers(tagData: brand, filament: Self.filament))
    }

    @Test func aDifferentNameAloneDoesNotDiffer() {
        // Names differ across ecosystems for the same filament (scan-flow.md).
        var tag = Self.tag(); tag.name = "AHPLPBK-108"
        #expect(!HubActionPlan.tagDiffers(tagData: tag, filament: Self.filament))
    }

    @Test func aFieldMissingOnEitherSideIsNotCompared() {
        let noVendor = Filament(id: 11, name: "BROWN", material: "PLA", vendor: nil, colorHex: nil, density: 1.24)
        var tag = Self.tag(); tag.brand = "Anything"
        #expect(!HubActionPlan.tagDiffers(tagData: tag, filament: noVendor))
    }

    // MARK: - Grid

    @Test func tileGridColumns() {
        #expect(HubTileGrid.columnCount(forTileCount: 1) == 1)
        #expect(HubTileGrid.columnCount(forTileCount: 2) == 2)
        #expect(HubTileGrid.columnCount(forTileCount: 3) == 3)
        #expect(HubTileGrid.columnCount(forTileCount: 4) == 2)
    }

    // MARK: - (i) popovers

    @Test func spoolInfoExplainsEachTileShownAndHowToEdit() {
        let section = HubSection(kind: .spool, tiles: [
            HubAction(id: .weigh, title: "Weigh", systemImage: "scalemass"),
            HubAction(id: .unlink, title: "Unlink", systemImage: "xmark.circle"),
        ])
        let lines = HubActionPlan.infoLines(
            for: section, spoolTitle: "Spool #53", unlinkTargetTitle: "Spool #53", backendName: "Spoolman",
            filamentRowCreates: false
        )
        #expect(lines == [
            "Weigh — Update this spool's remaining weight from your scale.",
            "Unlink — Remove this tag from Spool #53 in Spoolman. Nothing on the tag is erased.",
            "Tap the spool to edit it.",
        ])
    }

    /// The Unlink line names the spool Unlink releases, which an embedded-ID
    /// scan can make a different spool from the one the section shows.
    @Test func spoolInfoNamesTheSpoolUnlinkReleases() {
        let section = HubSection(kind: .spool, tiles: [
            HubAction(id: .unlink, title: "Unlink", systemImage: "xmark.circle"),
        ])
        let other = HubActionPlan.infoLines(
            for: section, spoolTitle: "Spool #53", unlinkTargetTitle: "Spool #99", backendName: "Spoolman",
            filamentRowCreates: false
        )
        #expect(other.first == "Unlink — Remove this tag from Spool #99 in Spoolman. Nothing on the tag is erased.")

        let unknown = HubActionPlan.infoLines(
            for: section, spoolTitle: nil, unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: false
        )
        #expect(unknown.first == "Unlink — Remove this tag from its spool in Spoolman. Nothing on the tag is erased.")
    }

    @Test func filamentInfoExplainsTheSwitchOnlyWhenItIsShown() {
        let withSwitch = HubSection(kind: .filament, tiles: [
            HubAction(id: .createNewSpool, title: "Create New Spool", systemImage: "plus", isPrimary: true),
        ], showsSourceSwitch: true)
        let lines = HubActionPlan.infoLines(
            for: withSwitch, spoolTitle: nil, unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: false
        )
        #expect(lines.contains(
            "Tag / Spoolman — Switch between what the tag says and what Spoolman has. \"Tag differs\" means the material, colour or brand disagree."
        ))
        #expect(lines.last == "Tap the filament to edit it.")

        let creates = HubActionPlan.infoLines(
            for: HubSection(kind: .filament, tiles: withSwitch.tiles), spoolTitle: nil, unlinkTargetTitle: nil,
            backendName: "Spoolman", filamentRowCreates: true
        )
        #expect(creates.last == "Tap the filament to save it to Spoolman.")
    }

    // MARK: - Filament tag (2026-10-11)

    /// A scanned filament tag gets the hub's own tiles, names and icons.
    @Test func aFilamentTagGetsTheHubsTiles() {
        let all = HubActionPlan.filamentTagSection(canTransfer: true, canUnlink: true)
        #expect(all.kind == .filament)
        #expect(all.tiles == [HubActionPlan.createTile, HubActionPlan.transferTile, HubActionPlan.unlinkTile])
        #expect(HubActionPlan.filamentTagSection(canTransfer: false, canUnlink: true).tiles.map(\.id) == [.createNewSpool, .unlink])
        #expect(HubActionPlan.filamentTagSection(canTransfer: false, canUnlink: false).tiles.map(\.id) == [.createNewSpool])
    }

    @Test func aFilamentTagsInfoSaysWhatTheTagIs() {
        let lines = HubActionPlan.filamentTagInfoLines(
            for: HubActionPlan.filamentTagSection(canTransfer: true, canUnlink: true),
            filamentTitle: "PLA Basic", backendName: "Spoolman"
        )
        #expect(lines == [
            "This tag identifies this filament.",
            "Create New Spool — Create a spool of this filament. The tag stays with the filament.",
            "Transfer Tag — Move this tag from the filament to a spool.",
            "Unlink — Remove this tag from PLA Basic in Spoolman. Nothing on the tag is erased.",
            "Tap the filament to edit it, or a spool below to edit that spool.",
        ])
    }

    // MARK: - Filament targets named in the (i) lines (spec 2026-10-11)

    @Test func transferAndLinkLinesNameFilamentsWhereTheyAreOffered() {
        let section = HubSection(kind: .spool, tiles: [HubActionPlan.transferTile])
        let offered = HubActionPlan.infoLines(
            for: section, spoolTitle: "Spool #53", unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: false, offersFilamentTargets: true
        )
        #expect(offered.first == "Transfer Tag — Move this tag to another spool or a filament. You choose which of this spool's tags move.")

        let notOffered = HubActionPlan.infoLines(
            for: section, spoolTitle: "Spool #53", unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: false
        )
        #expect(notOffered.first == "Transfer Tag — Move this tag to another spool. You choose which of this spool's tags move.")

        let link = HubSection(kind: .spool, tiles: [HubAction(id: .linkTag, title: "Link Tag…", systemImage: "link")])
        #expect(HubActionPlan.infoLines(
            for: link, spoolTitle: nil, unlinkTargetTitle: nil, backendName: "Spoolman",
            filamentRowCreates: false, offersFilamentTargets: true
        ).first == "Link Tag — Record this tag against a spool or a filament in Spoolman. The tag itself is not written to.")
    }

    @Test func aFilamentTagsTransferLineNamesAnotherFilamentWhereOffered() {
        let lines = HubActionPlan.filamentTagInfoLines(
            for: HubActionPlan.filamentTagSection(canTransfer: true, canUnlink: false),
            filamentTitle: "PLA Basic", backendName: "Spoolman", offersFilamentTargets: true
        )
        #expect(lines.contains("Transfer Tag — Move this tag from the filament to a spool or another filament."))
    }

    // MARK: - Inspect Tag

    @Test func inspectSitsBetweenCloneAndErase() {
        #expect(HubActionPlan.maintenanceItems(offersClone: true, offersInspect: true, offersErase: true)
            == [.cloneTag, .inspectTag, .emptyTag])
        #expect(HubActionPlan.maintenanceItems(offersClone: false, offersInspect: true, offersErase: false)
            == [.inspectTag])
    }

    @Test func knownTagMenuGainsInspect() {
        let p = plan(
            .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
            link: .mapped(spoolID: 53, releasable: true),
            identity: Self.spoolIDMode,
            secondTag: .scanSecondTag(enabled: true),
            inspect: true
        )
        #expect(p.menuItems == [.writeSpoolID, .cloneTag, .inspectTag, .emptyTag])
    }

    /// The plan follows what the hub offers: an OCR scan carries no inspection,
    /// so the hub passes `false` and the menu stays as it was; a state that does
    /// offer it gets the item after Review Scanned Data.
    @Test func inspectIsInTheMenuOnlyWhenOffered() {
        let result = UnifiedScanResult.filament(Self.tag(), nil, scannedUID: nil)
        let without = plan(result, format: .ocr, clone: false, erase: false, review: true, inspect: false)
        #expect(without.menuItems == [.reviewScannedData])
        #expect(!without.menuItems.contains(.inspectTag))

        let with = plan(result, format: .ocr, clone: false, erase: false, review: true, inspect: true)
        #expect(with.menuItems == [.reviewScannedData, .inspectTag])
    }

    /// Spec §4: Inspect sits immediately before Empty This Tag, or last when
    /// erase is not offered, in every state the plan builds.
    @Test(arguments: [true, false])
    func inspectSitsRightBeforeEraseOrLastInEveryState(erase: Bool) {
        let plans: [(state: String, plan: HubActionPlan)] = [
            ("known spool", plan(
                .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
                link: .mapped(spoolID: 53, releasable: true), erase: erase, inspect: true
            )),
            ("known spool, Spool ID mode", plan(
                .spool(Self.spool(cardUIDs: [Self.uid]), Self.tag(), scannedUID: Self.uid),
                link: .mapped(spoolID: 53, releasable: true), identity: Self.spoolIDMode,
                erase: erase, inspect: true
            )),
            ("unknown tag with a spool ID", plan(
                .spool(Self.spool(), Self.tag(spoolmanId: 53), scannedUID: "04AABBCCDDEE01"),
                erase: erase, inspect: true
            )),
            ("filament only", plan(
                .filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"),
                workingFilamentId: 10, erase: erase, inspect: true
            )),
            ("filament only, claimed by writing", plan(
                .filament(Self.tag(), Self.filament, scannedUID: "04AABBCCDDEE02"),
                identity: Self.neither, workingFilamentId: 10, erase: erase, inspect: true
            )),
            ("UID only", plan(
                .uidOnly("04AABBCCDDEE03"), format: nil, clone: false, erase: erase, inspect: true
            )),
            ("UID only, claimed by writing", plan(
                .uidOnly("04AABBCCDDEE03"), format: nil, identity: Self.spoolIDMode,
                clone: false, erase: erase, inspect: true
            )),
        ]
        for (state, p) in plans {
            #expect(p.menuItems.filter { $0 == .inspectTag }.count == 1, "\(state)")
            if erase {
                #expect(p.menuItems.last == .emptyTag, "\(state)")
                #expect(p.menuItems.dropLast().last == .inspectTag, "\(state)")
            } else {
                #expect(p.menuItems.last == .inspectTag, "\(state)")
            }
        }
    }

    /// The states with no plan (a location tag, a bare no-match) use
    /// `maintenanceItems` alone: Clone, then Inspect, then Empty.
    @Test(arguments: [true, false], [true, false])
    func maintenanceItemsOrderInspectBetweenCloneAndErase(clone: Bool, erase: Bool) {
        let items = HubActionPlan.maintenanceItems(offersClone: clone, offersInspect: true, offersErase: erase)
        #expect(items.filter { $0 == .inspectTag }.count == 1)
        if clone { #expect(items.first == .cloneTag) }
        if erase {
            #expect(items.last == .emptyTag)
            #expect(items.dropLast().last == .inspectTag)
        } else {
            #expect(items.last == .inspectTag)
        }
        #expect(!HubActionPlan.maintenanceItems(offersClone: clone, offersInspect: false, offersErase: erase)
            .contains(.inspectTag))
    }

    @Test func inspectItemCopy() {
        #expect(HubMenuItemID.inspectTag.title == "Inspect Tag")
        #expect(HubMenuItemID.inspectTag.systemImage == "info.circle")
    }
}
