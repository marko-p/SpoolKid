//
//  ScanResultHubView.swift
//  SpoolKid
//
//  Purpose: Universal post-scan destination for all NFC tag formats.
//
//  Routing logic (in priority order):
//  1. Authoritative embedded spool ID  → show confirmed Spoolman spool
//  2. Linked tag UID (Spoolman Tags, card_uids) → show confirmed spool
//  3. Heuristic filament match          → show top match (auto-accept or chooser)
//  4. Encrypted / unknown tag           → show UID-only card
//
//  Secondary actions always available: Write to New Tag, Save to Recent Tags.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "ScanResultHub")

struct ScanResultHubView: View {
    let result: ScanResult
    /// Set once this hub has reported its scan to Spoolman (spec 3).
    @State private var didReportScan = false
    /// Spec 4: the filament card's Unlink confirmation and its last error.
    @State private var isConfirmingFilamentUnlink = false
    @State private var filamentTagError: String?
    /// Set while the spool chooser is picking where a filament's tag moves.
    @State private var filamentTagMoveSource: Filament?

    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var supportPrompts: SupportPromptService
    @ObservedObject private var spoolmanDBService = SpoolmanDBService.shared
    @StateObject private var secondTagNFCManager = NFCManager()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.serverLink) private var serverLink

    // MARK: - State

    enum HubState {
        case loading
        case parsingWebUrl(URL)
        case webChallenge(URL)
        case authoritativeSpool(Spool)
        case cardUIDSpool(Spool)
        case matchResults([FilamentMatchResult])
        case unknownTag
        case noSpoolman
        case locationTag(LocationTagPayload)
        /// Spec 4: the tag is linked to a filament type.
        case filamentTag(Filament)
        /// A printed Spoolman/FilaMan label that names nothing here.
        case backendLabelProblem(ScanResolutionService.BackendLabelProblem)
    }

    /// How the hub's current answer was reached. Drives two things: the
    /// footer's resolution part (`HubActionPlan.footerResolutionPart`) and
    /// `HubLinkState`'s `resolvedViaLedger` — only `.onDeviceLedger` lets a
    /// ledger row count as a link, so changing how this is set can bring back
    /// Link Tag and Unlink offered side by side (audit H8). Every action keeps
    /// operating on the resolved spool whichever source reached it.
    enum HubResolutionSource: Equatable {
        case embeddedSpoolID
        case spoolLinkMapping
        case onDeviceLedger
        case spoolIDMigration
        /// The record a printed Spoolman/FilaMan label names.
        case backendLabel
        case heuristicMatch(topConfidence: Int)
        case manualChoice
    }

    /// What the hub's filament form is opened FOR. Replaces the old
    /// isPresented-flag pair whose save chained straight into spool creation:
    /// saving a create now just returns to the hub, which re-resolves.
    /// PUSHED (navigationDestination(item:)), not sheeted — the owner wants
    /// filament forms to arrive like spool forms: from the right edge, with
    /// a back button. The binding resets to nil when the user pops back,
    /// which is what drives the return refresh.
    enum FilamentFormRequest: Identifiable, Equatable, Hashable {
        case createFromTagData(FilamentTagData)
        case editExisting(Filament)

        var id: String {
            switch self {
            case .createFromTagData: return "createFromTagData"
            case .editExisting(let filament): return "editExisting-\(filament.id)"
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        /// Identity-level equality (record id, not full value) — enough for
        /// `onChange`, which only needs to notice dismiss vs. present.
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.createFromTagData(let a), .createFromTagData(let b)): return a.id == b.id
            case (.editExisting(let a), .editExisting(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    @State private var hubState: HubState = .loading
    /// Tag Links: the question for a spool-ID tag whose filament differs.
    @State private var spoolIDMismatch: SpoolIDMismatch?
    @State private var isAnsweringMismatch = false
    /// Only Overwrite Tag from Spool opens the write screen in the scanned
    /// tag's format; every other route resets it to the default.
    @State private var writeInitialFormat: TagFormat?
    @State private var parsedTagData: FilamentTagData?
    @State private var resolutionSource: HubResolutionSource? = nil
    /// The Filament row's display source, set by its Tag / backend switch:
    /// false = the backend's resolved filament (default, the pre-toggle
    /// behavior), true = the tag's own payload.
    @State private var showsTagPayload = false
    @State private var filamentFormRequest: FilamentFormRequest? = nil
    /// The filament the user saved from this hub's filament form, adopted as
    /// the scan's working data: the Filament row displays its values (labelled
    /// "Edited") and actions like spool creation use it instead of re-deriving
    /// everything from the tag payload. One hub instance is one scan; undo
    /// ("Revert to Tag Data") clears the adoption — the saved filament
    /// itself stays in the backend.
    @State private var adoptedFilament: Filament? = nil

    private var effectiveTagData: FilamentTagData? {
        parsedTagData ?? result.tagData
    }

    @State private var navigateToWriteTag = false
    @State private var navigateToChooser = false
    @State private var navigateToCreateSpool = false
    @State private var navigateToMoreFilaments = false
    @State private var writeInitialData: FilamentTagData? = nil
    @State private var newSpoolInitialFilamentId: Int? = nil
    /// What the scanned tag says about the spool, for the form: set by the
    /// routes that build the new spool on the tag's data; nil on a tag that
    /// a spool or a filament already owns.
    @State private var newSpoolTagWeights: TagSpoolWeights? = nil
    @State private var didJustMapCurrentTag = false
    @State private var secondTagTargetSpoolId: Int? = nil
    @State private var isPreparingCreateSpool = false
    @State private var createSpoolError: String? = nil
    @State private var persistenceError: String? = nil
    /// FilaMan's one-tag limit met a person's link; what Replace Tag resumes.
    @State private var replaceRequest: TagReplaceRequest?
    @State private var replaceContinuation: ReplaceContinuation = .chooser

    private enum ReplaceContinuation {
        case chooser
        case mismatch(SpoolIDMismatch)
        case overwrite(SpoolIDMismatch)
        case secondTag(ScanResult)
    }
    @State private var showsEraseConfirmation = false
    /// Which reader Clone Tag and Empty This Tag write with. Never stored.
    @State private var tagReader: TagReader = .iPhone
    /// The reader the clone or erase in flight runs on, fixed when it starts.
    @State private var tagRun = TagReaderRun()
    @State private var unlinkOfferSpool: Spool? = nil
    /// The Create New Spool form's tag-move offer (D3). Set by the create tap,
    /// cleared when the form closes.
    @State private var createTagMoveOffer: TagMoveOffer? = nil
    /// Transfer Tag's tag-move offer (D5), shown in the chooser.
    @State private var transferTagMoveOffer: TagMoveOffer? = nil
    @State private var chooserAllowAllSpools = false
    @State private var chooserExcludedSpoolIDs: Set<Int> = []
    @State private var chooserIntent: ChooserIntent? = nil
    /// The chooser's Filaments tab (spec 2026-10-11); nil hides it.
    @State private var chooserFilamentTargets: FilamentTargets? = nil
    @State private var ocrCandidateForReview: OCRParsedCandidate? = nil
    @State private var navigateToFilteredSpools = false
    @State private var navigateToLocationAssignment = false
    @State private var locationAssignmentInitialName: String? = nil
    /// The resolved spool the user tapped on the result card, to EDIT.
    /// Kept separate from `navigateToCreateSpool`, which every "create"
    /// action shares: routing the card tap through that one opened the
    /// *create* form on a spool the hub had already identified.
    @State private var spoolBeingEdited: Spool? = nil
    @State private var navigateToEditSpool = false
    /// The weight card's set-up opens the Spool page straight in Edit, at Weight.
    @State private var editsSpoolAtWeight = false
    /// The resolved spool the user tapped "Weigh This Spool" for. Same
    /// separate-from-create reasoning as `spoolBeingEdited` above.
    @State private var spoolBeingWeighed: Spool? = nil
    @State private var navigateToWeighSpool = false
    @State private var filteredSpoolFilamentId: Int? = nil
    /// Clone Tag. `pendingCloneUnlinkUID` is the tag the user agreed to take
    /// from its owner, held until a copy lands on exactly that tag — nothing
    /// is unlinked before then.
    @State private var pendingCloneUnlinkUID: String? = nil
    @State private var cloneUnlinkOfferUID: String? = nil
    @State private var cloneLinkStep: TagCloneService.LinkStep? = nil
    /// Inspect Tag shows what the scan read. `tagChangedSinceScan` flips when
    /// this hub writes to or erases the scanned tag, so that screen can say
    /// its reading is out of date.
    @State private var navigateToInspector = false
    @State private var tagChangedSinceScan = false

    enum ChooserIntent: Equatable {
        case mapUIDToSpool
        case overwriteTag
    }

    enum ChooserSelectionAction {
        case persistUID(spoolID: Int)
        case navigateToWriteTag(FilamentTagData)
    }

    enum UIDMappingActionState: Equatable {
        case scanSecondTag(enabled: Bool)
        case none
    }

    static func uidMappingActionState(
        writesLinks: Bool,
        didJustMapCurrentTag: Bool,
        isSecondTagScanning: Bool
    ) -> UIDMappingActionState {
        guard didJustMapCurrentTag else { return .none }
        // Unlimited card_uids: "Scan another tag" is always offered while mapping.
        return .scanSecondTag(enabled: writesLinks && !isSecondTagScanning)
    }

    /// Spec 2026-10-11: Transfer Tag and Link Tag… (`.mapUIDToSpool`) also
    /// offer filaments where filament links are written; the write-onto-tag
    /// chooser never does.
    nonisolated static func offersFilamentTargets(intent: ChooserIntent?, writesFilamentLinks: Bool) -> Bool {
        guard writesFilamentLinks, case .mapUIDToSpool? = intent else { return false }
        return true
    }

    static func chooserSelectionAction(intent: ChooserIntent?, spool: Spool) -> ChooserSelectionAction {
        switch intent {
        case .overwriteTag:
            return .navigateToWriteTag(FilamentTagData.from(spool: spool))
        case .mapUIDToSpool, .none:
            return .persistUID(spoolID: spool.id)
        }
    }

    /// The registry entry a scanned location tag belongs to: by uuid first
    /// (authoritative, survives renames), then by the tag's own hardware UID —
    /// which is how a tag adopted into an entry that already held its name is
    /// recognised, since that merge keeps the existing entry's uuid. `nil`
    /// means the registry does not know this tag at all.
    @MainActor
    static func registryRecord(
        for payload: LocationTagPayload, scannedUID: String? = nil, registry: LocationRegistry?
    ) -> LocationRecord? {
        guard let registry else { return nil }
        if let byUUID = registry.records.first(where: { $0.uuid == payload.uuid }) { return byUUID }
        guard let scannedUID else { return nil }
        return registry.record(forTagUID: scannedUID)
    }

    /// "Add" would be a lie when a location of that name is already registered:
    /// the tap then joins this tag to the entry that exists rather than
    /// creating anything. A button names what it actually does.
    static func adoptButtonTitle(name: String, nameIsAlreadyRegistered: Bool) -> String {
        nameIsAlreadyRegistered ? "Link This Tag to \(name)" : "Add \(name)"
    }

    /// The uuid is authoritative and the on-tag name is a cached label, so a
    /// location renamed after its tag was written still resolves. An unknown
    /// tag falls back to the tag's own name — which is how a tag written on
    /// another device, or before a reinstall, still works.
    @MainActor
    static func resolvedLocationName(
        for payload: LocationTagPayload, scannedUID: String? = nil, registry: LocationRegistry?
    ) -> String {
        registryRecord(for: payload, scannedUID: scannedUID, registry: registry)?.name ?? payload.name
    }

    /// A tag that reads as a spool tag is not a location tag any more — an NDEF
    /// write replaced the whole message. Release the UID rather than letting a
    /// rename go on offering to rewrite a tag that no longer exists. Silent by
    /// design: the user already made this choice when they wrote the spool tag.
    @MainActor
    static func healRegistry(afterReadingSpoolTagWithUID uid: String, registry: LocationRegistry?) {
        registry?.detachTag(uid: uid)
    }

    // MARK: - Tag maintenance (Empty This Tag / Unlink)

    /// Whether the hub offers to erase the scanned tag. Only an NFC read
    /// carries the tag's UID and therefore a physical tag to target — a QR,
    /// web or OCR scan has none. Hidden while resolution is unsettled,
    /// mirroring `TagCloneService.showsCloneButton`: the owner the erase
    /// confirmation names is not known yet.
    nonisolated static func showsEraseButton(cardUID: String?, hubState: HubState) -> Bool {
        guard let cardUID, !SpoolMappingService.normalizeUID(cardUID).isEmpty else { return false }
        switch hubState {
        case .loading, .parsingWebUrl, .webChallenge:
            return false
        case .authoritativeSpool, .cardUIDSpool, .matchResults, .unknownTag, .noSpoolman, .locationTag, .filamentTag,
             .backendLabelProblem:
            return true
        }
    }

    /// Whether a write that landed on `writtenUID` may have changed the tag
    /// that was scanned. A missing UID on either side cannot rule it out, so
    /// it counts: the notice is the safe side of "may have".
    nonisolated static func writeChangesScannedTag(writtenUID: String?, scannedUID: String?) -> Bool {
        guard let writtenUID, let scannedUID else { return true }
        return SpoolMappingService.normalizeUID(writtenUID) == SpoolMappingService.normalizeUID(scannedUID)
    }

    /// The catalogue the backend reads (FilaManDB on FilaMan), as the hub names it.
    private var catalogName: String { store.capabilities.manufacturerCatalog.displayName }

    private var workingFilamentId: Int? {
        guard case .filament(_, let matchedFilament, _) = unifiedResult else { return nil }
        return Self.workingFilament(adopted: adoptedFilament, matched: matchedFilament)?.id
    }

    private var resolutionService: ScanResolutionService {
        ScanResolutionService(
            repository: store,
            spoolmanDBService: spoolmanDBService,
            webParserService: .shared,
            identity: store.tagIdentity
        )
    }

    /// Signature verdict for a TigerTag scan. Unsigned is the normal state
    /// for maker-written tags and stays silent; only a verdict speaks.
    nonisolated static func signatureCaption(for info: TigerTagInfo?) -> (text: String, isWarning: Bool)? {
        switch info?.signature {
        case .valid:
            return ("Genuine — TigerTag+ Certified signature verified offline", false)
        case .invalid:
            return ("Signature invalid — this tag claims a brand it is not from", true)
        case .unsigned, nil:
            return nil
        }
    }

    /// What an OpenPrintTag says is left, on the printer's basis: "On tag:
    /// 612 g of 1,000 g left". Display only; nil unless the tag carries both a
    /// consumed weight and a full weight.
    nonisolated static func tagRemainingCaption(for data: FilamentTagData?, locale: Locale = .current) -> String? {
        guard let data, let remaining = data.remainingOnTag, let full = data.fullWeightOnTag else { return nil }
        func grams(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0)).locale(locale)) }
        return "On tag: \(grams(remaining)) g of \(grams(full)) g left"
    }

    /// D13: one line on where the data came from and how the hub found its
    /// answer, under the sections. A TigerTag signature verdict keeps its own
    /// line and icon — a trust signal is not shortened.
    @ViewBuilder
    private var provenanceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            let parts = [
                Self.provenanceCaption(format: result.format, hasParsedWebData: parsedTagData != nil, webHost: result.url?.host),
                HubActionPlan.footerResolutionPart(resolutionSource, backendName: store.capabilities.displayName),
            ].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let signature = Self.signatureCaption(for: result.tigerTagInfo) {
                Label(signature.text, systemImage: signature.isWarning ? "exclamationmark.shield.fill" : "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(signature.isWarning ? .orange : .green)
            }
            if result.isReportedByPrinter {
                Label(TagReaderOption.reportedByPrinterNote, systemImage: "printer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let remaining = Self.tagRemainingCaption(for: result.tagData) {
                Label(remaining, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// States that render neither a unified card nor contextual actions.
    @ViewBuilder
    private var fallbackStateView: some View {
        switch hubState {
        case .loading:
            ProgressView("Looking up spool...")
                .padding()
        case .parsingWebUrl(let url):
            VStack(spacing: 12) {
                ProgressView()
                Text("Fetching spool data from:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(url.host ?? url.absoluteString)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding()
        case .webChallenge(let url):
            VStack(spacing: 12) {
                Text("Security Check Required")
                    .font(.headline)
                Text("Please complete the security check to view the spool data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                WebChallengeView(url: url) { html in
                    Task {
                        await handleWebChallengeSuccess(html: html, url: url)
                    }
                } onCancel: {
                    hubState = .unknownTag
                }
                .frame(height: 300)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                Button("Cancel") {
                    hubState = .unknownTag
                }
                .padding(.top)
            }
            .padding()
        case .noSpoolman:
            noMappingCard(capabilities: store.capabilities)
        case .backendLabelProblem(let problem):
            backendLabelProblemCard(problem)
        case .locationTag(let payload):
            locationTagCard(payload)
        case .filamentTag(let filament):
            FilamentTagCard(
                filament: filament,
                spools: store.activeSpools.filter { $0.filament.id == filament.id },
                // A printed label has no tag to transfer or unlink.
                section: HubActionPlan.filamentTagSection(
                    canTransfer: result.cardUID != nil && store.tagIdentity.writesLinks,
                    canUnlink: result.cardUID != nil && store.filamentTagStore != nil
                ),
                backendName: store.capabilities.displayName,
                errorMessage: filamentTagError,
                offersFilamentTargets: store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore),
                onTile: { performFilamentTagTile($0, filament: filament) },
                // Opens the spool rather than resolving the scan to it: this
                // tag is the filament's, and resolving would offer to claim it.
                onOpenSpool: { spool in
                    spoolBeingEdited = spool
                    navigateToEditSpool = true
                },
                onEditFilament: { filamentFormRequest = .editExisting(filament) }
            )
            .alert("Unlink Tag?", isPresented: $isConfirmingFilamentUnlink) {
                Button("Cancel", role: .cancel) {}
                Button("Unlink", role: .destructive) {
                    Task { await unlinkFilamentTag(from: filament) }
                }
            } message: {
                Text("The tag will no longer identify \(filament.listTitle).")
            }
        case .authoritativeSpool, .cardUIDSpool, .matchResults, .unknownTag:
            EmptyView()
        }
    }

    private func locationTagCard(_ payload: LocationTagPayload) -> some View {
        let known = Self.registryRecord(
            for: payload, scannedUID: result.cardUID, registry: store.locationRegistry
        )
        let name = known?.name ?? payload.name
        return VStack(spacing: 16) {
            Label("Location tag", systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(name)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)

            Button("Assign a Spool Here") {
                locationAssignmentInitialName = name
                navigateToLocationAssignment = true
            }
            .buttonStyle(.borderedProminent)
            .needsServer()

            if let known {
                if known.name != payload.name {
                    Button("Update This Tag to \"\(known.name)\"") {
                        secondTagNFCManager.writeLocationTag(
                            LocationTagPayload(uuid: known.uuid, name: known.name),
                            blockedUIDs: store.tagMappedUIDs.union(store.filamentTagUIDs)
                        )
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("This tag isn't linked to one of your locations yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Adopts the TAG's uuid rather than minting a
                // fresh one: the tag was written elsewhere, and
                // an entry under a new uuid would leave it
                // unrecognised on every future scan, however
                // many times this button is tapped. The UID
                // joins the entry too, so a later rename can
                // offer to rewrite this tag.
                Button(Self.adoptButtonTitle(
                    name: name,
                    nameIsAlreadyRegistered: store.locationRegistry?.record(named: name) != nil
                )) {
                    Task {
                        let outcome = await store.addLocation(
                            name: name, adoptingUUID: payload.uuid, tagUID: result.cardUID
                        )
                        if let note = outcome.note(locationName: name, storageNoun: store.capabilities.storageNoun) {
                            store.postSaveNotice(note, record: name)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .needsServer()
            }
        }
        .padding()
    }

    // MARK: - Body

    var body: some View {
        hubLifecycle(
            hubSheets(
                hubDestinations(
                    hubChrome(scanContent)
                )
            )
        )
    }

    private var scanContent: some View {
        scanScroll
            .tagReplacePrompt($replaceRequest) { request in replaceTag(request) }
    }

    /// Replace Tag: the link the person was asked about continues.
    private func replaceTag(_ request: TagReplaceRequest) {
        switch replaceContinuation {
        case .chooser:
            guard let spool = request.spool else { return }
            Task { await persistUIDIfNeeded(to: spool, replacing: true) }
        case .mismatch(let mismatch):
            isAnsweringMismatch = true
            Task { await linkAnyway(mismatch, replacing: true) }
        case .overwrite(let mismatch):
            isAnsweringMismatch = true
            Task { await overwriteMismatchedTag(mismatch, replacing: true) }
        case .secondTag(let scan):
            guard let spool = request.spool else { return }
            Task { await finishSecondTagLink(scan, to: spool, replacing: true) }
        }
    }

    /// The question to ask before linking this scan's tag to `spool`, from the
    /// store's current copy of the spool. Nil when nothing is in the way.
    private func replaceQuestion(for spool: Spool, uid: String?) -> TagReplaceRequest? {
        guard let uid else { return nil }
        let current = store.spools.first { $0.id == spool.id } ?? spool
        return TagReplaceRequest.linking(uid: uid, to: current, targets: store.tagIdentity.linkTargets)
    }

    private var scanScroll: some View {
        ScrollView {
            VStack(spacing: 20) {
                // With a list loaded the tag still resolves against it; with
                // none, nothing behind the tag can be found.
                if serverLink.isDown, store.spools.isEmpty {
                    Text(ServerTagWriteRule.lookupNote(backendName: serverLink.backendName))
                        .font(.body).foregroundStyle(.secondary)
                }
                if let mismatch = spoolIDMismatch {
                    SpoolIDMismatchCard(
                        mismatch: mismatch,
                        isWorking: isAnsweringMismatch || isPreparingCreateSpool,
                        // Marked working before the Task starts, so a second
                        // tap in the same frame starts no second link.
                        onLinkAnyway: {
                            guard !isAnsweringMismatch else { return }
                            isAnsweringMismatch = true
                            Task { await linkAnyway(mismatch, replacing: false) }
                        },
                        onOverwrite: {
                            guard !isAnsweringMismatch else { return }
                            isAnsweringMismatch = true
                            Task { await overwriteMismatchedTag(mismatch, replacing: false) }
                        },
                        onCreate: { createSpoolFromMismatchedTag() }
                    )
                    .needsServer()
                }
                if let unifiedResult = unifiedResult {
                    hubSections(for: unifiedResult)
                } else {
                    fallbackStateView
                }
                if offersTagWrites {
                    tagReaderRow
                }
                provenanceFooter
            }
            .padding()
        }
    }

    /// Clone Tag and Empty This Tag both write a tag, so both take the reader.
    /// The row is left out entirely without a usable printer reader, so the
    /// hub's spacing is unchanged.
    private var offersTagWrites: Bool {
        hubMenuItems.contains { $0 == .cloneTag || $0 == .emptyTag }
            && !TagReaderOption.options(printer: printer, store: store,
                                        purpose: .write(format: result.format?.tagFormat)).isEmpty
    }

    private var tagReaderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            TagReaderPicker(selection: $tagReader, purpose: .write(format: result.format?.tagFormat),
                            title: "Clone and Empty with")
            if secondTagNFCManager.isScanning, let progress = tagRun.progressText {
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// One answer for "is this tag linked?". Link Tag and Unlink both read it,
    /// so they can never be offered together (audit H8).
    private var linkState: HubLinkState {
        HubLinkState.resolve(
            uid: result.cardUID,
            resolvedViaLedger: resolutionSource == .onDeviceLedger,
            spools: store.spools,
            ledger: TagAssociationStore.shared.snapshot()
        )
    }

    /// The spool Unlink releases — a claim SpoolKid can actually remove.
    private func unlinkTarget(for linkState: HubLinkState) -> Spool? {
        guard let spoolID = linkState.unlinkSpoolID else { return nil }
        return store.spools.first { $0.id == spoolID }
    }

    private func actionPlan(for unified: UnifiedScanResult, linkState: HubLinkState) -> HubActionPlan {
        HubActionPlan.make(.init(
            result: unified,
            linkState: linkState,
            tagFormat: result.format,
            identity: store.tagIdentity,
            secondTagState: secondTagActionState(for: unified),
            isSecondTagScanning: secondTagNFCManager.isScanning,
            workingFilamentId: workingFilamentId,
            hasAdoptedFilament: adoptedFilament != nil,
            offersClone: TagCloneService.showsCloneButton(result: result, hubState: hubState),
            offersErase: Self.showsEraseButton(cardUID: result.cardUID, hubState: hubState),
            offersScanReview: result.ocrCandidate != nil,
            offersInspect: result.inspection != nil,
            catalogName: catalogName
        ))
    }

    /// D10: the plan's items for a resolved scan; tag maintenance alone for
    /// the states with no plan (location tag, a bare no-match).
    private var hubMenuItems: [HubMenuItemID] {
        if let unified = unifiedResult { return actionPlan(for: unified, linkState: linkState).menuItems }
        return HubActionPlan.maintenanceItems(
            offersClone: TagCloneService.showsCloneButton(result: result, hubState: hubState),
            offersInspect: result.inspection != nil,
            offersErase: Self.showsEraseButton(cardUID: result.cardUID, hubState: hubState)
        )
    }

    private func performMenuItem(_ item: HubMenuItemID) {
        switch item {
        case .writeSpoolID:
            if let unified = unifiedResult { writeSpoolIdToTag(for: unified) }
        case .writeSpoolDataOntoTag:
            chooserAllowAllSpools = true
            chooserIntent = .overwriteTag
            chooserFilamentTargets = nil
            navigateToChooser = true
        case .cloneTag:
            startClone(allowing: nil)
        case .inspectTag:
            WorkflowTraceStore.log(path: "hub", step: "inspect.open", details: [
                "format": result.format?.displayName ?? ""
            ])
            navigateToInspector = true
        case .emptyTag:
            showsEraseConfirmation = true
        case .reviewScannedData:
            ocrCandidateForReview = result.ocrCandidate
        }
    }

    /// The filament-tag section's tiles (spec 4; layout 2026-10-11).
    private func performFilamentTagTile(_ id: HubTileID, filament: Filament) {
        switch id {
        case .createNewSpool:
            newSpoolInitialFilamentId = filament.id
            newSpoolTagWeights = nil
            createTagMoveOffer = nil
            createSpoolError = nil
            persistenceError = nil
            navigateToCreateSpool = true
        case .transferTag:
            filamentTagMoveSource = filament
            filamentTagError = nil
            chooserAllowAllSpools = true
            chooserIntent = .mapUIDToSpool
            chooserFilamentTargets = filamentTargets(for: .mapUIDToSpool, suggested: [], excluded: [filament.id])
            navigateToChooser = true
        case .unlink:
            isConfirmingFilamentUnlink = true
        default:
            break
        }
    }

    /// The Filaments tab's input for the chooser about to open, or nil where
    /// that chooser offers none.
    private func filamentTargets(for intent: ChooserIntent, suggested: [Int], excluded: Set<Int> = []) -> FilamentTargets? {
        guard Self.offersFilamentTargets(
            intent: intent,
            writesFilamentLinks: store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore)
        ) else { return nil }
        return FilamentTargets(suggestedIDs: suggested, excludedIDs: excluded)
    }

    private func performTile(_ id: HubTileID, for unified: UnifiedScanResult) {
        switch id {
        case .weigh:
            if case .spool(let spool, _, _) = unified {
                spoolBeingWeighed = spool
                navigateToWeighSpool = true
            }
        case .transferTag:
            transferTagMoveOffer = Self.tagMoveOffer(for: unified)
            persistenceError = nil
            chooserAllowAllSpools = true
            chooserIntent = .mapUIDToSpool
            var suggested: [Int] = []
            if case .spool(let spool, _, _) = unified {
                chooserExcludedSpoolIDs = [spool.id]
                suggested = [spool.filament.id]
            }
            chooserFilamentTargets = filamentTargets(for: .mapUIDToSpool, suggested: suggested)
            navigateToChooser = true
        case .unlink:
            unlinkOfferSpool = unlinkTarget(for: linkState)
        case .addAnotherTag:
            if case .spool(let spool, _, _) = unified {
                secondTagTargetSpoolId = spool.id
                tagRun = .iPhone
                secondTagNFCManager.startScanning()
            }
        case .linkTag:
            // A ledger-only hit goes through the chooser too: the record can
            // be stale (a link removed on purpose), so the person picks the
            // spool (issue #24 final review I-3).
            chooserAllowAllSpools = true
            chooserIntent = .mapUIDToSpool
            var suggested: [Int] = []
            if case .filament(_, let matchedFilament, _) = unified,
               let id = Self.workingFilament(adopted: adoptedFilament, matched: matchedFilament)?.id {
                suggested = [id]
            }
            chooserFilamentTargets = filamentTargets(for: .mapUIDToSpool, suggested: suggested)
            navigateToChooser = true
        case .createNewSpool:
            if case .filament(let tagData, _, _) = unified {
                createSpool(fromScannedFilament: tagData)
            } else {
                newSpoolInitialFilamentId = Self.initialFilamentIdForCreateSpool(unified)
                newSpoolTagWeights = nil
                // The form links tags only where linking is active, so only
                // then can it move anything.
                createTagMoveOffer = store.tagIdentity.writesLinks ? Self.tagMoveOffer(for: unified) : nil
                createSpoolError = nil
                persistenceError = nil
                navigateToCreateSpool = true
            }
        case .spoolsWithFilament:
            if case .filament(_, let matchedFilament, _) = unified,
               let filamentId = Self.workingFilament(adopted: adoptedFilament, matched: matchedFilament)?.id {
                filteredSpoolFilamentId = filamentId
                navigateToFilteredSpools = true
            }
        case .searchSpoolmanDB:
            navigateToMoreFilaments = true
        case .revertToTagData:
            adoptedFilament = nil
        case .writeTag, .setLocation:
            break
        }
    }

    /// Create New Spool on a filament-only scan: find-or-create the scanned
    /// filament's parents in the active backend, THEN open the form
    /// preselected with that filament — never a heuristic guess.
    ///
    /// `onOpen` runs only once the form is actually opening — never when
    /// find-or-create fails and the hub shows `createSpoolError` instead.
    private func createSpool(fromScannedFilament tagData: FilamentTagData, onOpen: @escaping () -> Void = {}) {
        newSpoolTagWeights = TagSpoolWeights(tagData: tagData, format: result.format)
        // An adopted (user-saved) filament IS the filament to build on —
        // find-or-create from the tag payload would create a duplicate under
        // the tag's raw brand.
        if let adopted = adoptedFilament {
            newSpoolInitialFilamentId = adopted.id
            navigateToCreateSpool = true
            onOpen()
            return
        }
        createSpoolError = nil
        isPreparingCreateSpool = true
        Task {
            let filament = await resolutionService.findOrCreateFilament(for: tagData, format: result.format?.tagFormat)
            await MainActor.run {
                isPreparingCreateSpool = false
                if let filament {
                    if let caveat = resolutionService.lastCreateCaveat {
                        store.postSaveNotice(caveat, record: filament.name)
                    }
                    newSpoolInitialFilamentId = filament.id
                    navigateToCreateSpool = true
                    onOpen()
                } else {
                    createSpoolError = Self.createSpoolFailureMessage(
                        backendName: store.capabilities.displayName,
                        detail: store.errorMessage
                    )
                }
            }
        }
    }

    /// The scanned tag data, with this spool id set. Every field the tag
    /// carries is kept, including the extra colors.
    static func withSpoolID(_ spoolID: Int, from existing: FilamentTagData) -> FilamentTagData {
        var copy = existing
        copy.spoolmanId = spoolID
        return copy
    }

    /// Upgrades the tag to the authoritative fast path for future scans: the
    /// scanned data, plus this spool's id.
    private func writeSpoolIdToTag(for unified: UnifiedScanResult) {
        guard case .spool(let spool, _, _) = unified else { return }
        let tagDataToWrite: FilamentTagData
        if let existing = effectiveTagData {
            tagDataToWrite = Self.withSpoolID(spool.id, from: existing)
        } else {
            tagDataToWrite = FilamentTagData.from(spool: spool)
        }
        writeInitialData = tagDataToWrite
        writeInitialFormat = nil
        navigateToWriteTag = true
    }

    private func hubChrome<Content: View>(_ content: Content) -> some View {
        content
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(tagRun.holdsScreen(isScanning: secondTagNFCManager.isScanning))
            .interactiveDismissDisabled(tagRun.holdsScreen(isScanning: secondTagNFCManager.isScanning))
            // The weight card's Used and Measured boxes are decimal pads, which
            // have no return key. Same rule as every SpoolKid keyboard.
            .keyboardDoneBar()
            .toolbar {
                // D9: no Done — on a pushed view it did exactly what Back does.
                ToolbarItem(placement: .topBarTrailing) {
                    let items = hubMenuItems
                    if !items.isEmpty {
                        Menu {
                            ForEach(items, id: \.self) { item in
                                if item == .emptyTag, item != items.first { Divider() }
                                Button(role: item == .emptyTag ? .destructive : nil) {
                                    performMenuItem(item)
                                } label: {
                                    if item == .cloneTag, let warning = TagCloneService.untestedWarning(for: result) {
                                        Label {
                                            Text(item.title)
                                            Text(warning)
                                        } icon: {
                                            Image(systemName: item.systemImage)
                                        }
                                    } else {
                                        Label(item.title, systemImage: item.systemImage)
                                    }
                                }
                                .disabled(
                                    secondTagNFCManager.isScanning && (item == .cloneTag || item == .emptyTag)
                                        || item.needsServer && serverLink.isDown
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel("More")
                        }
                    }
                }
            }
    }

    private func hubDestinations<Content: View>(_ content: Content) -> some View {
        content
            .navigationDestination(isPresented: $navigateToWriteTag) {
                WriteTagView(
                    initialData: writeInitialData ?? effectiveTagData,
                    scannedCardUID: result.cardUID,
                    initialFormat: writeInitialFormat,
                    onTagWritten: { uid in
                        if Self.writeChangesScannedTag(writtenUID: uid, scannedUID: result.cardUID) {
                            tagChangedSinceScan = true
                        }
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToInspector) {
                if let inspection = result.inspection {
                    TagInspectorView(
                        inspection: inspection,
                        formatName: TagInspectionFormatter.formatName(
                            format: result.format,
                            isLocationTag: result.locationTag != nil,
                            undecodedNote: result.undecodedTagNote
                        ),
                        changedSinceScan: tagChangedSinceScan
                    )
                }
            }
            .navigationDestination(isPresented: $navigateToCreateSpool) {
                SpoolFormView(
                    store: store,
                    initialFilamentId: newSpoolInitialFilamentId,
                    initialCardUIDs: newSpoolInitialCardUIDs,
                    tagMoveOffer: createTagMoveOffer,
                    tagWeights: newSpoolTagWeights,
                    onSaveSpool: { newSpool, movedUIDs in
                        // D3: the source loses exactly the tags the user ticked.
                        if let offer = createTagMoveOffer, !movedUIDs.isEmpty {
                            guard let source = store.spools.first(where: { $0.id == offer.sourceSpoolID })
                            else { return }
                            Task {
                                await handleSavedSpoolFromForm(newSpool, sourceSpool: source, movedUIDs: movedUIDs)
                            }
                            return
                        }
                        // Nothing moved, but the form may still have posted the
                        // scanned UID (states 2–4), and then the new spool owns
                        // the tag. The hub must show that spool: its resolve-time
                        // answer no longer owns the tag, so a second Create would
                        // open with no tag-move checklist and give the tag two
                        // owners.
                        let created = Self.refreshedSpool(id: newSpool.id, from: store.spools) ?? newSpool
                        guard Self.createdSpoolTakesScannedTag(scannedUID: result.cardUID, created: created)
                        else { return }
                        hubState = .authoritativeSpool(created)
                        resolutionSource = .manualChoice
                    }
                )
            }
            .onChange(of: navigateToCreateSpool) { _, isPresented in
                if !isPresented { createTagMoveOffer = nil }
            }
            .navigationDestination(isPresented: $navigateToMoreFilaments) {
                NewSpoolFilamentSelectionView(
                    load: loadNewSpoolCandidates,
                    onSelect: { source in
                        navigateToMoreFilaments = false
                        createNewSpool(from: source)
                    },
                    catalogName: catalogName
                )
            }
            .navigationDestination(isPresented: $navigateToChooser) {
                TagTargetPicker(
                    matches: matchResults,
                    allowAllSpools: chooserAllowAllSpools,
                    excludedSpoolIDs: chooserExcludedSpoolIDs,
                    tagMoveOffer: transferTagMoveOffer,
                    filamentTargets: chooserFilamentTargets,
                    onSelect: { target, movedUIDs in
                        switch target {
                        case .spool(let spool):
                            handleChooserSelection(spool: spool, movedUIDs: movedUIDs)
                        case .filament(let filament):
                            moveScannedTags(to: filament, movedUIDs: movedUIDs)
                        }
                        navigateToChooser = false
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToFilteredSpools) {
                ManageSpoolsView(filter: filteredSpoolFilamentId.map(SpoolFilter.filament))
            }
            .navigationDestination(isPresented: $navigateToLocationAssignment) {
                LocationAssignmentView(initialLocationName: locationAssignmentInitialName)
            }
            .navigationDestination(isPresented: $navigateToEditSpool) {
                if let spoolBeingEdited {
                    SpoolPageView(store: store, spoolID: spoolBeingEdited.id, startsEditingAtWeight: editsSpoolAtWeight)
                }
            }
            // `SpoolFormView` reports a save only for creates (`onSaveSpool`),
            // so an edit is picked up here: the hub holds its own copy of the
            // spool and would otherwise keep showing the values the user just
            // changed.
            .onChange(of: navigateToEditSpool) { _, isPresented in
                guard !isPresented, let edited = spoolBeingEdited else { return }
                spoolBeingEdited = nil
                editsSpoolAtWeight = false
                if let refreshed = Self.refreshedSpool(id: edited.id, from: store.spools) {
                    hubState = .authoritativeSpool(refreshed)
                }
            }
            .navigationDestination(isPresented: $navigateToWeighSpool) {
                if let spoolBeingWeighed {
                    WeighSessionView(initialSpool: spoolBeingWeighed)
                }
            }
            // Same reasoning as the edit-spool pair above: `WeighSessionView`
            // writes the spool's weight directly, so the hub's own copy has
            // to be refreshed on return or the card keeps showing the
            // pre-weigh remaining weight.
            .onChange(of: navigateToWeighSpool) { _, isPresented in
                guard !isPresented, let weighed = spoolBeingWeighed else { return }
                spoolBeingWeighed = nil
                if let refreshed = Self.refreshedSpool(id: weighed.id, from: store.spools) {
                    hubState = .authoritativeSpool(refreshed)
                }
            }
            // PUSHED, not sheeted: filament forms arrive like spool forms —
            // from the right edge, with a back button (owner, 2026-09-15).
            // No NavigationStack wrapper: pushed views must not declare one.
            .navigationDestination(item: $filamentFormRequest) { request in
                switch request {
                case .createFromTagData(let tagData):
                    FilamentFormView(store: store, initialData: tagData, onSaveFilament: { created in
                        // The user saved a filament from this scan: adopt
                        // it as the hub's working data (display + actions).
                        adoptedFilament = created
                    })
                case .editExisting(let filament):
                    FilamentPageView(store: store, filamentID: filament.id)
                }
            }
            // Saving a create inside the form writes through the store and
            // pops; an edit on the filament page saves in place, and only its
            // back button pops. `navigationDestination(item:)` nils the binding
            // on pop, and re-resolving picks the change up (a created filament
            // now matches, an edited one updates the displayed spool's copy).
            // Cancelling a create re-resolves too — the cascade is idempotent.
            .onChange(of: filamentFormRequest) { _, request in
                guard request == nil else { return }
                Task { await refreshAfterFilamentFormDismissal() }
            }
    }

    private func hubSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $ocrCandidateForReview) { candidate in
                ocrReviewSheet(candidate)
            }
    }

    private func ocrReviewSheet(_ candidate: OCRParsedCandidate) -> some View {
        OCRReviewView(candidate: candidate, capturedImageData: result.ocrCapturedImageData) { outcome in
            ocrCandidateForReview = nil

            switch outcome {
            case .proceedToScanHub(let result):
                WorkflowTraceStore.log(path: "ocr", step: "review.completed", details: ["destination": "scanHub"])
                // Update the result with the reviewed data
                parsedTagData = result.tagData
            case .retakeSmartScan:
                WorkflowTraceStore.log(path: "ocr", step: "review.retake-smart-scan")
                dismiss()
            case .cancel:
                WorkflowTraceStore.log(path: "ocr", step: "review.cancelled")
            }
        }
    }

    /// Spec 3: Spoolman 0.27 hears about the scan, so a browser paired with
    /// SpoolKid opens the tag's spool. Once per hub (the `.task` can rerun
    /// when the hub reappears); fire-and-forget — the hub never waits for it
    /// and never shows its outcome.
    private func reportScanToSpoolman() {
        guard !didReportScan, store.supportsTagScanReporting,
              let report = TagScanReporter.report(for: result, model: UIDevice.current.model)
        else { return }
        didReportScan = true
        Task {
            if case .failed(let message) = await store.reportTagScan(report) {
                logger.error("Tag scan report to Spoolman failed: \(message, privacy: .public)")
            }
        }
    }

    @MainActor
    private func hubLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .task {
                reportScanToSpoolman()
                await performResolve()
                // One hub instance is one scan. Recorded after resolution so the
                // "matched an existing spool" half is true — that is what makes a
                // scan a success moment rather than just a count.
                let matched: Bool
                switch hubState {
                case .authoritativeSpool, .cardUIDSpool: matched = true
                default: matched = false
                }
                supportPrompts.record(.tagScanCompleted(matchedSpool: matched))
            }
            .onChange(of: secondTagNFCManager.isScanning) { _, isScanning in
                if !isScanning {
                    Task { await handleSecondTagScanCompletion() }
                }
            }
            .onChange(of: secondTagNFCManager.lastLocationWrite) { _, result in
                if case .written(let uid) = result,
                   Self.writeChangesScannedTag(writtenUID: uid, scannedUID: self.result.cardUID) {
                    tagChangedSinceScan = true
                }
                // The only location write this hub issues is "Update This Tag",
                // whose uuid is always the currently-shown payload's — a blocked
                // or failed write already reaches the user via the NFC session's
                // own alert, so there is nothing further to do for those here.
                if case .written(let uid) = result, let uid, case .locationTag(let payload) = hubState {
                    // The entry that owns this tag, which after a name-collision
                    // adoption is not the one the tag's own uuid names. With no
                    // entry there is nothing to list the tag under.
                    if let owner = Self.registryRecord(
                        for: payload, scannedUID: self.result.cardUID, registry: store.locationRegistry
                    ) {
                        store.recordWrittenLocationTag(uid: uid, to: owner.uuid, locationName: owner.name)
                    }
                }
            }
            .onChange(of: secondTagNFCManager.lastClone) { _, cloneResult in
                handleCloneResult(cloneResult)
            }
            .onChange(of: secondTagNFCManager.lastTagClear) { _, clearResult in
                handleTagClear(clearResult)
            }
            .alert(
                "Empty This Tag?",
                isPresented: $showsEraseConfirmation
            ) {
                Button("Erase Tag", role: .destructive) {
                    eraseScannedTag()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(eraseConfirmationMessage)
            }
            .alert(
                "Unlink from \(unlinkOfferSpool?.listTitle ?? "")",
                isPresented: Binding(
                    get: { unlinkOfferSpool != nil },
                    set: { if !$0 { unlinkOfferSpool = nil } }
                ),
                presenting: unlinkOfferSpool
            ) { spool in
                Button("Unlink", role: .destructive) {
                    unlinkOfferSpool = nil
                    Task { await runUnlink(from: spool) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { spool in
                Text("Removes this tag's UID from \(spool.listTitle)'s mapping in \(store.capabilities.displayName). The tag itself is not erased.")
            }
            .alert(
                "Tag Belongs to \(TagCloneService.ownerName(store.owner(ofTagUID: cloneUnlinkOfferUID ?? "")))",
                isPresented: Binding(
                    get: { cloneUnlinkOfferUID != nil },
                    set: { if !$0 { cloneUnlinkOfferUID = nil } }
                ),
                presenting: cloneUnlinkOfferUID
            ) { uid in
                Button("Unlink and Continue", role: .destructive) {
                    cloneUnlinkOfferUID = nil
                    startClone(allowing: uid)
                }
                Button("Cancel", role: .cancel) { cloneUnlinkOfferUID = nil }
            } message: { uid in
                Text("Continuing overwrites it with the copy and unlinks it from \(TagCloneService.ownerName(store.owner(ofTagUID: uid))). You'll hold it against the phone once more.")
            }
            .alert(
                cloneLinkStep.flatMap(TagCloneService.linkAlertCopy(for:))?.title ?? "",
                isPresented: Binding(
                    get: { cloneLinkStep != nil },
                    set: { if !$0 { cloneLinkStep = nil } }
                ),
                presenting: cloneLinkStep
            ) { step in
                Button(TagCloneService.linkAlertCopy(for: step)?.confirm ?? "OK") {
                    cloneLinkStep = nil
                    linkClone(step)
                }
                Button("Not Now", role: .cancel) { cloneLinkStep = nil }
            } message: { step in
                Text(TagCloneService.linkAlertCopy(for: step)?.message ?? "")
            }
            .onChange(of: navigateToChooser) { _, isPresented in
                if !isPresented {
                    chooserAllowAllSpools = false
                    chooserExcludedSpoolIDs = []
                    chooserIntent = nil
                    chooserFilamentTargets = nil
                    transferTagMoveOffer = nil
                    filamentTagMoveSource = nil
                }
            }
    }

    /// Re-resolve plus, for a resolved spool, an explicit spool refetch: the
    /// cascade's mapping tiers only fetch spools when the list is empty, so
    /// re-resolving alone can keep showing the pre-edit embedded filament.
    private func refreshAfterFilamentFormDismissal() async {
        await performResolve()
        switch hubState {
        case .authoritativeSpool(let spool):
            await store.fetchSpools()
            if let refreshed = Self.refreshedSpool(id: spool.id, from: store.spools) {
                hubState = .authoritativeSpool(refreshed)
            }
        case .cardUIDSpool(let spool):
            await store.fetchSpools()
            if let refreshed = Self.refreshedSpool(id: spool.id, from: store.spools) {
                hubState = .cardUIDSpool(refreshed)
            }
        default:
            break
        }
    }

    // MARK: - Resolution

    private var matchResults: [FilamentMatchResult] {
        if case .matchResults(let m) = hubState { return m }
        return []
    }

    private var unifiedResult: UnifiedScanResult? {
        switch hubState {
        case .authoritativeSpool(let spool), .cardUIDSpool(let spool):
            return .spool(spool, effectiveTagData, scannedUID: result.cardUID)
        case .matchResults(let matches):
            if let tagData = effectiveTagData {
                return .filament(tagData, matches.first?.spool.filament, scannedUID: result.cardUID)
            }
            return nil
        case .unknownTag:
            return .uidOnly(result.cardUID ?? "Unknown")
        case .noSpoolman:
            if let tagData = effectiveTagData {
                return .filament(tagData, nil, scannedUID: result.cardUID)
            } else if let uid = result.cardUID {
                return .uidOnly(uid)
            }
            return nil
        case .loading, .parsingWebUrl, .webChallenge, .locationTag, .filamentTag, .backendLabelProblem:
            return nil
        }
    }

    private var newSpoolInitialCardUIDs: [String] {
        guard let uid = result.cardUID else { return [] }
        return Self.newSpoolPrefillUIDs(scannedUID: uid, owner: store.owner(ofTagUID: uid))
    }

    /// Pre-fills the new-spool form with the scanned tag only when nobody
    /// owns it yet. When the shown spool already owns the tag releasably, the
    /// hub uses the move offer instead of this prefill (Task 7); when another
    /// spool or a location owns it — including through `rfid_uid`,
    /// which `TagMoveOffer.make` refuses to offer a move for — pre-filling
    /// here would post the UID into the new spool's `card_uids` while the old
    /// owner keeps it too: two owners, no message (I1, fix round 1).
    nonisolated static func newSpoolPrefillUIDs(scannedUID: String?, owner: TagOwner) -> [String] {
        guard owner == .none, let scannedUID else { return [] }
        let normalized = SpoolMappingService.normalizeUID(scannedUID)
        guard !normalized.isEmpty else { return [] }
        return [normalized]
    }

    private func secondTagActionState(for result: UnifiedScanResult) -> UIDMappingActionState {
        guard case .spool = result else { return .none }
        return Self.uidMappingActionState(
            writesLinks: store.tagIdentity.writesLinks,
            didJustMapCurrentTag: didJustMapCurrentTag,
            isSecondTagScanning: secondTagNFCManager.isScanning
        )
    }

    private func performResolve() async {
        if let locationTag = result.locationTag {
            hubState = .locationTag(locationTag)
            return
        }

        // Only a scan that actually decoded as filament data proves the tag is
        // no longer a location tag. A UID-only result means the read failed or
        // the format is unrecognised — healing there would drop the registry's
        // claim on a tag that IS still a location tag, on one bad read.
        if let uid = result.cardUID, result.tagData != nil {
            Self.healRegistry(afterReadingSpoolTagWithUID: uid, registry: store.locationRegistry)
        }

        WorkflowTraceStore.log(path: "hub", step: "resolve.start", details: [
            "format": result.format?.displayName ?? "",
            "hasURL": String(result.url != nil),
            "hasCardUID": String(result.cardUID != nil),
            "hasResultTagData": String(result.tagData != nil),
            "hasParsedTagData": String(parsedTagData != nil),
            "backend": store.capabilities.kind.rawValue
        ])

        let isUnknown: Bool
        if case .unknownTag = hubState {
            isUnknown = true
        } else {
            isUnknown = false
        }

        if result.format == .webUrl, result.url != nil, parsedTagData == nil, !isUnknown {
            if let url = result.url {
                hubState = .parsingWebUrl(url)
            }
        }

        let resolution = await resolutionService.resolve(
            result,
            effectiveTagData: parsedTagData
        )

        switch resolution {
        case .parsedWebData(let data):
            parsedTagData = data
            await performResolve()
        default:
            if case .spoolIDMismatch(let mismatch, _) = resolution {
                spoolIDMismatch = mismatch
            } else {
                spoolIDMismatch = nil
            }
            hubState = Self.mapResolution(resolution)
            resolutionSource = Self.resolutionSource(from: resolution)
            if result.backendLabel != nil, resolutionSource != nil { resolutionSource = .backendLabel }
        }
    }

    /// The "Search ‹catalogue›" list's loader: run when the list opens, not on
    /// every resolve (on FilaMan it is a few requests, and the list is reached
    /// from one tile of one kind of scan).
    private func loadNewSpoolCandidates() async -> ScanResolutionService.CandidateLoad {
        guard let tagData = effectiveTagData else {
            return ScanResolutionService.CandidateLoad(candidates: [], catalogue: .noBrand)
        }
        return await resolutionService.newSpoolSourceCandidates(for: tagData)
    }

    /// The filament a filament-only scan's actions work on: the user's saved
    /// edits (adopted) win over the heuristic match.
    nonisolated static func workingFilament(adopted: Filament?, matched: Filament?) -> Filament? {
        adopted ?? matched
    }

    /// The tag data the filament card displays: the adopted filament's values
    /// when the user saved one from this hub, the scanned payload otherwise.
    /// MainActor: `FilamentTagData.from` derives subtypes via MainActor code.
    @MainActor
    static func displayedFilamentData(adopted: Filament?, tagData: FilamentTagData) -> FilamentTagData {
        adopted.map(FilamentTagData.from) ?? tagData
    }

    nonisolated static func createSpoolFailureMessage(backendName: String, detail: String?) -> String {
        let reason = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reason.isEmpty else { return "Could not create the filament in \(backendName)." }
        return "Could not create the filament in \(backendName): \(reason)"
    }

    /// Source attribution for the displayed filament data.
    /// - on-tag payload decode → "Read from tag · <format>"
    /// - OCR label read         → "Read from label · OCR Scan"
    /// - web-page parse fallback → "Parsed from web · <host>"
    /// - otherwise (UID-only, plain spool match) → nil
    nonisolated static func provenanceCaption(
        format: ScanResult.DetectedFormat?,
        hasParsedWebData: Bool,
        webHost: String?
    ) -> String? {
        switch format {
        case .openSpool: return "Read from tag · OpenSpool"
        case .openPrintTag: return "Read from tag · OpenPrintTag"
        case .openTag3D: return "Read from tag · OpenTag3D"
        case .anycubicACE: return "Read from tag · Anycubic ACE"
        case .elegoo: return "Read from tag · ELEGOO"
        case .tigerTag: return "Read from tag · TigerTag"
        case .ocr: return "Read from label · OCR Scan"
        // A label carries no filament data, only a record ID.
        case .backendLabel: return nil
        case .webUrl: return hasParsedWebData ? "Parsed from web · \(webHost ?? "web")" : nil
        case nil: return nil
        }
    }

    /// The provenance of a resolution outcome, for the caption. Manual spool
    /// assignments made inside the hub set `.manualChoice` at their own sites.
    nonisolated static func resolutionSource(
        from resolution: ScanResolutionService.Resolution
    ) -> HubResolutionSource? {
        switch resolution {
        case .authoritativeSpool:
            return .embeddedSpoolID
        case .cardUIDSpool(_, let source):
            switch source {
            case .cardUIDs: return .spoolLinkMapping
            case .onDeviceLedger: return .onDeviceLedger
            case .spoolIDMigration: return .spoolIDMigration
            }
        case .spoolIDMismatch(_, let otherwise):
            return resolutionSource(from: otherwise)
        case .matchResults(let results):
            return .heuristicMatch(topConfidence: results.first?.confidence ?? 0)
        // "found by its tag link": the footer's wording for any link.
        case .filamentTag:
            return .spoolLinkMapping
        case .unknownTag, .noMatch, .needsWebChallenge, .parsedWebData, .backendLabelProblem:
            return nil
        }
    }

    /// The spool a tap on the result card should open for EDITING, or nil
    /// when the card is not a resolved spool. Until 2026-08-24 the tap set
    /// `navigateToCreateSpool`, so tapping a spool the hub had just identified
    /// opened the *create* form — seeded with the scanned tag's UID, so saving
    /// it produced a second spool that took the tag with it while every edit
    /// the user made was written to a spool they had never asked for.
    nonisolated static func spoolToEditOnCardTap(_ result: UnifiedScanResult) -> Spool? {
        guard case .spool(let spool, _, _) = result else { return nil }
        return spool
    }

    /// The store's current copy of a spool the hub is displaying, or nil if it
    /// is gone (deleted from the form). Nil is not "keep the old one": the
    /// stale copy is no longer a fact about the backend.
    nonisolated static func refreshedSpool(id: Int, from spools: [Spool]) -> Spool? {
        spools.first { $0.id == id }
    }

    /// The tags a Create New Spool or a Transfer Tag takes: only a scan whose
    /// tag belongs to the resolved spool has any. Create passes it to the form
    /// only when SpoolLink will store the move; Transfer always passes it and
    /// `moveReusableUIDs` explains when it cannot store it.
    nonisolated static func tagMoveOffer(for result: UnifiedScanResult) -> TagMoveOffer? {
        guard case .spool(let spool, _, let scannedUID) = result else { return nil }
        return TagMoveOffer.make(scannedUID: scannedUID, source: spool)
    }

    /// The moved tags the created spool holds after its save — only these
    /// leave the source. A tag the new spool's link write did not land stays
    /// on the source instead of ending up on no spool (final review
    /// 2026-10-11). Order and spelling follow `moved`.
    nonisolated static func tagsTakenByCreatedSpool(moved: [String], created: Spool) -> [String] {
        let held = Set(created.writableCardUIDs.map(SpoolMappingService.normalizeUID))
        return moved.filter { held.contains(SpoolMappingService.normalizeUID($0)) }
    }

    /// Whether a spool the create form just saved holds the scanned tag — the
    /// form posts the scanned UID only with SpoolLink on, and the user can
    /// remove it before saving, so the hub asks the saved spool rather than
    /// assuming either way.
    nonisolated static func createdSpoolTakesScannedTag(scannedUID: String?, created: Spool) -> Bool {
        guard let scannedUID else { return false }
        let scanned = SpoolMappingService.normalizeUID(scannedUID)
        guard !scanned.isEmpty else { return false }
        return created.mappedCardUIDs.map(SpoolMappingService.normalizeUID).contains(scanned)
    }

    /// The filament the create-spool form must come preselected with when this
    /// scan's create action fires — the spool the hub is showing — or nil when
    /// the hub shows no filament. Until 2026-09 the `.spool`-scenario create
    /// buttons navigated without setting `newSpoolInitialFilamentId`, so the
    /// form's legacy "last used filament" fallback preselected the previously
    /// saved spool's filament instead of the one on the hub card. Nil is a
    /// real answer (`.uidOnly` shows no filament; the form's fallback applies
    /// there), not a gap to be filled with a heuristic.
    nonisolated static func initialFilamentIdForCreateSpool(_ result: UnifiedScanResult) -> Int? {
        guard case .spool(let spool, _, _) = result else { return nil }
        return spool.filament.id
    }

    private static func mapResolution(_ resolution: ScanResolutionService.Resolution) -> HubState {
        switch resolution {
        case .authoritativeSpool(let spool):
            return .authoritativeSpool(spool)
        case .cardUIDSpool(let spool, _):
            return .cardUIDSpool(spool)
        case .matchResults(let results):
            return .matchResults(results)
        case .unknownTag:
            return .unknownTag
        case .noMatch:
            return .noSpoolman
        case .needsWebChallenge(let url):
            return .webChallenge(url)
        case .parsedWebData:
            return .loading
        case .spoolIDMismatch(_, let otherwise):
            return mapResolution(otherwise)
        case .filamentTag(let filament):
            return .filamentTag(filament)
        case .backendLabelProblem(let problem):
            return .backendLabelProblem(problem)
        }
    }

    private func handleWebChallengeSuccess(html: String, url: URL) async {
        hubState = .parsingWebUrl(url)
        do {
            let parsed = try resolutionService.parseWebChallengeHTML(html, url: url)
            parsedTagData = parsed
            await performResolve()
        } catch {
            logger.error("Failed to parse html after challenge: \(error.localizedDescription, privacy: .public)")
            hubState = .unknownTag
        }
    }

    // MARK: - UID Persistence

    private func persistUIDIfNeeded(to spool: Spool, replacing: Bool = false) async {
        guard let uid = result.cardUID else { return }
        // Returned silently on the SpoolLink switch until 2026-08-25: the hub
        // then rendered the chosen spool as the scan's answer, which looks
        // exactly like a mapping and is not one. Link Tag is hidden outside
        // Tag Links, so this is the backstop for a link request that gets
        // here anyway.
        guard store.tagIdentity.writesLinks else {
            persistenceError = TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel)
            return
        }
        if !replacing, let question = replaceQuestion(for: spool, uid: uid) {
            // The chooser already showed this spool as the answer; until the
            // person decides, say the tag is not linked.
            persistenceError = TagStoreText.filamanOneTagNote(existing: question.existing)
            replaceContinuation = .chooser
            replaceRequest = question
            return
        }
        let outcome = await TagLinkService.assign(uid, to: spool, in: store, replacing: replacing)
        // Only a mapping that reached the server earns "this tag is mapped" —
        // and with it the "Scan another tag" affordance.
        didJustMapCurrentTag = outcome.didWrite
        persistenceError = outcome.followUpNote
        // The hub holds the chooser's pre-link copy. Left stale, the plan
        // (which reads the live store) offered Transfer while the tag-move
        // offer (which reads this copy) found no tag to move, so Create gave
        // the tag a second owner.
        if outcome.didWrite, let refreshed = Self.refreshedSpool(id: spool.id, from: store.spools) {
            hubState = .authoritativeSpool(refreshed)
        }
    }

    /// Link Anyway: asks first when FilaMan's one tag would be replaced.
    /// The link itself is `linkMismatchedTag`.
    private func linkAnyway(_ mismatch: SpoolIDMismatch, replacing: Bool) async {
        if !replacing, let question = replaceQuestion(for: mismatch.spool, uid: result.cardUID) {
            isAnsweringMismatch = false
            replaceContinuation = .mismatch(mismatch)
            replaceRequest = question
            return
        }
        await linkMismatchedTag(mismatch, replacing: replacing)
    }

    /// Link Anyway, and the first half of Overwrite: the user has said the
    /// tag is this spool's. True only when the link landed.
    @discardableResult
    private func linkMismatchedTag(_ mismatch: SpoolIDMismatch, replacing: Bool = false) async -> Bool {
        // Set (again) and always released here: the buttons set it before
        // their Task starts, and an early return must not leave the card
        // disabled.
        isAnsweringMismatch = true
        defer { isAnsweringMismatch = false }
        guard let uid = result.cardUID else { return false }
        let outcome = await TagLinkService.assign(uid, to: mismatch.spool, in: store, replacing: replacing)
        guard outcome.didWrite else {
            spoolIDMismatch = mismatch.withLinkError(
                outcome.failure ?? "The tag could not be linked to \(mismatch.spool.listTitle)."
            )
            return false
        }
        persistenceError = outcome.followUpNote
        hubState = .authoritativeSpool(Self.refreshedSpool(id: mismatch.spool.id, from: store.spools) ?? mismatch.spool)
        resolutionSource = .spoolIDMigration
        spoolIDMismatch = nil
        return true
    }

    /// Link first, then write the spool's data in the tag's own format. A
    /// cancelled write keeps the link: the user said the tag is this spool's.
    private func overwriteMismatchedTag(_ mismatch: SpoolIDMismatch, replacing: Bool) async {
        if !replacing, let question = replaceQuestion(for: mismatch.spool, uid: result.cardUID) {
            isAnsweringMismatch = false
            replaceContinuation = .overwrite(mismatch)
            replaceRequest = question
            return
        }
        guard await linkMismatchedTag(mismatch, replacing: replacing) else { return }
        writeInitialData = FilamentTagData.from(spool: mismatch.spool)
        writeInitialFormat = result.format?.tagFormat
        navigateToWriteTag = true
    }

    /// The existing create-from-tag route; the form links the UID on save.
    /// The card stays until the form opens: if find-or-create fails, the
    /// question is still unanswered. A second tap meanwhile would race a
    /// second find-or-create and could add the vendor and filament twice.
    private func createSpoolFromMismatchedTag() {
        guard !isPreparingCreateSpool, let tagData = effectiveTagData else { return }
        createSpool(fromScannedFilament: tagData) { spoolIDMismatch = nil }
    }

    /// Spec 4: releases the scanned tag from its filament, then resolves the
    /// scan again — the tag now answers as whatever else knows it.
    private func unlinkFilamentTag(from filament: Filament) async {
        guard let uid = result.cardUID else { return }
        filamentTagError = nil
        if await store.unlinkFilamentTag(filamentId: filament.id, uid: uid) {
            await performResolve()
        } else {
            filamentTagError = store.errorMessage ?? "The tag could not be unlinked from \(filament.listTitle)."
        }
    }

    /// Spec 2026-10-11: the chooser's Filaments tab, for Transfer Tag and
    /// Link Tag… alike. Moves the ticked tags of a spool's transfer, else the
    /// scanned tag, each from whatever holds it. The UIDs are read here,
    /// before the chooser closes: its dismissal clears the offer.
    private func moveScannedTags(to filament: Filament, movedUIDs: [String]) {
        let uids: [String]
        if transferTagMoveOffer != nil, !movedUIDs.isEmpty {
            uids = movedUIDs
        } else if let scanned = result.cardUID.map(SpoolMappingService.normalizeUID), !scanned.isEmpty {
            uids = [scanned]
        } else {
            return
        }
        filamentTagMoveSource = nil
        filamentTagError = nil
        persistenceError = nil
        Task {
            switch await TagHolderMove.moveToFilament(uids: uids, to: filament, in: store) {
            case .saved:
                break
            case .savedWithCaveat(let message), .notSaved(let message):
                // Shown on whichever card follows the re-resolve.
                filamentTagError = message
                persistenceError = message
            }
            clearReusableMoveContext()
            // Re-resolved whatever the outcome: a failed relink may already
            // have unlinked a tag.
            await performResolve()
        }
    }

    private func handleManualSelection(spool: Spool) {
        hubState = .authoritativeSpool(spool)
        resolutionSource = .manualChoice
        didJustMapCurrentTag = false
        Task {
            await persistUIDIfNeeded(to: spool)
        }
    }

    private func handleChooserSelection(spool: Spool, movedUIDs: [String]) {
        // Spec 4: the chooser was picking where the filament's tag moves.
        if filamentTagMoveSource != nil, let uid = result.cardUID {
            filamentTagMoveSource = nil
            Task {
                let outcome = await TagHolderMove.moveToSpool(
                    uid: uid, from: store.owner(ofTagUID: uid), to: spool, in: store
                )
                // Resolved again either way: a failed relink still unlinked
                // the tag, so the filament card would be stale. The message
                // shows on whichever card follows.
                if case .notSaved(let message) = outcome {
                    filamentTagError = message
                    persistenceError = message
                }
                await performResolve()
            }
            return
        }
        if let offer = transferTagMoveOffer, !movedUIDs.isEmpty,
           let source = store.spools.first(where: { $0.id == offer.sourceSpoolID }) {
            Task {
                _ = await moveReusableUIDs(to: spool, sourceSpool: source, movedUIDs: movedUIDs)
            }
            return
        }

        switch Self.chooserSelectionAction(intent: chooserIntent, spool: spool) {
        case .navigateToWriteTag(let tagData):
            writeInitialData = tagData
            writeInitialFormat = nil
            navigateToWriteTag = true
        case .persistUID:
            handleManualSelection(spool: spool)
        }
    }

    private func handleSavedSpoolFromForm(
        _ newSpool: Spool,
        sourceSpool: Spool?,
        movedUIDs: [String]
    ) async {
        guard let sourceSpool, !movedUIDs.isEmpty else { return }
        // The form linked the ticked tags to the new spool; the source loses
        // only those the new spool now holds. A failure to clear the source is
        // a caveat, never a failure of the whole move: the new spool holds the
        // tags, so nothing is lost — the old spool just still holds them too.
        let created = Self.refreshedSpool(id: newSpool.id, from: store.spools) ?? newSpool
        let taken = Self.tagsTakenByCreatedSpool(moved: movedUIDs, created: created)
        let takenSet = Set(taken.map(SpoolMappingService.normalizeUID))
        let stayed = movedUIDs.filter { !takenSet.contains(SpoolMappingService.normalizeUID($0)) }
        var notes: [String?] = []
        if store.tagIdentity.linkTargets.contains(.filamanTags) {
            // FilaMan Tags: the source may hold a tag in rfid_uid, which the
            // new spool could not claim. Each tag moves release-before-claim.
            notes.append(await TagLinkService.moveTags(movedUIDs, to: created, in: store).followUpNote)
            persistenceError = SaveOutcome.combinedNote(notes)
            hubState = .authoritativeSpool(Self.refreshedSpool(id: newSpool.id, from: store.spools) ?? created)
            resolutionSource = .manualChoice
            clearReusableMoveContext()
            return
        }
        if !taken.isEmpty {
            let remaining = TagMoveOffer.remainingSourceUIDs(of: sourceSpool, moved: taken)
            let cleared = await TagLinkService.writeCardUIDs(
                spoolId: sourceSpool.id,
                uids: remaining,
                failureFallback: "The new spool has the tag mapping, but it is still mapped to "
                    + "\(sourceSpool.listTitle).",
                in: store
            )
            notes.append(cleared.followUpNote)
        }
        if !stayed.isEmpty {
            notes.append("\(stayed.joined(separator: ", ")) stayed on \(sourceSpool.listTitle): "
                + "the new spool did not take \(stayed.count == 1 ? "it" : "them").")
        }
        persistenceError = SaveOutcome.combinedNote(notes)
        hubState = .authoritativeSpool(created)
        resolutionSource = .manualChoice
        clearReusableMoveContext()
    }

    private func clearReusableMoveContext() {
        transferTagMoveOffer = nil
        createTagMoveOffer = nil
        chooserAllowAllSpools = false
        chooserExcludedSpoolIDs = []
    }

    @discardableResult
    private func moveReusableUIDs(
        to destinationSpool: Spool,
        sourceSpool: Spool,
        movedUIDs: [String]
    ) async -> Bool {
        guard store.tagIdentity.writesLinks else {
            persistenceError = TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel)
            return false
        }

        guard destinationSpool.id != sourceSpool.id else {
            persistenceError = "Please choose a different destination spool."
            return false
        }

        // FilaMan Tags: written destination-first, a tag the source holds in
        // rfid_uid would end in no spool's rfid_uid. Each tag moves through
        // the single-owner assign instead (release before claim).
        if store.tagIdentity.linkTargets.contains(.filamanTags) {
            let outcome = await TagLinkService.moveTags(movedUIDs, to: destinationSpool, in: store)
            guard outcome.didWrite else {
                persistenceError = outcome.failure ?? store.errorMessage
                return false
            }
            hubState = .authoritativeSpool(
                store.spools.first { $0.id == destinationSpool.id } ?? destinationSpool
            )
            resolutionSource = .manualChoice
            didJustMapCurrentTag = false
            persistenceError = outcome.caveat
            clearReusableMoveContext()
            return outcome.caveat == nil
        }

        let destUIDs = TagMoveOffer.destinationUIDs(of: destinationSpool, adding: movedUIDs)
        let destinationUpdated = await store.setCardUIDs(spoolId: destinationSpool.id, uids: destUIDs)

        guard destinationUpdated else {
            persistenceError = "Failed to update destination spool tag mappings."
            return false
        }

        let srcUIDs = TagMoveOffer.remainingSourceUIDs(of: sourceSpool, moved: movedUIDs)
        let sourceUpdated = await store.setCardUIDs(spoolId: sourceSpool.id, uids: srcUIDs)

        if let refreshedDestination = store.spools.first(where: { $0.id == destinationSpool.id }) {
            hubState = .authoritativeSpool(refreshedDestination)
        } else {
            hubState = .authoritativeSpool(destinationSpool)
        }
        resolutionSource = .manualChoice

        if !sourceUpdated {
            persistenceError = "Tag mapping moved to destination spool, but source spool could not be cleaned up."
            clearReusableMoveContext()
            return false
        }

        didJustMapCurrentTag = false
        persistenceError = nil
        clearReusableMoveContext()
        return true
    }

    // MARK: - Clone Tag

    private var cloneOwner: TagCloneService.Owner {
        var locationRecord: LocationRecord?
        if case .locationTag(let payload) = hubState {
            locationRecord = Self.registryRecord(for: payload, scannedUID: result.cardUID, registry: store.locationRegistry)
        }
        return TagCloneService.sourceOwner(
            hubState: hubState,
            locationRecord: locationRecord,
            ledger: TagAssociationStore.shared.snapshot(),
            spools: store.spools
        )
    }

    /// `allowedUID` is the one claimed tag the user agreed to take; a fresh tap
    /// passes nil, which also forgets any earlier agreement.
    private func startClone(allowing allowedUID: String?) {
        guard let snapshot = result.tagSnapshot else { return }
        pendingCloneUnlinkUID = allowedUID
        var claimed = store.tagMappedUIDs.union(store.filamentTagUIDs)
        for record in store.locationRegistry?.records ?? [] {
            claimed.formUnion(record.tagUIDs)
        }
        tagRun = resolvedTagRun
        secondTagNFCManager.cloneTag(
            snapshot,
            sourceUID: result.cardUID,
            blockedUIDs: TagCloneService.blockedUIDs(claimed: claimed, owner: cloneOwner),
            allowedUID: allowedUID,
            reader: tagRun.reader
        )
    }

    private var resolvedTagRun: TagReaderRun {
        .start(tagReader, purpose: .write(format: result.format?.tagFormat), printer: printer, store: store)
    }

    private func handleCloneResult(_ cloneResult: NFCManager.CloneWriteResult?) {
        // `cloneTag` resets `lastClone` to nil as it starts; that is not an
        // outcome, and must not forget the tag the user just agreed to take.
        guard cloneResult != nil else { return }
        let followUp = TagCloneService.followUp(
            after: cloneResult,
            pendingUnlinkUID: pendingCloneUnlinkUID,
            owner: cloneOwner,
            writesLinks: store.tagIdentity.writesLinks
        )
        pendingCloneUnlinkUID = nil

        switch followUp {
        case .nothing:
            break
        case .offerUnlink(let uid):
            cloneUnlinkOfferUID = uid
        case .releaseThenLink(let uid, let step):
            Task {
                if let note = await TagCloneService.releasePreviousOwner(uid: uid, store: store) {
                    store.postSaveNotice(note, record: nil)
                }
                presentCloneLinkStep(step)
            }
        case .link(let step):
            presentCloneLinkStep(step)
        }
    }

    private func presentCloneLinkStep(_ step: TagCloneService.LinkStep) {
        switch step {
        case .none:
            break
        case .askToLinkSpool, .askToAddToLocation:
            cloneLinkStep = step
        }
    }

    private func linkClone(_ step: TagCloneService.LinkStep) {
        Task {
            if let note = await TagCloneService.link(step, store: store) {
                store.postSaveNotice(note, record: nil)
            }
            // The card's spool is a copy taken at resolve time. Without this a
            // second clone would treat the first copy as another owner's tag.
            if case .askToLinkSpool(let spoolID, _, _) = step,
               let refreshed = Self.refreshedSpool(id: spoolID, from: store.spools) {
                hubState = .authoritativeSpool(refreshed)
            }
        }
    }

    private func handleSecondTagScanCompletion() async {
        guard let targetSpoolId = secondTagTargetSpoolId else { return }
        defer {
            secondTagNFCManager.scanResult = nil
            secondTagTargetSpoolId = nil
        }

        guard let scan = secondTagNFCManager.scanResult else { return }

        guard let targetSpool = store.spools.first(where: { $0.id == targetSpoolId }) else {
            persistenceError = "Could not find the selected spool to store second tag mapping."
            return
        }

        if scan.locationTag == nil, let question = replaceQuestion(for: targetSpool, uid: scan.cardUID) {
            persistenceError = TagStoreText.filamanOneTagNote(existing: question.existing)
            replaceContinuation = .secondTag(scan)
            replaceRequest = question
            return
        }
        await finishSecondTagLink(scan, to: targetSpool, replacing: false)
    }

    private func finishSecondTagLink(_ scan: ScanResult, to targetSpool: Spool, replacing: Bool) async {
        persistenceError = await TagLinkService.linkScanned(scan, to: targetSpool, in: store, replacing: replacing)

        if let refreshed = store.spools.first(where: { $0.id == targetSpool.id }) {
            hubState = .authoritativeSpool(refreshed)
        }
    }

    private func createNewSpool(from selectedSource: ScanResolutionService.NewSpoolSource) {
        newSpoolTagWeights = effectiveTagData.map { TagSpoolWeights(tagData: $0, format: result.format) }
        createSpoolError = nil
        isPreparingCreateSpool = true

        Task {
            switch selectedSource {
            case .local(let filament):
                await MainActor.run {
                    newSpoolInitialFilamentId = filament.id
                    isPreparingCreateSpool = false
                    navigateToCreateSpool = true
                }

            case .spoolmanDB(let dbBest):
                if store.vendors.isEmpty {
                    await store.fetchVendors()
                }

                let importedFilament = await resolutionService.importDBFilamentIfNeeded(dbBest)
                await MainActor.run {
                    isPreparingCreateSpool = false
                    if let importedFilament {
                        newSpoolInitialFilamentId = importedFilament.id
                        navigateToCreateSpool = true
                    } else {
                        createSpoolError = "Could not import the suggested \(catalogName) filament."
                    }
                }
            }
        }
    }

    // MARK: - Tag maintenance (Empty This Tag / Unlink)

    private func eraseScannedTag() {
        WorkflowTraceStore.log(path: "hub", step: "erase.start", details: [
            "uid": result.cardUID ?? "",
            "backend": store.capabilities.kind.rawValue,
            "rawPages": String(result.tagSnapshot?.pageWrites.count ?? 0)
        ])
        // A raw-format tag (ACE, TigerTag, ELEGOO) is erased by zeroing the
        // pages its scan saw — an NDEF write would be refused, the format is
        // not NDEF. NDEF scans pass no pages and take the NDEF path.
        tagRun = resolvedTagRun
        secondTagNFCManager.clearTag(
            expectedUID: result.cardUID,
            zeroPages: result.tagSnapshot?.pageWrites.map(\.page) ?? [],
            reader: tagRun.reader
        )
    }

    /// `.cleared` needs no note here — the NFC sheet itself said "Tag cleared."
    /// The failure cases do need the hub's note line: a wrong tag or a refused
    /// erase is a surprise the sheet's dismissal alone does not explain.
    private func handleTagClear(_ clearResult: NFCManager.TagClearResult?) {
        guard let clearResult else { return }
        let outcome: String
        switch clearResult {
        case .cleared: outcome = "cleared"
        case .wrongTag: outcome = "wrongTag"
        case .failed: outcome = "failed"
        }
        WorkflowTraceStore.log(path: "hub", step: "erase.result", details: [
            "outcome": outcome,
            "backend": store.capabilities.kind.rawValue
        ])
        switch clearResult {
        case .cleared:
            tagChangedSinceScan = true
        case .wrongTag:
            persistenceError = "That was a different tag, so nothing was changed."
        case .failed(let reason):
            persistenceError = reason
        }
    }

    /// Names the current owner so "empty" cannot silently strand a claim:
    /// erasing is physical — the mapping survives, and the sentence says so.
    private var eraseConfirmationMessage: String {
        var message = "Erases everything written on the tag. This cannot be undone."
        guard let uid = result.cardUID else { return message }
        switch store.owner(ofTagUID: uid) {
        case .spool(_, let label):
            message += " The tag stays mapped to \(label) in \(store.capabilities.displayName) — unlink it separately if you want it released."
        case .filament(_, let label):
            message += " The tag stays linked to the filament \(label) in \(store.capabilities.displayName)."
        case .location(let name):
            message += " The tag stays registered to \(name) — remove it there if you want it released."
        case .none:
            break
        }
        return message
    }

    private func runUnlink(from spool: Spool) async {
        guard let uid = result.cardUID else { return }
        WorkflowTraceStore.log(path: "hub", step: "unlink.start", details: [
            "uid": uid,
            "spool": String(spool.id),
            "backend": store.capabilities.kind.rawValue
        ])
        let note = await TagLinkService.unlink(uid, from: spool, in: store)
        persistenceError = note
        WorkflowTraceStore.log(path: "hub", step: "unlink.result", details: [
            "clean": String(note == nil),
            "backend": store.capabilities.kind.rawValue
        ])
        await performResolve()
    }

    // MARK: - Subviews

    @ViewBuilder
    private func hubSections(for unified: UnifiedScanResult) -> some View {
        // Once per render: it reads the ledger snapshot and scans every spool.
        let linkState = self.linkState
        let plan = actionPlan(for: unified, linkState: linkState)
        let backendName = store.capabilities.displayName
        let busy: Set<HubTileID> = isPreparingCreateSpool ? [.createNewSpool] : []

        VStack(alignment: .leading, spacing: 20) {
            // Filament first, then Spool (owner, 2026-10-11).
            if let section = plan.filamentSection {
                HubEntitySection(
                    title: "Filament", section: section, showsTagData: $showsTagPayload,
                    backendName: backendName, busyTiles: busy,
                    infoLines: HubActionPlan.infoLines(
                        for: section, spoolTitle: nil, unlinkTargetTitle: nil, backendName: backendName,
                        filamentRowCreates: { () -> Bool in
                            if case .filament = unified { return true }
                            return false
                        }(),
                        offersFilamentTargets: store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore),
                        catalogName: catalogName
                    ),
                    showsIntroTip: true,
                    onTile: { performTile($0, for: unified) }
                ) { filamentRow(for: unified) }
            }
            // Errors sit under the section whose actions produce them (C8: .body).
            if let createSpoolError {
                Text(createSpoolError).font(.body).foregroundStyle(.red)
            }
            if let section = plan.spoolSection {
                HubEntitySection(
                    title: "Spool", section: section, showsTagData: $showsTagPayload,
                    backendName: backendName, busyTiles: busy,
                    infoLines: HubActionPlan.infoLines(
                        for: section,
                        spoolTitle: { () -> String? in
                            if case .spool(let spool, _, _) = unified { return spool.listTitle }
                            return nil
                        }(),
                        unlinkTargetTitle: unlinkTarget(for: linkState)?.listTitle,
                        backendName: backendName,
                        filamentRowCreates: false,
                        offersFilamentTargets: store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore),
                        catalogName: catalogName
                    ),
                    // The intro tip goes on the first (i) on screen.
                    showsIntroTip: plan.filamentSection == nil,
                    onTile: { performTile($0, for: unified) }
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        spoolRow(for: unified, linkState: linkState)
                        if case .spool(let spool, _, _) = unified {
                            HubSpoolWeightCard(spool: spool, onEditSpool: {
                                spoolBeingEdited = spool
                                editsSpoolAtWeight = true
                                navigateToEditSpool = true
                            }, onSaved: { refreshed in
                                hubState = .authoritativeSpool(refreshed)
                            })
                            // Keeps the card's own state (its boxes, its
                            // confirmation line) with the spool it belongs to,
                            // and resets it if the hub shows a different one.
                            .id(spool.id)
                        }
                    }
                }
            }
            if let persistenceError {
                Text(persistenceError).font(.body).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func spoolRow(for unified: UnifiedScanResult, linkState: HubLinkState) -> some View {
        switch unified {
        case .spool(let spool, _, let scannedUID):
            HubEntityRow(
                title: "Spool #\(spool.id)",
                subtitle: HubActionPlan.spoolRowSubtitle(
                    spool: spool, scannedUID: scannedUID, isLinked: linkState.isLinked
                ),
                onTap: {
                    spoolBeingEdited = Self.spoolToEditOnCardTap(unified)
                    navigateToEditSpool = spoolBeingEdited != nil
                }
            )
        case .filament:
            HubEntityRow(
                title: HubActionPlan.unresolvedSpoolRowTitle(linkState: linkState, spools: store.spools),
                subtitle: nil, isMuted: true, onTap: nil
            )
        case .uidOnly(let uid):
            HubEntityRow(
                title: HubActionPlan.unresolvedSpoolRowTitle(linkState: linkState, spools: store.spools),
                subtitle: (result.undecodedTagNote.map { "\($0) · " } ?? "")
                    + "UID \(SpoolMappingService.normalizeUID(uid))",
                isMuted: true, onTap: nil
            )
            .contextMenu {
                Button("Copy UID") { UIPasteboard.general.string = SpoolMappingService.normalizeUID(uid) }
            }
        }
    }

    @ViewBuilder
    private func filamentRow(for unified: UnifiedScanResult) -> some View {
        let isACE = result.format == .anycubicACE
        switch unified {
        case .spool(let spool, let tagData, _):
            let labels = (showsTagPayload ? tagData : nil)
                .map { $0.displayLabels(nameBelowDescriptor: isACE) }
                ?? HubActionPlan.backendLabels(spool: spool, tagData: tagData, nameBelowDescriptor: isACE)
            HubEntityRow(
                title: labels.headline,
                subtitle: [labels.secondary, tagData?.opacityText]
                    .compactMap { $0 }.joined(separator: " · "),
                swatchColors: showsTagPayload
                    ? (tagData?.colors ?? spool.filament.colors)
                    : (spool.filament.colors.hexes.isEmpty ? tagData?.colors : spool.filament.colors),
                badge: tagData.map { HubActionPlan.tagDiffers(tagData: $0, filament: spool.filament) } == true
                    ? "tag differs" : nil,
                onTap: { filamentFormRequest = .editExisting(spool.filament) }
            )
        case .filament(let tagData, _, _):
            let display = Self.displayedFilamentData(adopted: adoptedFilament, tagData: tagData)
            let labels = display.displayLabels(nameBelowDescriptor: isACE)
            HubEntityRow(
                title: labels.headline,
                subtitle: [labels.secondary, tagData.opacityText, Self.heuristicMatchLabel(resolutionSource)]
                    .compactMap { $0 }.joined(separator: " · "),
                swatchColors: display.colors,
                badge: adoptedFilament != nil ? "Edited" : nil,
                onTap: { filamentFormRequest = .createFromTagData(display) }
            )
        case .uidOnly:
            EmptyView()
        }
    }

    /// State 3's "matched 100%": the heuristic percentage lives in the
    /// filament row, not the footer.
    nonisolated static func heuristicMatchLabel(_ source: HubResolutionSource?) -> String? {
        guard case .heuristicMatch(let confidence) = source else { return nil }
        return "matched \(confidence)%"
    }

    /// "This tag matched nothing here", in ONE place. The unknown-tag card and
    /// the card below sit six lines apart and disagreed: this one had been
    /// generalised to the active backend, that one still read "No Spoolman
    /// Mapping Found" on every backend (I4).
    ///
    /// On-device storage keeps its links as Tags in your library, not a
    /// server's "mapping", so it gets a different sentence rather than a
    /// renamed one — "No Library Mapping Found" would name the wrong thing.
    static func noMappingHeadline(_ capabilities: BackendCapabilities) -> String {
        capabilities.isOnDeviceStorage
            ? "No Matching Spool"
            : "No \(capabilities.displayName) Mapping Found"
    }

    @ViewBuilder
    private func backendLabelProblemCard(_ problem: ScanResolutionService.BackendLabelProblem) -> some View {
        Label(
            Self.backendLabelProblemMessage(problem, capabilities: store.capabilities),
            systemImage: "qrcode"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    nonisolated static func backendLabelProblemMessage(
        _ problem: ScanResolutionService.BackendLabelProblem, capabilities: BackendCapabilities
    ) -> String {
        switch problem {
        case .otherBackend(let origin):
            return "This label was printed by \(origin.displayName), but SpoolKid is using \(capabilities.storageNoun). Switch backends to open it."
        case .notFound(.spool(let id)):
            return "Spool #\(id) from this label is not in \(capabilities.displayName). It may have been deleted."
        case .notFound(.filament(let id)):
            return "Filament #\(id) from this label is not in \(capabilities.displayName). It may have been deleted."
        }
    }

    private func noMappingCard(capabilities: BackendCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                Self.noMappingHeadline(capabilities),
                systemImage: capabilities.isOnDeviceStorage ? "plus.circle" : capabilities.tabSymbol
            )
            .font(.headline)
            .foregroundStyle(.secondary)
            Text(
                capabilities.isOnDeviceStorage
                    ? "No spool in your library matched this tag. You can create a new spool or save the data manually."
                    : "No spool in your \(capabilities.displayName) library matched this tag. You can write a new tag or save the data manually."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}
