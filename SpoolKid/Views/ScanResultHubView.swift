//
//  ScanResultHubView.swift
//  SpoolKid
//
//  Purpose: Universal post-scan destination for all NFC tag formats.
//
//  Routing logic (in priority order):
//  1. Authoritative embedded spool ID  → show confirmed Spoolman spool
//  2. card_uid match in Spoolman lot_nr → show confirmed Spoolman spool
//  3. Heuristic filament match          → show top match (auto-accept or chooser)
//  4. Encrypted / unknown tag           → show UID-only card
//
//  Secondary actions always available: Write to New Tag, Save to Recent Tags.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import UIKit

struct ScanResultHubView: View {
    let result: ScanResult

    @StateObject private var spoolmanService = SpoolmanService()
    @StateObject private var spoolmanDBService = SpoolmanDBService.shared
    @StateObject private var recentTagManager = RecentTagManager()
    @StateObject private var secondTagNFCManager = NFCManager()

    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage(AppConfig.spoolmanPersistCardUIDKey) private var persistCardUID: Bool = false
    @AppStorage("write_spool_id") private var writeSpoolId: Bool = true

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    enum HubState {
        case loading
        case authoritativeSpool(SpoolmanSpool)
        case cardUIDSpool(SpoolmanSpool)
        case matchResults([FilamentMatchResult])
        case unknownTag
        case noSpoolman
    }

    @State private var hubState: HubState = .loading
    @State private var navigateToWriteTag = false
    @State private var navigateToChooser = false
    @State private var navigateToCreateSpool = false
    @State private var navigateToMoreFilaments = false
    @State private var writeInitialData: FilamentTagData? = nil
    @State private var savedToRecent = false
    @State private var showSlotReplacementAlert = false
    @State private var slotReplacementContext: SlotReplacementContext? = nil
    @State private var newSpoolInitialFilamentId: Int? = nil
    @State private var suggestedNewSpoolSource: NewSpoolSource? = nil
    @State private var newSpoolCandidates: [NewSpoolSource] = []
    @State private var didJustMapCurrentTag = false
    @State private var secondTagTargetSpoolId: Int? = nil
    @State private var isPreparingCreateSpool = false
    @State private var createSpoolError: String? = nil
    @State private var persistenceError: String? = nil
    @State private var moveBothMappedTagIDs = true
    @State private var reusableMoveSourceSpool: SpoolmanSpool? = nil
    @State private var reusableMoveUIDs: [String] = []
    @State private var chooserAllowAllSpools = false
    @State private var chooserExcludedSpoolIDs: Set<Int> = []
    @State private var overrideInitialLotNrForNewSpool: String? = nil
    @State private var rawByteExportFileURL: URL? = nil
    @State private var showRawByteExportSheet = false

    struct SlotReplacementContext {
        let spool: SpoolmanSpool
        let existingUIDs: [String]
        let newUID: String
    }

    enum NewSpoolSource: Identifiable {
        case local(SpoolmanFilament)
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

    enum UIDMappingActionState: Equatable {
        case saveCurrentTag(enabled: Bool)
        case scanSecondTag(enabled: Bool)
        case none
    }

    enum UIDOnlyActionsState: Equatable {
        case enabled
        case disabledByMappingSetting
        case disabledByConnection
        case unavailable
    }

    enum SecondaryCreateAction: Equatable {
        case none
        case bestMatch
        case uidOnly
    }

    enum MoveSourceUIDSelectionState: Equatable {
        case hidden
        case visible(defaultMoveBoth: Bool)
    }

    static func uidMappingActionState(
        persistCardUID: Bool,
        tagMapped: Bool,
        didJustMapCurrentTag: Bool,
        isSecondTagScanning: Bool,
        mappedUIDCount: Int
    ) -> UIDMappingActionState {
        if didJustMapCurrentTag {
            let canScanSecondTag = mappedUIDCount < 2
            return .scanSecondTag(enabled: persistCardUID && canScanSecondTag && !isSecondTagScanning)
        }

        if !tagMapped {
            return .saveCurrentTag(enabled: persistCardUID)
        }

        return .none
    }

    static func uidOnlyActionsState(
        cardUID: String?,
        persistCardUID: Bool,
        spoolmanConfigured: Bool
    ) -> UIDOnlyActionsState {
        guard cardUID != nil else { return .unavailable }
        guard spoolmanConfigured else { return .disabledByConnection }
        guard persistCardUID else { return .disabledByMappingSetting }
        return .enabled
    }

    static func existingSpoolMappingState(
        cardUID: String?,
        persistCardUID: Bool,
        spoolmanConfigured: Bool
    ) -> UIDOnlyActionsState {
        uidOnlyActionsState(
            cardUID: cardUID,
            persistCardUID: persistCardUID,
            spoolmanConfigured: spoolmanConfigured
        )
    }

    static func secondaryCreateAction(
        tagDataAvailable: Bool,
        showCreateSpool: Bool,
        showUIDActionsForUnknownTag: Bool
    ) -> SecondaryCreateAction {
        if tagDataAvailable && showCreateSpool {
            return .bestMatch
        }

        if !tagDataAvailable && showUIDActionsForUnknownTag {
            return .uidOnly
        }

        return .none
    }

    static func moveSourceUIDSelectionState(sourceMappedUIDs: [String]) -> MoveSourceUIDSelectionState {
        if sourceMappedUIDs.count >= SpoolMappingService.maxCardUIDs {
            return .visible(defaultMoveBoth: true)
        }
        return .hidden
    }

    static func selectedUIDsForReusableMove(
        scannedUID: String,
        sourceMappedUIDs: [String],
        moveBothWhenAvailable: Bool
    ) -> [String] {
        let normalizedScannedUID = SpoolMappingService.normalizeUID(scannedUID)
        var seen = Set<String>()
        let normalizedSourceUIDs = sourceMappedUIDs.compactMap { uid -> String? in
            let normalized = SpoolMappingService.normalizeUID(uid)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }

        if moveBothWhenAvailable,
           normalizedSourceUIDs.count >= SpoolMappingService.maxCardUIDs,
           normalizedSourceUIDs.contains(normalizedScannedUID) {
            return Array(normalizedSourceUIDs.prefix(SpoolMappingService.maxCardUIDs))
        }

        if !normalizedScannedUID.isEmpty {
            return [normalizedScannedUID]
        }

        return []
    }

    static func shouldShowUnknownRawByteExport(
        isUnknownFormat: Bool,
        rawPageLogBytes: [UInt8]?
    ) -> Bool {
        isUnknownFormat && !(rawPageLogBytes?.isEmpty ?? true)
    }

    static func unknownRawByteExportText(
        rawPageLogBytes: [UInt8],
        cardUID: String?,
        timestamp: Date
    ) -> String {
        let isoTimestamp = ISO8601DateFormatter().string(from: timestamp)
        let uidValue = cardUID ?? ""
        let bytesHex = rawPageLogBytes.map { String(format: "%02X", $0) }.joined()
        return "{\"timestamp\":\"\(isoTimestamp)\",\"uid\":\"\(uidValue)\",\"source\":\"raw-read-fallback\",\"bytesPerPage\":4,\"bytesHex\":\"\(bytesHex)\"}"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                    topCard

                    switch hubState {
                    case .loading:
                        ProgressView("Looking up spool...")
                            .padding()

                    case .authoritativeSpool(let spool):
                        mappingActions(spool: spool)
                        secondaryActions(tagData: result.tagData, showCreateSpool: false, showUIDActionsForUnknownTag: false)

                    case .cardUIDSpool(let spool):
                        mappingActions(spool: spool)
                        secondaryActions(tagData: result.tagData, showCreateSpool: false, showUIDActionsForUnknownTag: false)

                    case .matchResults(let matches):
                        matchSection(matches: matches)
                        secondaryActions(tagData: result.tagData, showCreateSpool: false, showUIDActionsForUnknownTag: false)

                    case .unknownTag:
                        unknownTagCard
                        secondaryActions(tagData: nil, showCreateSpool: false, showUIDActionsForUnknownTag: true)

                    case .noSpoolman:
                        noSpoolmanCard(spoolmanConfigured: !spoolmanUrl.isEmpty)
                        if let tagData = result.tagData {
                            secondaryActions(tagData: tagData, showCreateSpool: true, showUIDActionsForUnknownTag: false)
                        }
                    }

                    if isPreparingCreateSpool {
                        ProgressView("Preparing new spool...")
                            .padding(.horizontal)
                    }

                    if let createError = createSpoolError {
                        Text(createError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if let error = persistenceError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToWriteTag) {
                WriteTagView(initialData: writeInitialData ?? result.tagData)
            }
            .navigationDestination(isPresented: $navigateToCreateSpool) {
                SpoolFormView(
                    service: spoolmanService,
                    baseUrl: spoolmanUrl,
                    initialFilamentId: newSpoolInitialFilamentId,
                    initialLotNr: suggestedInitialLotNrForNewSpool,
                    onSaveSpool: { newSpool in
                        let sourceSpool = reusableMoveSourceSpool
                        let movedUIDs = reusableMoveUIDs
                        Task {
                            await handleSavedSpoolFromForm(
                                newSpool,
                                sourceSpool: sourceSpool,
                                movedUIDs: movedUIDs
                            )
                        }
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToMoreFilaments) {
                NewSpoolFilamentSelectionView(
                    candidates: additionalNewSpoolCandidates,
                    onSelect: { source in
                        navigateToMoreFilaments = false
                        createNewSpool(from: source)
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToChooser) {
                SpoolMatchSelectionView(
                    matches: matchResults,
                    allowAllSpools: chooserAllowAllSpools,
                    excludedSpoolIDs: chooserExcludedSpoolIDs,
                    onSelect: { spool in
                        handleChooserSelection(spool: spool)
                        navigateToChooser = false
                    }
                )
            }
            .sheet(isPresented: $showRawByteExportSheet) {
                if let fileURL = rawByteExportFileURL {
                    ShareSheet(activityItems: [fileURL])
                }
            }
            .alert("Replace Tag Slot", isPresented: $showSlotReplacementAlert, presenting: slotReplacementContext) { ctx in
                Button("Slot 1") { applySlotReplacement(ctx: ctx, slot: .first) }
                Button("Slot 2") { applySlotReplacement(ctx: ctx, slot: .second) }
                Button("Cancel", role: .cancel) {}
            } message: { ctx in
                let uid1 = ctx.existingUIDs.indices.contains(0) ? ctx.existingUIDs[0] : "—"
                let uid2 = ctx.existingUIDs.indices.contains(1) ? ctx.existingUIDs[1] : "—"
                Text("Both tag slots are in use.\nSlot 1: \(uid1)\nSlot 2: \(uid2)\n\nWhich slot should be replaced with the new tag?")
            }
        .task {
            await resolve()
        }
        .onChange(of: secondTagNFCManager.isScanning) { _, isScanning in
            if !isScanning {
                Task { await handleSecondTagScanCompletion() }
            }
        }
        .onChange(of: navigateToCreateSpool) { _, isPresented in
            if !isPresented, reusableMoveSourceSpool != nil {
                clearReusableMoveContext()
            }
        }
        .onChange(of: navigateToChooser) { _, isPresented in
            if !isPresented {
                chooserAllowAllSpools = false
                chooserExcludedSpoolIDs = []
            }
        }
    }

    // MARK: - Resolution

    private var matchResults: [FilamentMatchResult] {
        if case .matchResults(let m) = hubState { return m }
        return []
    }

    private var mappedSpool: SpoolmanSpool? {
        switch hubState {
        case .authoritativeSpool(let spool), .cardUIDSpool(let spool):
            return spool
        default:
            return nil
        }
    }

    private var suggestedInitialLotNrForNewSpool: String? {
        if let overrideInitialLotNrForNewSpool {
            return overrideInitialLotNrForNewSpool
        }

        guard let uid = result.cardUID else { return nil }
        return SpoolMappingService.lotNumber(for: [uid])
    }

    private var additionalNewSpoolCandidates: [NewSpoolSource] {
        guard let suggested = suggestedNewSpoolSource else { return [] }
        return newSpoolCandidates.filter { $0.id != suggested.id }
    }

    private func resolve() async {
        let isSpoolmanConfigured = !spoolmanUrl.isEmpty

        // 1. Authoritative: embedded spool_id on tag
        if let spoolId = result.tagData?.spoolmanId, isSpoolmanConfigured {
            await spoolmanService.fetchSpools(baseUrl: spoolmanUrl)
            if let spool = spoolmanService.spools.first(where: { $0.id == spoolId }) {
                hubState = .authoritativeSpool(spool)
                return
            }
        }

        // 2. card_uid lookup in Spoolman lot_nr
        if let uid = result.cardUID, isSpoolmanConfigured {
            if spoolmanService.spools.isEmpty {
                await spoolmanService.fetchSpools(baseUrl: spoolmanUrl)
            }
            if let spool = spoolmanService.findSpool(byCardUID: uid) {
                hubState = .cardUIDSpool(spool)
                return
            }
        }

        // 3. Heuristic filament match (requires decoded tag data + Spoolman)
        if let tagData = result.tagData, isSpoolmanConfigured {
            if spoolmanService.spools.isEmpty {
                await spoolmanService.fetchSpools(baseUrl: spoolmanUrl)
            }

            if spoolmanService.filaments.isEmpty {
                await spoolmanService.fetchFilaments(baseUrl: spoolmanUrl)
            }

            await prepareSuggestedNewSpoolSource(for: tagData)

            let ranked = FilamentMatchService.rank(tag: tagData, spools: spoolmanService.spools)
            if !ranked.isEmpty {
                hubState = .matchResults(ranked)
                return
            }
        }

        // 4. Tag has UID but no decoded data — show UID mapping UI
        if result.cardUID != nil, result.tagData == nil {
            hubState = .unknownTag
            return
        }

        // 5. No Spoolman configured, no match found, or empty Spoolman library
        hubState = .noSpoolman
    }

    // MARK: - UID Persistence

    private func persistUIDIfNeeded(to spool: SpoolmanSpool) async {
        guard persistCardUID, let uid = result.cardUID, !spoolmanUrl.isEmpty else { return }
        switch SpoolMappingService.updatedLotNumber(existingLotNumber: spool.lotNr, adding: uid) {
        case .updated(let newLotNr):
            await spoolmanService.setLotNr(spoolId: spool.id, lotNr: newLotNr, baseUrl: spoolmanUrl)
            didJustMapCurrentTag = true
        case .needsSlotReplacement(let existingUIDs, let newUID):
            slotReplacementContext = SlotReplacementContext(spool: spool, existingUIDs: existingUIDs, newUID: newUID)
            showSlotReplacementAlert = true
        }
    }

    private func applySlotReplacement(ctx: SlotReplacementContext, slot: SpoolMappingService.Slot) {
        let newLotNr = SpoolMappingService.replacingUID(in: ctx.spool.lotNr, slot: slot, with: ctx.newUID)
        Task {
            await spoolmanService.setLotNr(spoolId: ctx.spool.id, lotNr: newLotNr, baseUrl: spoolmanUrl)
            await MainActor.run {
                didJustMapCurrentTag = true
            }
        }
    }

    private func handleManualSelection(spool: SpoolmanSpool) {
        hubState = .authoritativeSpool(spool)
        didJustMapCurrentTag = false
        Task {
            await persistUIDIfNeeded(to: spool)
        }
    }

    private func handleChooserSelection(spool: SpoolmanSpool) {
        if let sourceSpool = reusableMoveSourceSpool, !reusableMoveUIDs.isEmpty {
            let movedUIDs = reusableMoveUIDs
            Task {
                _ = await moveReusableUIDs(
                    to: spool,
                    sourceSpool: sourceSpool,
                    movedUIDs: movedUIDs
                )
            }
            return
        }

        handleManualSelection(spool: spool)
    }

    private func handleSavedSpoolFromForm(
        _ newSpool: SpoolmanSpool,
        sourceSpool: SpoolmanSpool?,
        movedUIDs: [String]
    ) async {
        guard let sourceSpool, !movedUIDs.isEmpty else { return }

        _ = await moveReusableUIDs(
            to: newSpool,
            sourceSpool: sourceSpool,
            movedUIDs: movedUIDs
        )
    }

    private func clearReusableMoveContext() {
        reusableMoveSourceSpool = nil
        reusableMoveUIDs = []
        chooserAllowAllSpools = false
        chooserExcludedSpoolIDs = []
        overrideInitialLotNrForNewSpool = nil
        moveBothMappedTagIDs = true
    }

    @discardableResult
    private func moveReusableUIDs(
        to destinationSpool: SpoolmanSpool,
        sourceSpool: SpoolmanSpool,
        movedUIDs: [String]
    ) async -> Bool {
        guard persistCardUID else {
            persistenceError = "Enable \"Save Tag ID to Spoolman Lot nr.\" in Settings to move tag mappings."
            return false
        }

        guard !spoolmanUrl.isEmpty else {
            persistenceError = "Connect to a Spoolman server in Settings to move tag mappings."
            return false
        }

        guard destinationSpool.id != sourceSpool.id else {
            persistenceError = "Please choose a different destination spool."
            return false
        }

        guard let destinationLotNr = SpoolMappingService.replacingAllUIDs(
            in: destinationSpool.lotNr,
            with: movedUIDs
        ) else {
            persistenceError = "Could not determine destination tag mapping values."
            return false
        }

        let destinationUpdated = await spoolmanService.setLotNr(
            spoolId: destinationSpool.id,
            lotNr: destinationLotNr,
            baseUrl: spoolmanUrl
        )

        guard destinationUpdated else {
            persistenceError = "Failed to update destination spool tag mappings."
            return false
        }

        let sourceLotNrAfterRemoval = SpoolMappingService.lotNumber(
            removing: movedUIDs,
            from: sourceSpool.lotNr
        )

        let sourceUpdated: Bool
        if let sourceLotNrAfterRemoval {
            sourceUpdated = await spoolmanService.setLotNr(
                spoolId: sourceSpool.id,
                lotNr: sourceLotNrAfterRemoval,
                baseUrl: spoolmanUrl
            )
        } else {
            sourceUpdated = await spoolmanService.clearLotNr(
                spoolId: sourceSpool.id,
                baseUrl: spoolmanUrl
            )
        }

        if let refreshedDestination = spoolmanService.spools.first(where: { $0.id == destinationSpool.id }) {
            hubState = .authoritativeSpool(refreshedDestination)
        } else {
            hubState = .authoritativeSpool(destinationSpool)
        }

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

    private func handleSecondTagScanCompletion() async {
        guard let targetSpoolId = secondTagTargetSpoolId else { return }
        defer {
            secondTagNFCManager.scanResult = nil
            secondTagTargetSpoolId = nil
        }

        guard let secondUID = secondTagNFCManager.scanResult?.cardUID else {
            return
        }

        guard let targetSpool = spoolmanService.spools.first(where: { $0.id == targetSpoolId }) else {
            persistenceError = "Could not find the selected spool to store second tag mapping."
            return
        }

        switch SpoolMappingService.updatedLotNumber(existingLotNumber: targetSpool.lotNr, adding: secondUID) {
        case .updated(let newLotNr):
            await spoolmanService.setLotNr(spoolId: targetSpool.id, lotNr: newLotNr, baseUrl: spoolmanUrl)
        case .needsSlotReplacement(let existingUIDs, let newUID):
            slotReplacementContext = SlotReplacementContext(spool: targetSpool, existingUIDs: existingUIDs, newUID: newUID)
            showSlotReplacementAlert = true
        }

        if let refreshed = spoolmanService.spools.first(where: { $0.id == targetSpool.id }) {
            hubState = .authoritativeSpool(refreshed)
        }
    }

    private func prepareSuggestedNewSpoolSource(for tagData: FilamentTagData) async {
        if spoolmanDBService.filaments.isEmpty {
            await spoolmanDBService.fetchFilaments()
        }
        var scored: [(source: NewSpoolSource, score: Int)] = []

        scored.append(contentsOf: spoolmanService.filaments.compactMap { filament in
            let score = localFilamentScore(for: tagData, filament: filament)
            guard score > 0 else { return nil }
            return (.local(filament), score)
        })

        scored.append(contentsOf: spoolmanDBService.filaments.compactMap { filament in
            let score = dbFilamentScore(for: tagData, filament: filament)
            guard score > 0 else { return nil }
            return (.spoolmanDB(filament), score)
        })

        scored.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.source.id < rhs.source.id }
            return lhs.score > rhs.score
        }

        newSpoolCandidates = scored.map { $0.source }
        suggestedNewSpoolSource = scored.first?.source
    }

    private func prepareWriteTagData(withMappedSpool spool: SpoolmanSpool? = nil) {
        var data = result.tagData
        if let spool, writeSpoolId {
            if data == nil {
                data = FilamentTagData.from(spool: spool, writeSpoolId: true)
            } else {
                data?.spoolmanId = spool.id
            }
        }
        writeInitialData = data
        navigateToWriteTag = true
    }

    private func createNewSpoolFromBestMatch() {
        clearReusableMoveContext()
        createNewSpool(from: nil)
    }

    private func createNewSpoolFromUIDOnly() {
        clearReusableMoveContext()

        guard result.cardUID != nil else {
            createSpoolError = "Tag UID is unavailable for creating a new spool."
            return
        }

        createSpoolError = nil
        newSpoolInitialFilamentId = nil
        navigateToCreateSpool = true
    }

    private func createNewSpool(from selectedSource: NewSpoolSource?) {
        guard let tagData = result.tagData, !spoolmanUrl.isEmpty else {
            createSpoolError = "Tag data is unavailable for creating a new spool."
            return
        }

        createSpoolError = nil
        isPreparingCreateSpool = true

        Task {
            var source = selectedSource

            if source == nil, suggestedNewSpoolSource == nil {
                if spoolmanService.filaments.isEmpty {
                    await spoolmanService.fetchFilaments(baseUrl: spoolmanUrl)
                }
                await prepareSuggestedNewSpoolSource(for: tagData)
            }

            if source == nil {
                source = suggestedNewSpoolSource
            }

            switch source {
            case .local(let filament):
                await MainActor.run {
                    newSpoolInitialFilamentId = filament.id
                    isPreparingCreateSpool = false
                    navigateToCreateSpool = true
                }
                return

            case .spoolmanDB(let dbBest):
                if spoolmanService.vendors.isEmpty {
                    await spoolmanService.fetchVendors(baseUrl: spoolmanUrl)
                }

                let importedFilament = await importDBFilamentIfNeeded(dbBest)
                await MainActor.run {
                    isPreparingCreateSpool = false
                    if let importedFilament {
                        newSpoolInitialFilamentId = importedFilament.id
                        navigateToCreateSpool = true
                    } else {
                        createSpoolError = "Could not import the suggested SpoolmanDB filament."
                    }
                }
                return

            case .none:
                await MainActor.run {
                    isPreparingCreateSpool = false
                    createSpoolError = "Could not find a suitable filament match in your library or SpoolmanDB."
                }
                return
            }
        }
    }

    private func localFilamentScore(for tagData: FilamentTagData, filament: SpoolmanFilament) -> Int {
        var score = 0
        let tagMaterial = tagData.material.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagBrand = tagData.brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagName = (tagData.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if (filament.material ?? "").lowercased() == tagMaterial { score += 40 }
        if (filament.vendor?.name ?? "").lowercased() == tagBrand { score += 25 }
        if let name = filament.name?.lowercased(), !tagName.isEmpty {
            if name == tagName { score += 15 }
            else if name.contains(tagName) || tagName.contains(name) { score += 7 }
        }

        let colorScore = perceptualColorScore(tagHex: tagData.colorHex, candidateHex: filament.colorHex)
        score += colorScore

        if colorScore <= 2,
           (filament.material ?? "").lowercased() == tagMaterial,
           (filament.vendor?.name ?? "").lowercased() == tagBrand {
            score -= 8
        }

        return score
    }

    private func dbFilamentScore(for tagData: FilamentTagData, filament: SpoolmanDBFilament) -> Int {
        var score = 0
        let tagMaterial = tagData.material.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagBrand = tagData.brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagName = (tagData.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if filament.material.lowercased() == tagMaterial { score += 40 }
        if filament.manufacturer.lowercased() == tagBrand { score += 25 }
        let name = filament.name.lowercased()
        if !tagName.isEmpty {
            if name == tagName { score += 15 }
            else if name.contains(tagName) || tagName.contains(name) { score += 7 }
        }

        let colorScore = perceptualColorScore(tagHex: tagData.colorHex, candidateHex: filament.colorHex)
        score += colorScore

        if colorScore <= 2,
           filament.material.lowercased() == tagMaterial,
           filament.manufacturer.lowercased() == tagBrand {
            score -= 8
        }

        return score
    }

    // MARK: - Perceptual color matching (CIELAB / DeltaE)

    /// Returns 0...20 where higher means more similar.
    private func perceptualColorScore(tagHex: String, candidateHex: String?) -> Int {
        guard let tagLab = labColor(fromHex: tagHex),
              let candidateLab = labColor(fromHex: candidateHex ?? "") else {
            return 0
        }

        let deltaE = deltaE76(tagLab, candidateLab)
        // Human perception: colors with DeltaE close to 0 are very similar.
        // We treat 100+ as effectively "very different".
        let similarity = max(0.0, 1.0 - min(deltaE, 100.0) / 100.0)
        return Int((similarity * 20.0).rounded())
    }

    private func labColor(fromHex hex: String) -> (Double, Double, Double)? {
        guard let rgb = normalizedSRGB(fromHex: hex) else { return nil }

        let r = linearized(rgb.0)
        let g = linearized(rgb.1)
        let b = linearized(rgb.2)

        // sRGB D65 -> XYZ
        let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        let z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041

        // D65 reference white
        let xr = x / 0.95047
        let yr = y / 1.00000
        let zr = z / 1.08883

        let fx = labF(xr)
        let fy = labF(yr)
        let fz = labF(zr)

        let l = max(0.0, 116.0 * fy - 16.0)
        let a = 500.0 * (fx - fy)
        let b2 = 200.0 * (fy - fz)
        return (l, a, b2)
    }

    private func deltaE76(_ lhs: (Double, Double, Double), _ rhs: (Double, Double, Double)) -> Double {
        let dl = lhs.0 - rhs.0
        let da = lhs.1 - rhs.1
        let db = lhs.2 - rhs.2
        return sqrt(dl * dl + da * da + db * db)
    }

    private func normalizedSRGB(fromHex hex: String) -> (Double, Double, Double)? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        let expanded: String
        if cleaned.count == 3 {
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        } else {
            expanded = cleaned
        }

        guard expanded.count == 6, let value = UInt32(expanded, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    private func linearized(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    private func labF(_ t: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        if t > epsilon {
            return pow(t, 1.0 / 3.0)
        }
        return (kappa * t + 16.0) / 116.0
    }

    private func importDBFilamentIfNeeded(_ dbFilament: SpoolmanDBFilament) async -> SpoolmanFilament? {
        let existing = spoolmanService.filaments.first { filament in
            (filament.vendor?.name ?? "").localizedCaseInsensitiveCompare(dbFilament.manufacturer) == .orderedSame
            && (filament.name ?? "").localizedCaseInsensitiveCompare(dbFilament.name) == .orderedSame
            && (filament.material ?? "").localizedCaseInsensitiveCompare(dbFilament.material) == .orderedSame
        }
        if let existing { return existing }

        var vendorId = spoolmanService.vendors.first(where: {
            $0.name.localizedCaseInsensitiveCompare(dbFilament.manufacturer) == .orderedSame
        })?.id

        if vendorId == nil {
            if let newVendor = await spoolmanService.addVendor(name: dbFilament.manufacturer, baseUrl: spoolmanUrl) {
                vendorId = newVendor.id
            } else {
                return nil
            }
        }

        guard let finalVendorId = vendorId else { return nil }

        let imported = await spoolmanService.addFilament(
            name: dbFilament.name,
            vendorId: finalVendorId,
            material: dbFilament.material,
            colorHex: dbFilament.colorHex,
            density: dbFilament.density,
            diameter: dbFilament.diameter,
            extruderTemp: dbFilament.extruderTemp,
            bedTemp: dbFilament.bedTemp,
            baseUrl: spoolmanUrl
        )
        return imported
    }

    // MARK: - Subviews

    @ViewBuilder
    private var topCard: some View {
        if let spool = mappedSpool {
            confirmedSpoolCard(spool: spool, label: "Mapped Spool")
        } else {
            unknownMappingCard
        }
    }

    @ViewBuilder
    private var unknownMappingCard: some View {
        VStack(spacing: 8) {
            Image(systemName: result.isUnknownFormat ? "tag" : "tag")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text(result.isUnknownFormat ? "Unknown Tag Format" : "No Spoolman Mapping Found")
                .font(.headline)

            if let tagData = result.tagData {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: tagData.colorHex) ?? .gray)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summaryLine(for: tagData))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(tagData.subtype ?? tagData.name ?? "(No filament name on tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }

            if let uid = result.cardUID {
                Text("UID: \(uid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Copy UID") {
                            UIPasteboard.general.string = uid
                        }
                    }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryLine(for tagData: FilamentTagData) -> String {
        var parts: [String] = []
        if !tagData.brand.isEmpty { parts.append(tagData.brand) }
        if !tagData.material.isEmpty { parts.append(tagData.material) }
        if let subtype = tagData.subtype, !subtype.isEmpty { parts.append(subtype) }
        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private func confirmedSpoolCard(spool: SpoolmanSpool, label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)

            HStack(spacing: 12) {
                if let hex = spool.filament.colorHex {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text((spool.filament.name ?? "Spool") + " (#\(spool.id))")
                        .font(.headline)
                    if let vendor = spool.filament.vendor?.name,
                       let material = spool.filament.material {
                        Text("\(vendor) \(material)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let weight = spool.remainingWeight {
                        Text(String(format: "%.0f g remaining", weight))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func matchSection(matches: [FilamentMatchResult]) -> some View {
        let mappingState = Self.existingSpoolMappingState(
            cardUID: result.cardUID,
            persistCardUID: persistCardUID,
            spoolmanConfigured: !spoolmanUrl.isEmpty
        )

        VStack(spacing: 14) {
            if let source = suggestedNewSpoolSource {
                createSpoolSuggestionCard(source: source)
            }

            if let top = matches.first {
                mapSpoolSuggestionCard(
                    topMatch: top,
                    matchesCount: matches.count,
                    mappingState: mappingState
                )
            }
        }
    }

    @ViewBuilder
    private func createSpoolSuggestionCard(source: NewSpoolSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested New Spool", systemImage: "plus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            newSpoolSuggestionRow(source: source)

            Button {
                createNewSpoolFromBestMatch()
            } label: {
                Label("Create New Spool", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if !additionalNewSpoolCandidates.isEmpty {
                Button {
                    navigateToMoreFilaments = true
                } label: {
                    Label("See \(additionalNewSpoolCandidates.count) more filaments", systemImage: "list.bullet")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func mapSpoolSuggestionCard(
        topMatch: FilamentMatchResult,
        matchesCount: Int,
        mappingState: UIDOnlyActionsState
    ) -> some View {
        let mappingEnabled = mappingState == .enabled

        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested Spool", systemImage: "sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)

            matchRow(match: topMatch)

            Button {
                handleManualSelection(spool: topMatch.spool)
            } label: {
                Label("Map to Existing Spool", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!mappingEnabled)

            if matchesCount > 1 {
                Button {
                    chooserAllowAllSpools = false
                    chooserExcludedSpoolIDs = []
                    navigateToChooser = true
                } label: {
                    Label("See \(matchesCount - 1) more candidates", systemImage: "list.bullet")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(!mappingEnabled)
            }

            if let mappingHint = mappingHintText(for: mappingState) {
                Text(mappingHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func newSpoolSuggestionRow(source: NewSpoolSource) -> some View {
        HStack(spacing: 10) {
            switch source {
            case .local(let filament):
                if let hex = filament.colorHex {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(filament.name ?? "Unnamed Filament")
                        .font(.subheadline.weight(.medium))
                    Text("\(filament.vendor?.name ?? "Unknown Vendor") \(filament.material ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("From My Filaments")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .spoolmanDB(let filament):
                if let hex = filament.colorHex {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(filament.name)
                        .font(.subheadline.weight(.medium))
                    Text("\(filament.manufacturer) \(filament.material)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("From SpoolmanDB (will import first)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func matchRow(match: FilamentMatchResult) -> some View {
        HStack(spacing: 10) {
            if let hex = match.spool.filament.colorHex {
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(match.spool.filament.name ?? "Spool #\(match.spool.id)")
                    .font(.subheadline.weight(.medium))
                if let vendor = match.spool.filament.vendor?.name,
                   let material = match.spool.filament.material {
                    Text("\(vendor) \(material)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var unknownTagCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unknown Tag Format", systemImage: "tag")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("This tag was detected but its format is not supported. The UID has been captured and can be used to link this tag to a Spoolman spool.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let uid = result.cardUID {
                Button {
                    UIPasteboard.general.string = uid
                } label: {
                    Label("Copy UID", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if Self.shouldShowUnknownRawByteExport(
                isUnknownFormat: result.isUnknownFormat,
                rawPageLogBytes: result.rawPageLogBytes
            ) {
                Button {
                    saveUnknownRawPageLogBytes()
                } label: {
                    Label("Save raw page log bytes", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func saveUnknownRawPageLogBytes() {
        guard let rawPageLogBytes = result.rawPageLogBytes,
              Self.shouldShowUnknownRawByteExport(isUnknownFormat: result.isUnknownFormat, rawPageLogBytes: rawPageLogBytes)
        else {
            persistenceError = "No raw page log bytes are available for this scan."
            return
        }

        let now = Date()
        let exportText = Self.unknownRawByteExportText(
            rawPageLogBytes: rawPageLogBytes,
            cardUID: result.cardUID,
            timestamp: now
        )
        let uidPart = result.cardUID ?? "unknown"
        let timestampPart = Int(now.timeIntervalSince1970)
        let filename = "unknown_tag_raw_pages_\(uidPart)_\(timestampPart).json"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try exportText.write(to: fileURL, atomically: true, encoding: .utf8)
            rawByteExportFileURL = fileURL
            showRawByteExportSheet = true
        } catch {
            persistenceError = "Failed to save raw page log bytes: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func noSpoolmanCard(spoolmanConfigured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                spoolmanConfigured ? "No Spoolman Mapping Found" : "No Spoolman Connection",
                systemImage: "server.rack"
            )
            .font(.headline)
            .foregroundStyle(.secondary)
            Text(
                spoolmanConfigured
                    ? "No spool in your Spoolman library matched this tag. You can write a new tag or save the data manually."
                    : "Connect to a Spoolman server in Settings to enable spool matching and history."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func mappingActions(spool: SpoolmanSpool) -> some View {
        let sourceMappedUIDs = SpoolMappingService.cardUIDs(in: spool.lotNr)
        let sourceUIDSelectionState = Self.moveSourceUIDSelectionState(sourceMappedUIDs: sourceMappedUIDs)

        VStack(alignment: .leading, spacing: 10) {
            if writeSpoolId, result.tagData?.spoolmanId == nil {
                Button {
                    prepareWriteTagData(withMappedSpool: spool)
                } label: {
                    Label("Write Spool ID to Tag", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let uid = result.cardUID {
                let mappedUIDs = SpoolMappingService.cardUIDs(in: spool.lotNr)
                let mapped = mappedUIDs.contains(SpoolMappingService.normalizeUID(uid))
                let mappingAction = Self.uidMappingActionState(
                    persistCardUID: persistCardUID,
                    tagMapped: mapped,
                    didJustMapCurrentTag: didJustMapCurrentTag,
                    isSecondTagScanning: secondTagNFCManager.isScanning,
                    mappedUIDCount: mappedUIDs.count
                )
                let showPersistSettingHint = !persistCardUID && mappingAction != .none

                switch mappingAction {
                case .scanSecondTag(let enabled):
                    Button {
                        secondTagTargetSpoolId = spool.id
                        secondTagNFCManager.startScanning()
                    } label: {
                        Label(
                            secondTagNFCManager.isScanning ? "Scanning Second Tag..." : "Scan Second Tag for This Spool",
                            systemImage: "wave.3.right"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!enabled)

                case .saveCurrentTag(let enabled):
                    Button {
                        Task { await persistUIDIfNeeded(to: spool) }
                    } label: {
                        Label("Save Tag ID to Spoolman Lot nr.", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!enabled)

                case .none:
                    EmptyView()
                }

                if showPersistSettingHint {
                    Text("Enable \"Save Tag ID to Spoolman Lot nr.\" in Settings to use UID mapping actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let scannedUID = result.cardUID {
                let mappingState = Self.existingSpoolMappingState(
                    cardUID: scannedUID,
                    persistCardUID: persistCardUID,
                    spoolmanConfigured: !spoolmanUrl.isEmpty
                )
                let mappingEnabled = mappingState == .enabled

                Divider()

                Label("Reusable Spool", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch sourceUIDSelectionState {
                case .visible(let defaultMoveBoth):
                    Toggle("Move both mapped tag IDs", isOn: $moveBothMappedTagIDs)
                        .font(.subheadline)
                        .onAppear {
                            if moveBothMappedTagIDs != defaultMoveBoth {
                                moveBothMappedTagIDs = defaultMoveBoth
                            }
                        }
                case .hidden:
                    EmptyView()
                }

                Button {
                    let movedUIDs = Self.selectedUIDsForReusableMove(
                        scannedUID: scannedUID,
                        sourceMappedUIDs: sourceMappedUIDs,
                        moveBothWhenAvailable: moveBothMappedTagIDs
                    )
                    reusableMoveSourceSpool = spool
                    reusableMoveUIDs = movedUIDs
                    overrideInitialLotNrForNewSpool = SpoolMappingService.lotNumber(for: movedUIDs)
                    createSpoolError = nil
                    persistenceError = nil
                    navigateToCreateSpool = true
                } label: {
                    Label("Create New Spool (Reusable)", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!mappingEnabled)

                Button {
                    let movedUIDs = Self.selectedUIDsForReusableMove(
                        scannedUID: scannedUID,
                        sourceMappedUIDs: sourceMappedUIDs,
                        moveBothWhenAvailable: moveBothMappedTagIDs
                    )
                    reusableMoveSourceSpool = spool
                    reusableMoveUIDs = movedUIDs
                    chooserAllowAllSpools = true
                    chooserExcludedSpoolIDs = [spool.id]
                    persistenceError = nil
                    navigateToChooser = true
                } label: {
                    Label("Map to Another Spool", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!mappingEnabled)

                if let mappingHint = mappingHintText(for: mappingState) {
                    Text(mappingHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func mappingHintText(for state: UIDOnlyActionsState) -> String? {
        switch state {
        case .disabledByMappingSetting:
            return "Enable \"Save Tag ID to Spoolman Lot nr.\" in Settings to map this tag to an existing spool."
        case .disabledByConnection:
            return "Connect to a Spoolman server in Settings to map this tag to an existing spool."
        case .unavailable:
            return "Tag UID is unavailable, so mapping by UID is not possible."
        case .enabled:
            return nil
        }
    }

    @ViewBuilder
    private func secondaryActions(
        tagData: FilamentTagData?,
        showCreateSpool: Bool,
        showUIDActionsForUnknownTag: Bool
    ) -> some View {
        let createAction = Self.secondaryCreateAction(
            tagDataAvailable: tagData != nil,
            showCreateSpool: showCreateSpool,
            showUIDActionsForUnknownTag: showUIDActionsForUnknownTag
        )
        let mappingState = Self.existingSpoolMappingState(
            cardUID: result.cardUID,
            persistCardUID: persistCardUID,
            spoolmanConfigured: !spoolmanUrl.isEmpty
        )
        let mappingEnabled = mappingState == .enabled

        VStack(spacing: 10) {
            if tagData != nil {
                if showCreateSpool {
                    Button {
                        createNewSpoolFromBestMatch()
                    } label: {
                        Label("Create New Spool", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        chooserAllowAllSpools = false
                        chooserExcludedSpoolIDs = []
                        navigateToChooser = true
                    } label: {
                        Label("Map to Existing Spool", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!mappingEnabled)

                    if let mappingHint = mappingHintText(for: mappingState) {
                        Text(mappingHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    prepareWriteTagData()
                } label: {
                    Label("Create Tag", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !savedToRecent {
                    Button {
                        if let data = tagData {
                            recentTagManager.addTag(data)
                            savedToRecent = true
                        }
                    } label: {
                        Label("Add to Recent Tags", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label("Saved to Recent Tags", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            } else if showUIDActionsForUnknownTag {
                let uidActionsState = Self.uidOnlyActionsState(
                    cardUID: result.cardUID,
                    persistCardUID: persistCardUID,
                    spoolmanConfigured: !spoolmanUrl.isEmpty
                )
                let encryptedMappingEnabled = uidActionsState == .enabled
                let creationEnabled = uidActionsState != .disabledByConnection && uidActionsState != .unavailable

                Button {
                    switch createAction {
                    case .uidOnly:
                        createNewSpoolFromUIDOnly()
                    case .bestMatch:
                        createNewSpoolFromBestMatch()
                    case .none:
                        break
                    }
                } label: {
                    Label("Create New Spool", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!creationEnabled)

                Button {
                    chooserAllowAllSpools = false
                    chooserExcludedSpoolIDs = []
                    navigateToChooser = true
                } label: {
                    Label("Map to Existing Spool", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!encryptedMappingEnabled)

                switch uidActionsState {
                case .disabledByMappingSetting:
                    Text("Enable \"Save Tag ID to Spoolman Lot nr.\" in Settings to create or map by UID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .disabledByConnection:
                    Text("Connect to a Spoolman server in Settings to create or map by UID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable, .enabled:
                    EmptyView()
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
