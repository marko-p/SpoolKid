//
//  SpoolFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Spool in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolFormView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.serverLink) private var serverLink
    /// Set after a create that may have saved: Save waits for "Save Again".
    @State private var holdsResave = false
    @Environment(\.hidesFirstRunTips) private var hidesFirstRunTips
    @EnvironmentObject private var supportPrompts: SupportPromptService
    @EnvironmentObject private var emptySpools: EmptySpoolLibrary
    @EnvironmentObject private var printer: PrinterService
    @ObservedObject var store: SpoolDataStore
    var spoolToEdit: Spool?
    var initialFilamentId: Int? = nil
    var initialCardUIDs: [String] = []
    /// A new spool's location, applied once on appear. Only an existing
    /// location is passed here (`PrinterLocationMatch`); none is created.
    var initialLocation: String? = nil
    /// D3 (spec 2026-09-27): the tags this new spool takes from the spool the
    /// scanned tag belongs to. Nil everywhere except the hub's Create New
    /// Spool on a known tag.
    var tagMoveOffer: TagMoveOffer? = nil
    /// What the scanned tag says about this physical spool. Its empty weight
    /// counts for a new spool of `initialFilamentId` only (`tagOffer`); its
    /// initial and remaining weights seed a new spool once, on appear.
    var tagWeights: TagSpoolWeights? = nil
    /// Fires on creates only. `movedTagUIDs` is the ticked part of
    /// `tagMoveOffer` — the caller removes exactly those from the source.
    var onSaveSpool: ((Spool, _ movedTagUIDs: [String]) -> Void)? = nil
    /// Set when the form is shown in place (the Spool page's Edit): Cancel,
    /// Save and Archive hand back to the caller instead of dismissing.
    var onFinish: (() -> Void)? = nil
    /// Opens scrolled to the weight section (the weight card's set-up).
    var opensAtWeight = false

    @AppStorage(AppConfig.lastSpoolPriceKey) private var lastSpoolPrice: String = ""
    @AppStorage(AppConfig.lastSpoolEmptyWeightKey) private var lastSpoolEmptyWeight: String = "0"
    @AppStorage(AppConfig.lastSpoolFilamentIdKey) private var lastSpoolFilamentId: Int = -1
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete = true

    @StateObject private var nfcManager = NFCManager()
    @StateObject private var recentTagManager = RecentTagManager()
    /// The spool whose Write Tag is in flight — the owner of the tag being written.
    @State private var writingSpool: Spool?
    /// FilaMan's one-tag limit met a Save & Write; answered per section.
    @State private var replaceRequest: TagReplaceRequest?
    /// A scanned tag that would replace FilaMan's one tag; answered in the
    /// section that scanned it.
    @State private var linkReplaceRequest: TagReplaceRequest?
    /// The person chose Replace Tag before the write; its link replaces.
    @State private var replacesOnWriteLink = false

    @State private var filamentId: Int?
    @State private var price: String = ""
    @State private var initialWeight: String = "1000"
    @State private var spoolWeight: String = ""
    /// The text this form last put in Initial Filament Weight by itself; nil
    /// once the user typed or tapped a size, for a tag's weight, and in edit mode.
    @State private var autoFilledInitialWeight: String?
    /// The text this form last put in Empty Spool Weight by itself; nil once
    /// the user picked or applied a value, and in edit mode.
    @State private var autoFilledSpoolWeight: String?
    /// What the filament's catalogue answered for the chosen filament's missing
    /// spool weight (`lookUpCatalogSpoolWeight`). It counts only while that
    /// filament is the chosen one, and goes back to the filament on a save
    /// that kept it (`CatalogSpoolWeight.weightToSave`).
    @State private var lookedUp: (filamentId: Int, grams: Double)?
    /// What `.onAppear` put into the weight fields, so a save can tell an
    /// untouched field from a re-asserted one (R21). Empty when creating.
    @State private var loadedInitialWeight: String = ""
    @State private var loadedSpoolWeight: String = ""
    @State private var loadedRemainingWeight: String = ""
    @State private var loadedComment: String = ""
    @State private var loadedFirstUsed: String = ""
    @State private var loadedLastUsed: String = ""
    @State private var location: String = ""
    @State private var isNamingNewLocation = false
    @State private var newLocationName = ""
    @State private var comment: String = ""
    @State private var archived: Bool = false
    @State private var firstUsedISO8601: String = ""
    @State private var lastUsedISO8601: String = ""
    // FilaMan-only (Task 7). `statusKey` is the picker's selection, `""` when
    // no status is loaded or the picker isn't rendered; `purchaseDate` is
    // `nil` when the spool has none, matching the DatePicker binding below.
    @State private var statusKey: String = ""
    @State private var externalId: String = ""
    @State private var purchaseDate: Date?
    @State private var loadedStatusKey: String = ""
    @State private var loadedExternalId: String = ""
    @State private var loadedPurchaseDate: String = ""

    /// How many identical spools one Add save creates. Not remembered between
    /// forms: a count carried over would quietly multiply the next save.
    @State private var count = 1
    @State private var isSaved: Bool = false
    @State private var isSaving: Bool = false
    @State private var savedSpools: [Spool] = []
    @State private var hasInitialized = false
    /// `opensAtWeight` scrolls once, not on every return from a picker.
    @State private var didScrollToWeight = false
    /// The one plain alert on screen (2026-10-11); see `SpoolFormAlert`.
    @State private var formAlert: SpoolFormAlert?

    /// One tag list per section: index 0 is Spool 1 on Add and the edited spool on
    /// Edit. One entry before an Add save; padded with [] to `savedSpools.count`
    /// when it saves. Read through `listedTags(in:)`, which yields [] past the end.
    @State private var tagSections: [[String]] = [[]]
    /// The section a running scan or write is for. Set per tap, so the result
    /// of a scan lands on the spool whose button was tapped.
    @State private var activeTagSection = 0
    @State private var isScanningForCardUID = false
    @State private var movingTagUIDs: Set<String> = []
    /// Tags the user agreed to take from another spool or a filament, by UID,
    /// with the holder each leaves and the section that agreed it. Released on
    /// Save, before the link write; a cancelled form changes nothing.
    @State private var pendingMoves: [String: PendingMove] = [:]
    /// The last tag write queued after an Add save: a tag-list change
    /// (`saveLinkedTagsNow`) or a written tag's link (`linkWrittenTag`).
    @State private var linkedTagsSave: Task<Void, Never>?
    /// How many of those writes are queued or running. While any is, no tag
    /// button starts a scan or a write: a claim decided now would read a store
    /// that does not show the write yet.
    @State private var pendingTagWrites = 0
    /// Which reader scans and writes tags here. Never stored.
    @State private var tagReader: TagReader = .iPhone
    /// The reader the scan or write in flight, or the last write, ran on.
    @State private var run = TagReaderRun()

    /// The UID an in-flight "Unlink and Continue" is clearing, held across the
    /// second NFC session so its result can be matched to the right tag.
    @State private var pendingUnlinkUID: String?
    @State private var showCustomizeFields = false
    @State private var fieldVisibilityRefreshToken = 0

    /// The two ways of stating what the spool still holds. A measured (GROSS)
    /// scale reading is NOT one of them — it is an input that DERIVES this
    /// number, so it has its own row and its own field below rather than a
    /// third segment that silently reinterprets this one (owner, 2026-09-04).
    enum WeightMode: String, CaseIterable {
        case remaining = "Remaining"
        case used = "Total Used"
    }

    @State private var weightMode: WeightMode = .remaining
    @State private var weightInput: String = ""
    /// The GROSS scale reading, when one has been taken. Never prefilled: a
    /// measurement is taken, not derived, and offering the figure SpoolKid
    /// already believes would let a user "confirm" a weight they never put on
    /// a scale — which on FilaMan writes a phantom adjustment event and flips
    /// `status_id` (see `filaman-api.md`).
    @State private var measuredInput: String = ""
    /// The NET remaining weight the form currently believes, carried across
    /// mode switches. Needed because `.measured` shows an empty field by
    /// design: without an anchor, Remaining → Measured → Remaining would come
    /// back blank and quietly drop the weight the spool arrived with.
    @State private var lastKnownNetRemaining: Double? = nil
    /// Grams this print used, typed into the Used row (#17). Resolved into the
    /// mode field as it changes; a Measured reading clears it.
    @State private var usedThisPrintInput: String = ""
    /// The text Used last wrote into `weightInput`. A change to the mode field
    /// that is NOT this text is the user taking it over, which clears Used.
    @State private var weightInputSetByUsed: String? = nil

    /// The numeric fields, so the keyboard bar's Done button has something to
    /// resign. `.decimalPad` has no return key, so without this every weight
    /// and price entry traps the keyboard over the rest of the form — which is
    /// how the measured-weight suggestion came to be invisible behind it.
    /// The Used and Measured fields are focused through `adjustFocus`, owned
    /// by `SpoolWeightAdjustRows`.
    enum NumericField: Hashable {
        case price, initialWeight, spoolWeight, weightInput
    }
    @FocusState private var focusedNumericField: NumericField?
    @FocusState private var adjustFocus: SpoolWeightAdjustRows.Field?

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func visibleFieldIDs(for capabilities: BackendCapabilities) -> Set<String> {
        FieldVisibilityStore(support: capabilities.fieldSupport).visibleFieldIDs(for: .spool)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func locationPatch(for location: String) -> SpoolmanPatchValue<String> {
        let normalizedLocation = normalized(location)
        return normalizedLocation.isEmpty ? .setNil : .set(normalizedLocation)
    }

    static func spoolPayload(
        filamentId: Int?,
        price: String,
        initialWeight: String,
        spoolWeight: String,
        remainingWeight: String,
        usedWeight: String,
        location: String,
        comment: String,
        archived: Bool,
        firstUsedISO8601: String,
        lastUsedISO8601: String,
        // FilaMan-only (Task 7). `purchaseDateISO` is `purchaseDate` rendered
        // through `CalendarDateCodec` (a CALENDAR date, not an instant — see
        // its doc comment), converted before this call so the function stays
        // a pure string-in, `SpoolDraft`-out seam like the rest.
        statusKey: String = "",
        externalId: String = "",
        purchaseDateISO: String = "",
        // What `.onAppear` loaded from the spool. Empty when creating. A field
        // still holding its loaded value is `.ignore` — see `weightPatch` and
        // `textPatch`. Passing nothing is therefore the CREATE case, where
        // every stated field is `.set` and every empty one `.ignore`.
        loadedInitialWeight: String = "",
        loadedSpoolWeight: String = "",
        loadedRemainingWeight: String = "",
        loadedComment: String = "",
        loadedFirstUsed: String = "",
        loadedLastUsed: String = "",
        loadedStatusKey: String = "",
        loadedExternalId: String = "",
        loadedPurchaseDate: String = ""
    ) -> SpoolDraft {
        func parseDouble(_ value: String) -> Double? {
            let normalizedValue = normalized(value).replacingOccurrences(of: ",", with: ".")
            guard !normalizedValue.isEmpty else { return nil }
            return Double(normalizedValue)
        }

        let weightPair = weightPairPatch(
            initialWeight: initialWeight, loadedInitialWeight: loadedInitialWeight,
            spoolWeight: spoolWeight, loadedSpoolWeight: loadedSpoolWeight
        )

        return SpoolDraft(
            filamentId: filamentId,
            firstUsed: textPatch(current: firstUsedISO8601, loaded: loadedFirstUsed),
            lastUsed: textPatch(current: lastUsedISO8601, loaded: loadedLastUsed),
            price: parseDouble(price),
            initialWeight: weightPair.initial,
            spoolWeight: weightPair.basis,
            remainingWeight: weightPatch(current: remainingWeight, loaded: loadedRemainingWeight),
            usedWeight: weightPatch(current: usedWeight, loaded: ""),
            location: locationPatch(for: location),
            // No `lotNr`. This form has never edited a lot number — it read
            // the spool's own back and sent it again, which `.ignore` says
            // properly and without a write. Tag mappings are
            // `persistCardUIDs`'s.
            comment: textPatch(current: comment, loaded: loadedComment),
            archived: archived,
            statusKey: textPatch(current: statusKey, loaded: loadedStatusKey),
            externalId: textPatch(current: externalId, loaded: loadedExternalId),
            purchaseDate: textPatch(current: purchaseDateISO, loaded: loadedPurchaseDate)
        )
    }

    /// Which of the three states a weight field is in, given what it holds now
    /// and what was loaded into it.
    ///
    /// This is the half of R21 the TYPE alone does not fix. `SpoolFormView`
    /// loads a spool's current weights into its fields on appear, so before
    /// this every save re-asserted them — and two people editing one spool
    /// meant the second silently reverted the first. A field still holding
    /// exactly what was loaded says nothing now.
    ///
    /// An EMPTY field is `.ignore`, not `.setNil`: that is what empty has
    /// always meant here, and the form offers no "clear this weight" control
    /// to mean anything else. Inventing one would clear weights for users who
    /// simply blanked a box (A6's cousin — do not ship behaviour nobody asked
    /// for).
    ///
    /// `loaded` is empty when creating, so every stated field is `.set`.
    nonisolated static func weightPatch(current: String, loaded: String) -> SpoolmanPatchValue<Double> {
        let normalizedCurrent = normalized(current).replacingOccurrences(of: ",", with: ".")
        guard !normalizedCurrent.isEmpty, let value = Double(normalizedCurrent) else { return .ignore }
        let normalizedLoaded = normalized(loaded).replacingOccurrences(of: ",", with: ".")
        // Unchanged since it was loaded: the user did not touch it.
        if !normalizedLoaded.isEmpty, normalizedCurrent == normalizedLoaded { return .ignore }
        return .set(value)
    }

    /// The gross figure and its basis, resolved together (F31).
    ///
    /// `spoolWeightKeys` refuses a gross figure whose basis is unstated,
    /// because guessing one lets FilaMan rewrite the number. The form is the
    /// layer that can prevent that combination arising: when it states an
    /// initial weight it also states the basis it is holding, touched or not.
    nonisolated static func weightPairPatch(
        initialWeight: String, loadedInitialWeight: String,
        spoolWeight: String, loadedSpoolWeight: String
    ) -> (initial: SpoolmanPatchValue<Double>, basis: SpoolmanPatchValue<Double>) {
        let initial = weightPatch(current: initialWeight, loaded: loadedInitialWeight)
        var basis = weightPatch(current: spoolWeight, loaded: loadedSpoolWeight)
        if case .set = initial, case .ignore = basis {
            let normalizedBasis = normalized(spoolWeight).replacingOccurrences(of: ",", with: ".")
            basis = .set(Double(normalizedBasis) ?? 0)
        }
        return (initial, basis)
    }

    /// A text field's three states, given what it holds now and what was
    /// loaded into it. One rule for create and update alike: `loaded` is empty
    /// when creating, so a stated box is `.set` and an empty one `.ignore`.
    ///
    /// **An emptied box is `.setNil` — the opposite of `weightPatch`,
    /// deliberately.** The form loads a spool's text into its boxes on appear,
    /// so a box the user emptied is a box the user cleared; there is nothing
    /// else it could mean. A weight box has the identical shape and the
    /// opposite answer, because clearing a weight is not something this form
    /// offers. The two sit next to each other so the difference is visible
    /// rather than inferred.
    ///
    /// A box still holding exactly what was loaded says NOTHING — same lost
    /// update `weightPatch` closes. It also decides whether FilaMan nags: a
    /// date it refuses is reported whenever the draft states one, and an
    /// untouched date box must therefore not state anything.
    nonisolated static func textPatch(current: String, loaded: String) -> SpoolmanPatchValue<String> {
        let trimmedCurrent = normalized(current)
        guard trimmedCurrent != normalized(loaded) else { return .ignore }
        return trimmedCurrent.isEmpty ? .setNil : .set(trimmedCurrent)
    }

    /// The chosen filament's brand: the vendor's name, nil with no filament
    /// or no vendor. Computed, so a filament list that loads late counts.
    private var filamentManufacturer: String? {
        store.filaments.first { $0.id == filamentId }?.vendor?.name
    }

    private var filamentManufacturerKey: String {
        ManufacturerName.key(filamentManufacturer ?? "")
    }

    /// The chosen filament's own spool weight, nil with no filament or none
    /// stated. Computed, so a filament list that loads late counts.
    private var filamentSpoolWeight: Double? {
        store.filaments.first { $0.id == filamentId }?.spoolWeight
    }

    /// The chosen filament's own net weight, nil with no filament or none
    /// stated. Computed, so a filament list that loads late counts.
    private var filamentNetWeight: Double? {
        store.filaments.first { $0.id == filamentId }?.weight
    }

    /// The catalogue's answer for the chosen filament; nil for any other.
    private var catalogSpoolWeight: Double? {
        guard let lookedUp, lookedUp.filamentId == filamentId else { return nil }
        return lookedUp.grams
    }

    /// The scanned tag's weight as an offer for the filament the form opened
    /// with; nil when editing or when the tag states none.
    private var tagOffer: (filamentId: Int, grams: Double)? {
        guard spoolToEdit == nil, let initialFilamentId,
              let grams = FilamentTagData.statedMeasurement(tagWeights?.empty)
        else { return nil }
        return (initialFilamentId, grams)
    }

    private var newSpoolFilamentWeight: Double? {
        Self.filamentAccountWeight(
            tagOffer: tagOffer, filamentId: filamentId, own: filamentSpoolWeight, catalogue: catalogSpoolWeight
        )
    }

    /// The weight a new spool starts from on the filament's account, first
    /// that exists: the scanned tag's, while the chosen filament is the one it
    /// was offered for (the tag describes this physical spool); the filament's
    /// own spool weight (> 0); what its catalogue answered.
    nonisolated static func filamentAccountWeight(
        tagOffer: (filamentId: Int, grams: Double)?, filamentId: Int?, own: Double?, catalogue: Double?
    ) -> Double? {
        if let tagOffer, tagOffer.filamentId == filamentId { return tagOffer.grams }
        if let own, own > 0 { return own }
        return catalogue
    }

    /// What may go back to the saved filament: the tag's weight when it was
    /// offered for that filament, else the catalogue's answer. Either goes
    /// through `CatalogSpoolWeight.weightToSave`.
    nonisolated static func writeBackOffer(
        tagOffer: (filamentId: Int, grams: Double)?, lookedUp: (filamentId: Int, grams: Double)?,
        savedFilamentId: Int
    ) -> (filamentId: Int, grams: Double)? {
        if let tagOffer, tagOffer.filamentId == savedFilamentId { return tagOffer }
        return lookedUp
    }

    /// The chosen filament while a catalogue lookup could still supply its
    /// missing spool weight: a new spool, a filament that states none, and no
    /// tag weight for it. Computed, so a filament list that loads late starts
    /// the lookup.
    private var catalogLookupFilament: Filament? {
        guard spoolToEdit == nil,
              let filament = store.filaments.first(where: { $0.id == filamentId }),
              (filament.spoolWeight ?? 0) <= 0,
              tagOffer?.filamentId != filament.id
        else { return nil }
        return filament
    }

    /// What a new spool's Empty Spool Weight is derived from. Two filaments of
    /// one brand can state different weights, so the brand alone is not the
    /// key; a change in any part refills an untouched field.
    private struct EmptyWeightSource: Equatable {
        let filamentId: Int?
        let brandKey: String
        let spoolWeight: Double?
        let catalogWeight: Double?
    }

    private var emptyWeightSource: EmptyWeightSource {
        EmptyWeightSource(
            filamentId: filamentId,
            brandKey: filamentManufacturerKey,
            spoolWeight: filamentSpoolWeight,
            catalogWeight: catalogSpoolWeight
        )
    }

    @ViewBuilder
    private var filamentSection: some View {
        Section("Filament") {
            NavigationLink {
                FilamentSelectionView(selectedFilamentID: $filamentId, store: store)
            } label: {
                if let id = filamentId, let filament = store.filaments.first(where: { $0.id == id }) {
                    // Same headline and spec line as the picker the filament came from.
                    HStack {
                        if !filament.colors.hexes.isEmpty {
                            FilamentSwatch(colors: filament.colors, size: 24)
                        }
                        VStack(alignment: .leading) {
                            Text(filament.listTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(filament.listSpecParts.joined(separator: " • "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    HStack {
                        Text("Filament")
                        Spacer()
                        Text("Select Filament").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Weight frames

    /// Every weight field says NET or GROSS in its own caption, because the
    /// frame is invisible in the number and FilaMan's web UI uses "Initial
    /// Total Weight" for the GROSS figure — the same words for the other
    /// frame. Reported 2026-08-24: a full spool weighed at 1238 g on a 238 g
    /// core was entered as Initial 1238 / Empty 238 and stored, faithfully, as
    /// 1238 g of filament.
    static let initialWeightCaption =
        "NET — the filament only, with no spool. A full 1 kg spool is 1000, "
        + "whatever the scale says."

    static let spoolWeightCaption =
        "The bare spool or cardboard core with no filament on it."

    /// What a new spool's Initial Filament Weight starts as, first that exists:
    /// the scanned tag's (it describes this physical spool), the chosen
    /// filament's own net weight (> 0), else 1000. Never the last value saved:
    /// a tag's weight would carry into the next spool. Edit mode never calls this.
    nonisolated static func newSpoolInitialWeight(tagWeight: Double?, filamentWeight: Double?) -> String {
        if let grams = FilamentTagData.statedMeasurement(tagWeight) { return formatWeight(grams) }
        if let filamentWeight, filamentWeight > 0 { return formatWeight(filamentWeight) }
        return formatWeight(1000)
    }

    /// The new text when the filament's net weight changes, or nil to leave the
    /// field alone: the same rule as `refilledEmptyWeight`. A tag's weight is
    /// never auto-filled, so it never follows a filament change.
    nonisolated static func refilledInitialWeight(
        current: String, autoFilled: String?, isNewSpool: Bool, filamentWeight: Double?
    ) -> String? {
        guard isNewSpool, let autoFilled, current == autoFilled else { return nil }
        return newSpoolInitialWeight(tagWeight: nil, filamentWeight: filamentWeight)
    }

    /// The usual spool sizes Add Spool offers under Initial Filament Weight:
    /// Spoolman's six.
    nonisolated static let initialWeightPresets: [Double] = [250, 500, 750, 1000, 2000, 3000]

    /// "250 g", "1 kg": whole kilograms read as kilograms.
    nonisolated static func presetLabel(_ grams: Double) -> String {
        grams >= 1000 && grams.truncatingRemainder(dividingBy: 1000) == 0
            ? "\(Int(grams / 1000)) kg"
            : "\(formatWeight(grams)) g"
    }

    nonisolated static func isPresetSelected(_ grams: Double, field: String) -> Bool {
        parseWeight(field) == grams
    }

    /// What a new spool's Empty Spool Weight starts as, first that exists: the
    /// weight on the filament's account (`filamentAccountWeight`: the tag's,
    /// the filament's own, the catalogue's; > 0, 0 and nil mean unknown), the
    /// weight of the entry `EmptySpoolLibrary.prefillEntry(forManufacturer:)`
    /// picks for the filament's brand, then the last value saved (the
    /// behaviour before the library existed). Edit mode never calls this.
    nonisolated static func newSpoolEmptyWeight(
        filamentWeight: Double? = nil, entryWeight: Double?, lastUsed: String
    ) -> String {
        if let filamentWeight, filamentWeight > 0 {
            return SpoolWeightMath.formatWeight(filamentWeight)
        }
        guard let entryWeight else { return lastUsed }
        return SpoolWeightMath.formatWeight(entryWeight)
    }

    /// The new text when the filament changes, or nil to leave the field
    /// alone. A new spool follows the filament only while the field still
    /// holds exactly what the form last filled in by itself (`autoFilled`): a
    /// typed value no longer matches it, and a pick or an applied scale
    /// suggestion clears it, so the user's number is never overwritten.
    nonisolated static func refilledEmptyWeight(
        current: String, autoFilled: String?, isNewSpool: Bool,
        filamentWeight: Double? = nil, entryWeight: Double?, lastUsed: String
    ) -> String? {
        guard isNewSpool, let autoFilled, current == autoFilled else { return nil }
        return newSpoolEmptyWeight(filamentWeight: filamentWeight, entryWeight: entryWeight, lastUsed: lastUsed)
    }

    /// Why there is no Remaining/Used choice on this backend.
    nonisolated static func singleWeightModeNote(_ backendName: String) -> String {
        "\(backendName) works out used weight from the other figures rather than "
            + "storing it, so remaining weight is the only one to state here."
    }

    static let measuredWeightCaption =
        "GROSS — the whole spool on the scale, filament and spool together."

    static func weightModeCaption(_ mode: WeightMode) -> String {
        switch mode {
        case .remaining:
            return "NET — filament still on the spool."
        case .used:
            return "NET — filament already printed. Initial Filament Weight minus what is left."
        }
    }

    /// The one line that stays under a weight field once the long captions
    /// moved into the (i): the frame is invisible in the number, and a full
    /// spool's 1238 g was once entered as filament weight (2026-08-24).
    static let initialWeightFrame = "NET — filament only"
    static let measuredWeightFrame = "GROSS — spool and filament"

    static func weightModeFrame(_ mode: WeightMode) -> String {
        switch mode {
        case .remaining: return "NET — filament left on the spool"
        case .used: return "NET — filament already printed"
        }
    }

    // MARK: - One spool, three readings

    /// The NET filament remaining that `input` asserts when read in `mode`, or
    /// nil when the entry cannot be resolved into one.
    ///
    /// The three modes are three ways of stating the same physical fact, and
    /// one `@State` holds all of them — so switching the picker used to leave
    /// the number in place and silently reinterpret it. A spool with 750 g left
    /// then claimed 750 g *used* and 750 g *on the scale*.
    nonisolated static func netRemaining(
        input: String,
        mode: WeightMode,
        initialWeight: String,
        spoolWeight: String
    ) -> Double? {
        guard let value = parseWeight(input) else { return nil }
        switch mode {
        case .remaining:
            return value
        case .used:
            // Without an initial weight "used" names no remainder at all; that
            // is unknown, not zero.
            guard let initial = parseWeight(initialWeight) else { return nil }
            return initial - value
        }
    }

    /// The NET filament remaining that a GROSS scale reading implies, or nil
    /// when the reading cannot be parsed.
    ///
    /// A missing core weight means a core that weighs nothing — the same
    /// assumption `saveSpools` makes for the same entry.
    nonisolated static func netFromMeasured(
        measured: String,
        spoolWeight: String
    ) -> Double? {
        guard let gross = parseWeight(measured) else { return nil }
        return SpoolWeightMath.netFromGross(
            gross: gross,
            emptySpoolWeight: parseWeight(spoolWeight) ?? 0
        )
    }

    /// What the field should show for `mode`, given the NET remaining weight
    /// currently known. Empty whenever the mode's number cannot be stated.
    ///
    /// `.measured` is ALWAYS empty: a measurement is taken, not derived.
    /// Prefilling it with the gross figure SpoolKid already believes would
    /// invite the user to "confirm" a weight they never put on a scale, and on
    /// FilaMan saving one writes an adjustment event and flips `status_id`.
    nonisolated static func weightInputText(
        for mode: WeightMode,
        netRemaining: Double?,
        initialWeight: String
    ) -> String {
        guard let netRemaining else { return "" }
        switch mode {
        case .remaining:
            return formatWeight(netRemaining)
        case .used:
            guard let initial = parseWeight(initialWeight) else { return "" }
            // A spool cannot have used a negative amount. When its own numbers
            // say otherwise — an initial weight entered as a gross figure
            // leaves exactly this — the field shows nothing and
            // `usedWeightUnavailableNote` explains it, rather than rendering
            // "-238" into a box the user types into. Empty also reads back as
            // nil, so the mode switch falls through to the anchor and the
            // remaining weight survives the round trip.
            guard initial >= netRemaining else { return "" }
            return formatWeight(initial - netRemaining)
        }
    }

    /// The mode field's new text once grams used this print are stated, or nil
    /// when that entry states nothing usable. Blank Used restores `base`, the
    /// remaining weight the spool was loaded with.
    nonisolated static func weightInputAfterUsedThisPrint(
        used: String,
        base: Double?,
        mode: WeightMode,
        initialWeight: String
    ) -> String? {
        guard let base else { return nil }
        let net: Double
        if normalized(used).isEmpty {
            net = base
        } else {
            guard let grams = parseWeight(used), grams > 0, grams.isFinite else { return nil }
            net = base - grams
        }
        return weightInputText(for: mode, netRemaining: net, initialWeight: initialWeight)
    }

    /// The mode Used this print must write in. Total Used cannot state a figure
    /// without an Initial Filament Weight, or when the loaded remaining is above
    /// it, so a non-blank Used then switches to Remaining: Save writes the figure
    /// rather than dropping it. Otherwise the mode is unchanged.
    nonisolated static func modeForUsedThisPrint(
        used: String,
        base: Double?,
        mode: WeightMode,
        initialWeight: String
    ) -> WeightMode {
        guard mode == .used, !normalized(used).isEmpty,
              weightInputAfterUsedThisPrint(
                  used: used, base: base, mode: .used, initialWeight: initialWeight
              ) == "" else { return mode }
        return .remaining
    }

    /// Whether Used's figure survives a mode switch. The converted text is
    /// empty when the new mode cannot state it (Total Used without an Initial
    /// Filament Weight); keeping Used then would show a figure Save drops.
    nonisolated static func usedSurvivesModeChange(convertedText: String) -> Bool {
        !convertedText.isEmpty
    }

    /// Whether new mode-field text means the user typed over Used's figure.
    /// Text Used itself wrote is not a takeover.
    nonisolated static func weightInputTakesOverUsed(_ newValue: String, setByUsed: String?) -> Bool {
        guard let setByUsed else { return false }
        return newValue != setByUsed
    }

    /// Why the Used field is empty when the spool holds more than its stated
    /// initial weight, or nil when it is not. Names the field to correct,
    /// because that is the one the user got wrong.
    nonisolated static func usedWeightUnavailableNote(
        netRemaining: Double?,
        initialWeight: String
    ) -> String? {
        guard let netRemaining, let initial = parseWeight(initialWeight) else { return nil }
        guard netRemaining > initial else { return nil }
        return "This spool holds more filament than its Initial Filament Weight, so nothing "
            + "here counts as used. Check that Initial Filament Weight is the filament alone."
    }

    // MARK: - Assigning a measurement's difference

    static let assignDifferenceTitle = "Assign the Difference"

    /// Scroll target for the Weight Status section. Focusing a numeric field
    /// only guarantees the FIELD is above the keyboard; the suggestion renders
    /// below it, so the section is scrolled to instead.
    static let weightSectionAnchor = "weight-status-section"

    /// A field a scale reading could fill in, on a spool being created.
    nonisolated enum MeasuredWeightSuggestion: Equatable {
        /// The reading is heavier than the filament alone; the surplus is the
        /// spool itself.
        case setEmptySpoolWeight(Double)
        /// The reading is lighter than filament + spool; the shortfall is
        /// filament already gone.
        case setUsedFilament(Double)

        var prompt: String {
            switch self {
            case .setEmptySpoolWeight(let grams):
                return "That is \(SpoolFormView.formatWeight(grams)) g more than the filament alone. "
                    + "Use it as the Empty Spool Weight?"
            case .setUsedFilament(let grams):
                return "That is \(SpoolFormView.formatWeight(grams)) g less than a full spool. "
                    + "Record it as filament already used?"
            }
        }
    }

    /// What the difference between a scale reading and the entered weights can
    /// be assigned to, or nil when nothing can be offered.
    ///
    /// Only on a NEW spool. An existing spool's core weight is a fact already
    /// recorded, and rewriting it from one reading moves the reported remaining
    /// weight of the whole spool by the same delta (F32) — a measurement of
    /// what is left must never redefine what the spool is.
    ///
    /// A reading below the initial weight with **no** core weight entered is
    /// deliberately not offered to either field: it could be a light spool or a
    /// part-used one, and the arithmetic cannot tell. Guessing would write a
    /// number the user never chose into a field they left empty.
    nonisolated static func measuredWeightSuggestion(
        measured: String,
        initialWeight: String,
        spoolWeight: String,
        isNewSpool: Bool
    ) -> MeasuredWeightSuggestion? {
        guard isNewSpool,
              let measured = parseWeight(measured),
              let initial = parseWeight(initialWeight) else { return nil }

        guard let spool = parseWeight(spoolWeight) else {
            guard measured > initial else { return nil }
            return .setEmptySpoolWeight(measured - initial)
        }

        let full = initial + spool
        guard measured < full else { return nil }
        return .setUsedFilament(full - measured)
    }

    private nonisolated static func parseWeight(_ value: String) -> Double? {
        SpoolWeightMath.parseWeight(value)
    }

    /// Grams, without a trailing `.0` on a whole number — the field is one the
    /// user types into, so it has to read like something they would type.
    nonisolated static func formatWeight(_ grams: Double) -> String {
        SpoolWeightMath.formatWeight(grams)
    }

    @ViewBuilder
    private var propertiesSection: some View {
        Section {
            if spoolToEdit == nil {
                Stepper(value: $count, in: SpoolBatch.countRange) {
                    HStack {
                        Text("Count")
                        Spacer()
                        Text("\(count)")
                    }
                }
                .accessibilityIdentifier("spoolForm.count")
                // Once spools exist the batch is fixed: a count that changed now
                // would not match what was saved. Mid-save it is the batch being
                // created.
                .disabled(isSaved || isSaving)
            }
            HStack {
                Text("Price")
                Spacer()
                TextField("0.00", text: $price)
                    .keyboardType(.decimalPad)
                    .focused($focusedNumericField, equals: .price)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Initial Filament Weight (g)")
                    Spacer()
                    TextField("1000", text: $initialWeight)
                        .keyboardType(.decimalPad)
                        .focused($focusedNumericField, equals: .initialWeight)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Text(Self.initialWeightFrame)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if spoolToEdit == nil {
                    initialWeightPresetChips
                }
            }
            HStack {
                Text("Empty Spool Weight (g)")
                Spacer()
                TextField("0", text: $spoolWeight)
                    .keyboardType(.decimalPad)
                    .focused($focusedNumericField, equals: .spoolWeight)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("spoolForm.emptySpoolWeight")
                // Copies the number only; the field stays typeable for a
                // spool the library does not hold.
                EmptySpoolPickerButton(
                    accessibilityID: "spoolForm.emptySpoolPicker",
                    manufacturer: filamentManufacturer
                ) { grams in
                    spoolWeight = Self.formatWeight(grams)
                    autoFilledSpoolWeight = nil
                }
            }
        } header: {
            HStack {
                Text("Properties")
                Spacer()
                // The first (i) on the form carries the one-time tip.
                InfoButton(
                    title: "Properties",
                    lines: [Self.initialWeightCaption, Self.spoolWeightCaption],
                    introTip: hidesFirstRunTips ? nil : InfoButtonTip()
                )
            }
        }
    }

    /// Add Spool's size chips: a tap sets Initial Filament Weight, and the
    /// field stops following the filament. The chip matching the field is
    /// prominent. Bordered styles keep each chip its own tap target inside
    /// the form row, and dim with the section once it locks.
    private var initialWeightPresetChips: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.initialWeightPresets, id: \.self) { grams in
                let selected = Self.isPresetSelected(grams, field: initialWeight)
                let button = Button(Self.presetLabel(grams)) {
                    initialWeight = Self.formatWeight(grams)
                    autoFilledInitialWeight = nil
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("spoolForm.initialWeightPreset.\(Int(grams))")
                if selected {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, 4)
    }

    /// The NET remaining the spool was loaded with, the figure Used this print
    /// is taken from. Nil on a new spool, and on one with no remaining weight.
    private var loadedRemainingValue: Double? {
        SpoolWeightMath.parseWeight(loadedRemainingWeight)
    }

    /// What the Used or Measured entry would leave, or nil when neither states
    /// a usable number. A new spool has no `loadedRemainingValue`, so only a
    /// Measured reading can preview there.
    private var adjustmentPreview: SpoolWeightAdjustment.Preview? {
        Self.adjustmentPreview(
            used: usedThisPrintInput,
            measured: measuredInput,
            loadedRemaining: loadedRemainingValue,
            spoolWeight: spoolWeight
        )
    }

    /// The preview the form shows for the Used and Measured entries. Save
    /// consults the same value, so what the note says and what Save does agree.
    nonisolated static func adjustmentPreview(
        used: String,
        measured: String,
        loadedRemaining: Double?,
        spoolWeight: String
    ) -> SpoolWeightAdjustment.Preview? {
        guard let input = SpoolWeightAdjustment.input(used: used, measured: measured) else {
            return nil
        }
        let outcome = SpoolWeightAdjustment.outcome(
            of: input,
            currentRemaining: loadedRemaining,
            emptySpoolWeight: parseWeight(spoolWeight) ?? 0
        )
        return SpoolWeightAdjustment.Preview(before: loadedRemaining, outcome: outcome)
    }

    /// Whether Save must refuse because the adjustment would leave the spool
    /// below zero. Applies in every Input Mode: in Total Used, a Used larger
    /// than what remains otherwise writes a used figure above the initial weight.
    nonisolated static func refusesNegativeAdjustment(_ preview: SpoolWeightAdjustment.Preview?) -> Bool {
        if case .negative = preview?.outcome { return true }
        return false
    }

    @ViewBuilder
    private var weightStatusSection: some View {
        // Support-gated, not preference-gated: FilaMan's PATCH derives used
        // weight from the other two (F31 review, fix round 1) rather than
        // storing it, so there is nothing for this mode to read or write —
        // unlike Advanced's fields, this has no "off by default" state to
        // respect, only "present or not."
        let showsUsedMode = store.capabilities.fieldSupport.supports("used_weight", in: .spool)
        let availableModes = WeightMode.allCases.filter { $0 != .used || showsUsedMode }

        Section {
            // One segment is not a choice. FilaMan derives used weight rather
            // than storing it, so on that backend this collapses to Remaining
            // alone and the picker would be a control with nothing to pick.
            if availableModes.count > 1 {
                Picker("Input Mode", selection: $weightMode) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(weightMode.rawValue) Weight (g)")
                    Spacer()
                    TextField("0", text: $weightInput)
                        .keyboardType(.decimalPad)
                        .focused($focusedNumericField, equals: .weightInput)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Text(Self.weightModeFrame(weightMode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if weightMode == .used,
               let note = Self.usedWeightUnavailableNote(
                   netRemaining: lastKnownNetRemaining, initialWeight: initialWeight
               ) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            // Used this print and Measured share one component, which also says
            // what the adjustment would leave. Measured sits on its OWN row,
            // below the number it derives: it is a scale reading, not a third
            // way of stating the remaining weight (owner, 2026-09-04).
            SpoolWeightAdjustRows(
                usedInput: $usedThisPrintInput,
                measuredInput: $measuredInput,
                showsUsed: spoolToEdit != nil && loadedRemainingValue != nil,
                measuring: .available,
                preview: adjustmentPreview,
                focus: $adjustFocus
            )

            if !measuredInput.isEmpty {
                // A reading that disagrees with the entered weights has a
                // difference, and on a new spool that difference belongs
                // somewhere. Offered, never applied silently: it fills a field
                // the user left empty.
                if let suggestion = Self.measuredWeightSuggestion(
                    measured: measuredInput,
                    initialWeight: initialWeight,
                    spoolWeight: spoolWeight,
                    isNewSpool: spoolToEdit == nil
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(Self.assignDifferenceTitle, systemImage: "scalemass")
                            .font(.subheadline.weight(.semibold))
                        // Body text in the primary colour, not `.secondary`:
                        // this is an offer the user has to read and act on, and
                        // as a grey caption it went unnoticed behind a keyboard.
                        Text(suggestion.prompt)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Button("Apply") { apply(suggestion) }
                            // Prominent, so the label is white on the accent
                            // rather than accent-on-accent-tint, which is the
                            // low contrast `.bordered` gives here.
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Text("Weight Status")
                Spacer()
                // Say why the Input Mode control is absent, on a
                // single-mode backend, rather than just omitting it. The
                // owner looked for Used on FilaMan and reported it missing
                // (2026-09-05); it had never been there — FilaMan derives
                // used weight instead of storing it — but until Measured
                // moved to its own row the picker still rendered, so its
                // disappearance read as the field going away. Same "keep +
                // explain" call the mapping buttons took on 2026-08-25. The
                // note itself now lives here, in the (i), rather than on
                // screen.
                InfoButton(
                    title: "Weight Status",
                    lines: (availableModes.count > 1 ? [] : [Self.singleWeightModeNote(store.capabilities.displayName)])
                        + [Self.weightModeCaption(weightMode), Self.measuredWeightCaption]
                )
            }
        }
        .id(Self.weightSectionAnchor)
    }

    /// The same merge every other location list uses: a shelf that exists only
    /// in the device-local registry — one no spool has been assigned to yet —
    /// is missing from `store.locations` on Spoolman and Local, and this is the
    /// screen where a user normally puts the first spool in it.
    private var choosableLocations: [String] {
        ManageLocationsView.mergedLocations(
            observed: store.spools.compactMap(\.location),
            known: store.locations,
            registered: store.registeredLocations.map(\.name)
        )
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            // One control (audit S2): None, a known location, or a new name.
            // Locations are spool-derived, so naming one here is how a new
            // location is created.
            Menu {
                Button("None") { location = "" }
                if !choosableLocations.isEmpty {
                    Divider()
                    ForEach(choosableLocations, id: \.self) { item in
                        Button(item) { location = item }
                    }
                }
                Divider()
                Button("New Location…") {
                    newLocationName = ""
                    isNamingNewLocation = true
                }
            } label: {
                HStack {
                    Text("Location")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(location.isEmpty ? "None" : location)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("New Location", isPresented: $isNamingNewLocation) {
                TextField("Name", text: $newLocationName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let name = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { location = name }
                }
            }
        }
    }

    private func resolvedStatusKey(for spool: Spool) -> String {
        store.spoolStatusOptions.first { $0.id == spool.statusId }?.key ?? ""
    }

    /// FilaMan-only (Task 7). Status supersedes the Archived toggle — exactly
    /// one of the two ever reaches `visibleFieldIDs` on any backend
    /// (`BackendFieldSupportTests.exactlyOneArchiveControlPerBackend`) — and
    /// Purchase Date has no Spoolman/Local equivalent at all. An empty
    /// `store.spoolStatusOptions` hides the picker rather than showing one
    /// with nothing in it: a spool's status is left alone, not guessed.
    @ViewBuilder
    private func inventorySection(visibleFieldIDs: Set<String>) -> some View {
        Section("Inventory") {
            if visibleFieldIDs.contains("status") && !store.spoolStatusOptions.isEmpty {
                Picker("Status", selection: $statusKey) {
                    ForEach(store.spoolStatusOptions) { option in
                        Text(option.label).tag(option.key)
                    }
                }
            }
            if visibleFieldIDs.contains("purchase_date") {
                // Matches how First Used/Last Used read: an unset field shows
                // as unset, never a fabricated "today", and the user has an
                // explicit way to clear a set one. `DatePicker` has no empty
                // state of its own, so the toggle stands in for "the box is
                // blank" — off means `purchaseDate` is `nil`, which
                // `textPatch` (fed by `purchaseDateISO`) turns into `.setNil`
                // when it was previously loaded, and `.ignore` when it never
                // held one.
                Toggle("Purchase Date", isOn: Binding(
                    get: { purchaseDate != nil },
                    set: { isOn in purchaseDate = isOn ? (purchaseDate ?? Date()) : nil }
                ))
                if let date = purchaseDate {
                    DatePicker("Date", selection: Binding(
                        get: { date },
                        set: { purchaseDate = $0 }
                    ), displayedComponents: .date)
                }
            }
        }
    }

    @ViewBuilder
    private func advancedSection(visibleFieldIDs: Set<String>) -> some View {
        Section("Advanced") {
            if visibleFieldIDs.contains("comment") {
                TextField("Comment", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
            }

            if visibleFieldIDs.contains("archived") {
                Toggle("Archived", isOn: $archived)
            }

            if visibleFieldIDs.contains("first_used") {
                TextField("First Used (ISO8601)", text: $firstUsedISO8601)
                    .textInputAutocapitalization(.never)
            }

            if visibleFieldIDs.contains("last_used") {
                TextField("Last Used (ISO8601)", text: $lastUsedISO8601)
                    .textInputAutocapitalization(.never)
            }

            if visibleFieldIDs.contains("external_id") {
                TextField("External ID", text: $externalId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    /// D3/D4: which of the source spool's tags this new spool takes. A ticked
    /// tag is in Spool 1's list (section 0); unticking every tag moves nothing.
    @ViewBuilder
    private var tagMoveSection: some View {
        if let offer = openTagMoveOffer {
            Section {
                ForEach(offer.uids, id: \.self) { uid in
                    Toggle(isOn: Binding(
                        get: { movingTagUIDs.contains(uid) },
                        set: { isOn in
                            if isOn {
                                movingTagUIDs.insert(uid)
                                addTag(uid, toSection: 0)
                            } else {
                                movingTagUIDs.remove(uid)
                                removeTag(uid, fromSection: 0)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uid)
                                .font(.body.monospaced())
                            if uid == offer.scannedUID {
                                Text("Scanned")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Move Tags from \(offer.sourceTitle)")
            } footer: {
                Text("Ticked tags move to the new spool and are removed from \(offer.sourceTitle).")
                    .font(.subheadline)
            }
        }
    }

    /// Edit Spool's tag section, built from section 0.
    @ViewBuilder
    private var tagUIDSection: some View {
        Section {
            tagRows(section: 0)

            if addsLinks {
                TagReaderPicker(selection: $tagReader, purpose: .read)
                Button {
                    activeTagSection = 0
                    isScanningForCardUID = true
                    // Only a spool tag is an acceptable answer here, so a location
                    // tag is refused by the session itself and iOS shows its own
                    // error sheet — rather than reporting a clean read the app
                    // contradicts a moment later.
                    startScan()
                } label: {
                    Label(
                        isScanningForCardUID
                            ? (run.progressText ?? "Scanning…")
                            : "Scan tag to link",
                        systemImage: isScanningForCardUID ? "antenna.radiowaves.left.and.right" : "wave.3.right"
                    )
                    .foregroundStyle(isScanningForCardUID ? .orange : .accentColor)
                }
                .buttonStyle(.plain)
                .tagReplacePrompt($linkReplaceRequest) { request in
                    replaceLinkedTag(with: request, section: 0)
                }
                .disabled(nfcManager.isScanning || pendingTagWrites > 0)
            }
        } header: {
            HStack {
                Text("Linked Tags")
                Spacer()
                // Only where the mode adds links: the footer says why not.
                if addsLinks {
                    InfoButton(
                        title: "Linked Tags",
                        lines: ["Scan each physical tag to link it to this spool. SpoolKid then recognizes the spool from any of its tags."]
                    )
                }
            }
        } footer: {
            if let footer = Self.linkedTagsFooter(identity: store.tagIdentity) {
                Text(footer)
                    .font(.subheadline)
            }
        }
    }

    /// A section's tags, each with its remove button. Offered tags are listed
    /// once, in the Move Tags section above. A removal after an Add save is
    /// saved at once for that spool; before it, it is local.
    @ViewBuilder
    private func tagRows(section: Int) -> some View {
        ForEach(listedTags(in: section).filter { !(openTagMoveOffer?.uids.contains($0) ?? false) }, id: \.self) { uid in
            HStack(spacing: 10) {
                Text(uid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(role: .destructive) {
                    removeTag(uid, fromSection: section)
                    saveLinkedTagsNow(section: section)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Add Spool's tag sections, one per spool: `count` of them until the save,
    /// the saved spools after it. Each has its own Write Tag and Link Tag, so the
    /// control the user taps names the spool it acts on.
    @ViewBuilder
    private var addTagSections: some View {
        let sectionCount = isSaved ? savedSpools.count : count
        ForEach(Array(0..<sectionCount), id: \.self) { index in
            Section {
                tagRows(section: index)

                TagReaderPicker(selection: $tagReader, purpose: .write(format: TagFormatService.shared.currentFormat))
                if activeTagSection == index, nfcManager.lastWriteSucceeded, pendingTagWrites == 0,
                   run.offersOtherSide {
                    WriteOtherSideButton { writeOtherSide(section: index) }
                        .disabled(nfcManager.isScanning)
                }

                ForEach(Self.tagSectionActions(writesLinks: addsLinks), id: \.self) { action in
                    tagButton(action, section: index)
                }
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    // Once, above every section: it is about the save, not one spool.
                    if index == 0, !isSaved {
                        Text(Self.saveFirstNote(count: count, writesLinks: addsLinks))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .textCase(nil)
                    }
                    Text(Self.tagSectionTitle(position: index + 1, savedSpoolID: savedSpoolID(inSection: index)))
                }
            } footer: {
                if index == sectionCount - 1, let footer = Self.linkedTagsFooter(identity: store.tagIdentity) {
                    Text(footer)
                        .font(.subheadline)
                }
            }
        }
    }

    /// The spool's real number once the section's spool exists.
    private func savedSpoolID(inSection index: Int) -> Int? {
        isSaved && index < savedSpools.count ? savedSpools[index].id : nil
    }

    private func tagButton(_ action: TagAction, section index: Int) -> some View {
        let isScanningHere = action == .link && isScanningForCardUID && activeTagSection == index
        return Button {
            Task { await tagAction(action, section: index) }
        } label: {
            Label(
                buttonTitle(action, section: index, isScanningHere: isScanningHere),
                systemImage: isScanningHere ? "antenna.radiowaves.left.and.right" : action.systemImage
            )
            .foregroundStyle(isScanningHere ? Color.orange : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .needsServer()
        // On the button, and only for the section that asked: every section
        // has one, and they share the request.
        .tagReplacePrompt(Binding(
            get: { action == .write && activeTagSection == index ? replaceRequest : nil },
            set: { if $0 == nil { replaceRequest = nil } }
        )) { _ in
            guard index < savedSpools.count else { return }
            writeTag(for: savedSpools[index], replacing: true)
        }
        .tagReplacePrompt(Binding(
            get: { action == .link && activeTagSection == index ? linkReplaceRequest : nil },
            set: { if $0 == nil { linkReplaceRequest = nil } }
        )) { request in
            replaceLinkedTag(with: request, section: index)
        }
        .disabled(!Self.canStartTagAction(
            hasFilament: filamentId != nil, isSaving: isSaving,
            isScanning: nfcManager.isScanning, tagWritesPending: pendingTagWrites
        ))
        .accessibilityLabel(Self.tagButtonAccessibilityLabel(
            action, position: index + 1, savedSpoolID: savedSpoolID(inSection: index),
            isScanning: isScanningHere
        ))
    }

    private func buttonTitle(_ action: TagAction, section: Int, isScanningHere: Bool) -> String {
        if isScanningHere {
            return run.progressText ?? "Scanning…"
        }
        if action == .write, run.isWriting, activeTagSection == section, nfcManager.isScanning,
           let progress = run.progressText {
            return progress
        }
        return action.title
    }

    /// A link scan on the resolved reader.
    private func startScan() {
        run = .start(tagReader, purpose: .read, printer: printer, store: store)
        nfcManager.startScanning(rejectingLocationTags: true, reader: run.reader)
    }

    /// Chips can be ADDED only where the mode writes links; existing ones can
    /// always be removed (links are read in every mode, spec §2).
    private var addsLinks: Bool {
        store.tagIdentity.writesLinks
    }

    /// The move offer while it can still be taken: a new spool, before its
    /// save. After it the moved tags are Spool 1's, listed in its section.
    private var openTagMoveOffer: TagMoveOffer? {
        spoolToEdit == nil && !isSaved ? tagMoveOffer : nil
    }

    /// What a section's two buttons do.
    nonisolated enum TagAction: Hashable {
        case write, link

        var title: String { self == .write ? "Write Tag" : "Link Tag" }
        var systemImage: String { self == .write ? "wave.3.right" : "link" }
    }

    /// Write Tag or Link Tag on one section. The first tap on an unsaved form
    /// saves every spool first, and goes on only if the whole batch was created:
    /// a stopped one leaves the user an alert to read, which a write or scan
    /// starting underneath would bury, so they tap again.
    private func tagAction(_ action: TagAction, section: Int) async {
        if !isSaved {
            guard await saveSpools(closesOnSuccess: false) == .complete else { return }
        }
        // The button is disabled while a tag write is in flight; this is for a tap
        // delivered after it was, which must not start a claim against a stale store.
        guard pendingTagWrites == 0 else { return }
        // A spool the batch never created has nothing to write or link (C7).
        guard section < savedSpools.count else { return }
        activeTagSection = section
        // Set on every tap: a scan that was cancelled never clears it, and a stale
        // true would show "Scanning…" under whichever section was tapped next.
        isScanningForCardUID = action == .link
        switch action {
        case .write:
            let spool = store.spools.first { $0.id == savedSpools[section].id } ?? savedSpools[section]
            // Before the write: the new tag's ID is unknown until it is
            // written, and Cancel must leave the tag blank.
            if store.tagIdentity.writesLinks,
               let request = TagReplaceRequest.writing(
                   spool: spool, knownUID: nil, targets: store.tagIdentity.linkTargets
               ) {
                replaceRequest = request
                return
            }
            writeTag(for: savedSpools[section])
        case .link:
            startScan()
        }
    }

    /// An agreed Move: the holder the tag leaves, and the section that agreed
    /// it. Only that section's write releases it.
    nonisolated struct PendingMove: Equatable, Sendable {
        let holder: TagOwner
        let section: Int
    }

    /// Whether a tag button may start a write or a scan. Never while a tag write
    /// is queued or running (`pendingTagWrites`).
    nonisolated static func canStartTagAction(
        hasFilament: Bool, isSaving: Bool, isScanning: Bool, tagWritesPending: Int
    ) -> Bool {
        hasFilament && !isSaving && !isScanning && tagWritesPending == 0
    }

    /// The moves `section`'s write releases: those it agreed, for tags it still
    /// lists. Another section's agreed move is left for that section, so a write
    /// that runs first can neither spend it nor write the tag under two owners.
    nonisolated static func movesToRelease(
        section: Int, listed: [String], agreed: [String: PendingMove]
    ) -> [(uid: String, holder: TagOwner)] {
        listed.compactMap { uid in
            guard let move = agreed[uid], move.section == section else { return nil }
            return (uid: uid, holder: move.holder)
        }
    }

    /// Once an Add has saved, the shared fields describe spools that exist, and
    /// nothing re-saves them: they lock, and the tag sections stay live. Edit
    /// Spool is where details change.
    nonisolated static func sharedFieldsLocked(isEditing: Bool, isSaved: Bool) -> Bool {
        !isEditing && isSaved
    }

    private var sharedFieldsAreLocked: Bool {
        Self.sharedFieldsLocked(isEditing: spoolToEdit != nil, isSaved: isSaved)
    }

    /// Section `section`'s tags; [] for a section that has none yet.
    private func listedTags(in section: Int) -> [String] {
        tagSections.indices.contains(section) ? tagSections[section] : []
    }

    private func addTag(_ uid: String, toSection section: Int) {
        while tagSections.count <= section { tagSections.append([]) }
        if !tagSections[section].contains(uid) { tagSections[section].append(uid) }
    }

    /// A tag taken back out is no longer an agreed move: left in `pendingMoves`
    /// it would release the tag from whoever holds it when it is next listed.
    /// Only the section that agreed the move can take it back.
    private func removeTag(_ uid: String, fromSection section: Int) {
        if pendingMoves[uid]?.section == section { pendingMoves[uid] = nil }
        guard tagSections.indices.contains(section) else { return }
        tagSections[section].removeAll { $0 == uid }
    }

    var body: some View {
        ScrollViewReader { proxy in
            formBody
                .task {
                    guard SpoolPage.appliesOnce(requested: opensAtWeight, applied: didScrollToWeight) else { return }
                    didScrollToWeight = true
                    // After the push animation, or the scroll lands on the
                    // pre-layout geometry.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation { proxy.scrollTo(Self.weightSectionAnchor, anchor: .top) }
                }
                // Focusing the field puts the FIELD just above the keyboard,
                // which leaves the suggestion under it. Scroll the section to
                // the top instead, after the keyboard's own animation has
                // settled — racing it lands on the pre-keyboard geometry.
                .onChange(of: focusedNumericField) { _, field in
                    guard field == .weightInput else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation {
                            proxy.scrollTo(Self.weightSectionAnchor, anchor: .top)
                        }
                    }
                }
                // Attached out here rather than inside `formBody`, which keeps
                // its own modifier chain short. Every plain alert the form
                // shows is this one (2026-10-11).
                .alert(
                    Text(presentedAlert?.title ?? ""),
                    isPresented: Binding(
                        get: { presentedAlert != nil },
                        set: { if !$0 { dismissAlert() } }
                    ),
                    presenting: presentedAlert
                ) { alert in
                    alertActions(for: alert)
                } message: { alert in
                    Text(alert.message)
                }
                .onChange(of: nfcManager.lastTagClear) { _, result in
                    handleTagClear(result)
                }
        }
    }

    @ViewBuilder
    private var formBody: some View {
        let _ = fieldVisibilityRefreshToken
        let visibleFieldIDs = Self.visibleFieldIDs(for: store.capabilities)

        Form {
            ServerDownFormNote()
            if holdsResave {
                Section {
                    Text(SaveNote.unsureCreate)
                    Button("Save Again") { holdsResave = false }
                }
            }
            // After an Add save the shared fields are locked (`sharedFieldsLocked`);
            // the tag sections below stay live.
            filamentSection.disabled(sharedFieldsAreLocked)
                propertiesSection.disabled(sharedFieldsAreLocked)
                weightStatusSection.disabled(sharedFieldsAreLocked)

                if visibleFieldIDs.contains("location") {
                    locationSection.disabled(sharedFieldsAreLocked)
                }

                if (visibleFieldIDs.contains("status") && !store.spoolStatusOptions.isEmpty)
                    || visibleFieldIDs.contains("purchase_date") {
                    inventorySection(visibleFieldIDs: visibleFieldIDs).disabled(sharedFieldsAreLocked)
                }

                if visibleFieldIDs.contains("comment")
                    || visibleFieldIDs.contains("archived")
                    || visibleFieldIDs.contains("first_used")
                    || visibleFieldIDs.contains("last_used")
                    || visibleFieldIDs.contains("external_id") {
                    advancedSection(visibleFieldIDs: visibleFieldIDs).disabled(sharedFieldsAreLocked)
                }

                tagMoveSection
                if spoolToEdit == nil {
                    addTagSections
                } else if addsLinks || !listedTags(in: 0).isEmpty {
                    tagUIDSection
                }

                if let existing = spoolToEdit {
                    Section {
                        SpoolArchiveControls(
                            spool: existing, store: store, confirmBeforeDelete: confirmBeforeDelete,
                            run: runSpoolAction
                        )
                    }
                }
            }
            // The decimal pad has no return key, so this bar is the only way
            // out of it. `focusedNumericField` below is for scrolling, not for
            // dismissal — the bar answers to the keyboard itself.
            .keyboardDoneBar()
            .selectsTextOnFocus()
            .navigationTitle(Self.formTitle(isEditing: spoolToEdit != nil, count: count))
            // Inside the Spool page (`onFinish`) the page already hides the back
            // button; saying `false` here must not undo that.
            .navigationBarBackButtonHidden(onFinish != nil || run.holdsScreen(isScanning: nfcManager.isScanning))
            .interactiveDismissDisabled(run.holdsScreen(isScanning: nfcManager.isScanning))
            .onChange(of: nfcManager.isScanning) { _, isScanning in
                if addsLinks, !isScanning, isScanningForCardUID, let result = nfcManager.scanResult {
                    handleLinkScan(result)
                    isScanningForCardUID = false
                    nfcManager.scanResult = nil
                }
            }
            .onChange(of: addsLinks) { _, isEnabled in
                if !isEnabled {
                    isScanningForCardUID = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCustomizeFields = true
                    } label: {
                        Label("Customize Fields", systemImage: "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Self.cancelTitle(isSaved: isSaved)) { finish() }
                        .disabled(isSaving || run.holdsScreen(isScanning: nfcManager.isScanning))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaved ? "Saved" : "Save") {
                        Task { await saveSpools(closesOnSuccess: true) }
                    }
                    .disabled(filamentId == nil || isSaved || isSaving || holdsResave)
                    .needsServer()
                }
            }
            .sheet(isPresented: $showCustomizeFields, onDismiss: { fieldVisibilityRefreshToken += 1 }) {
                NavigationStack {
                    Form {
                        Section("Optional Fields") {
                            FieldVisibilityEditor(entity: .spool, capabilities: store.capabilities)
                        }
                    }
                    .navigationTitle("Customize Fields")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCustomizeFields = false }
                        }
                    }
                }
            }
            .onAppear(perform: loadFormOnce)
            // Keyed on the filament that needs a lookup, so choosing another
            // cancels the old one. It never blocks the form: until an answer
            // arrives the field holds the library's or the last value.
            .task(id: catalogLookupFilament?.id) { await lookUpMissingSpoolWeight() }
            // The three modes are three readings of one spool, so the number
            // is converted rather than reinterpreted. Anchored on the last
            // resolvable value: `.measured` deliberately shows nothing, and
            // leaving it empty must not erase what the spool holds.
            // Measured DERIVES the remaining weight, live. This is the whole
            // reason it left the picker: as a mode it replaced the number, and
            // the relationship between the reading and the weight was visible
            // only after a save. Now the reading lands in its own box and the
            // number above it moves as you type (owner, 2026-09-04).
            //
            // The remaining/used field stays editable — typing there after a
            // measurement wins, and does not feed back here, because a derived
            // gross figure is exactly the phantom reading `measuredInput` must
            // never hold.
            .onChange(of: measuredInput) { _, newValue in measuredInputChanged(newValue) }
            .onChange(of: usedThisPrintInput) { _, newValue in usedThisPrintChanged(newValue) }
            .onChange(of: weightInput) { _, newValue in weightInputChanged(newValue) }
            // A core weight entered AFTER the reading changes what that same
            // reading means, so the derived weight is recomputed rather than
            // left stating the old core.
            .onChange(of: spoolWeight) { _, newValue in spoolWeightChanged(newValue) }
            // A filament list that arrives after the form opened is a filament change too.
            .onChange(of: emptyWeightSource) { _, _ in emptyWeightSourceChanged() }
            .onChange(of: filamentNetWeight) { _, _ in filamentNetWeightChanged() }
            .onChange(of: weightMode) { oldMode, newMode in weightModeChanged(from: oldMode, to: newMode) }
            .onChange(of: nfcManager.lastWriteSucceeded) { _, succeeded in tagWriteFinished(succeeded) }
    }

    /// Loads the form once: the spool's values when editing, the last-used
    /// values when creating.
    private func loadFormOnce() {
        if !hasInitialized {
            hasInitialized = true
            Task {
                await store.fetchFilaments()
                await store.fetchLocations()
            }
            // FilaMan's Status picker needs the status list, which a
            // form opened before any spool fetch (from the scan hub)
            // does not have yet. Resolved into BOTH the selection and
            // its loaded snapshot, so arriving late is not an edit.
            Task {
                await store.loadSpoolStatusOptionsIfNeeded()
                if let spool = spoolToEdit, statusKey.isEmpty, loadedStatusKey.isEmpty {
                    statusKey = resolvedStatusKey(for: spool)
                    loadedStatusKey = statusKey
                }
            }

            if let spool = spoolToEdit {
                filamentId = spool.filament.id
                if let p = spool.price { price = String(p) }
                if let iw = spool.initialWeight { initialWeight = String(iw) }
                if let sw = spool.spoolWeight { spoolWeight = String(sw) }
                loadedInitialWeight = initialWeight
                loadedSpoolWeight = spoolWeight

                if let rw = spool.remainingWeight {
                    weightMode = .remaining
                    weightInput = Self.weightInputText(
                        for: .remaining, netRemaining: rw, initialWeight: initialWeight
                    )
                    lastKnownNetRemaining = rw
                    // The NET figure, matching what the save computes —
                    // `weightInput` is mode-dependent and would compare
                    // the wrong number after a mode switch.
                    loadedRemainingWeight = String(rw)
                }

                location = spool.location ?? ""
                comment = spool.comment ?? ""
                archived = spool.archived ?? false
                firstUsedISO8601 = spool.firstUsed.map { Self.dateFormatter.string(from: $0) } ?? ""
                lastUsedISO8601 = spool.lastUsed.map { Self.dateFormatter.string(from: $0) } ?? ""
                loadedComment = comment
                loadedFirstUsed = firstUsedISO8601
                loadedLastUsed = lastUsedISO8601

                // FilaMan-only (Task 7). The key, not the id — matched
                // against whatever `store.spoolStatusOptions` has
                // already fetched; `""` (no match yet, or no status)
                // renders no picker and compares equal to itself, so
                // an unresolved lookup never masquerades as a change.
                statusKey = resolvedStatusKey(for: spool)
                externalId = spool.externalId ?? ""
                purchaseDate = spool.purchaseDate
                loadedStatusKey = statusKey
                loadedExternalId = externalId
                loadedPurchaseDate = purchaseDate.map { CalendarDateCodec.string(from: $0) } ?? ""

                tagSections = [spool.mappedCardUIDs]
            } else {
                if let initialFilamentId {
                    filamentId = initialFilamentId
                }
                if let initialLocation { location = initialLocation }
                if let tagMoveOffer {
                    movingTagUIDs = tagMoveOffer.defaultSelection
                    tagSections = [tagMoveOffer.uids]
                } else if !initialCardUIDs.isEmpty, addsLinks {
                    tagSections = [initialCardUIDs]
                }
                if !lastSpoolPrice.isEmpty { price = lastSpoolPrice }
                if filamentId == nil, lastSpoolFilamentId != -1 { filamentId = lastSpoolFilamentId }
                // After the filament is settled: an untagged weight follows it.
                initialWeight = Self.newSpoolInitialWeight(
                    tagWeight: tagWeights?.initial, filamentWeight: filamentNetWeight
                )
                autoFilledInitialWeight = FilamentTagData.statedMeasurement(tagWeights?.initial) == nil
                    ? initialWeight : nil
                // A printer's recorded consumption: the spool is not full.
                if let remaining = tagWeights?.remaining {
                    weightMode = .remaining
                    weightInput = Self.weightInputText(
                        for: .remaining, netRemaining: remaining, initialWeight: initialWeight
                    )
                    lastKnownNetRemaining = remaining
                }
                // After the filament is settled: the weight follows it.
                spoolWeight = Self.newSpoolEmptyWeight(
                    filamentWeight: newSpoolFilamentWeight,
                    entryWeight: emptySpools.prefillEntry(forManufacturer: filamentManufacturer)?.weight,
                    lastUsed: lastSpoolEmptyWeight
                )
                autoFilledSpoolWeight = spoolWeight
            }
        }
    }

    private func measuredInputChanged(_ newValue: String) {
        guard let net = Self.netFromMeasured(
            measured: newValue, spoolWeight: spoolWeight
        ) else { return }
        // A reading takes the figure over outright. Clearing Used here, not
        // only through the takeover check, means a derived text that happens
        // to equal Used's own text cannot leave Used attached.
        usedThisPrintInput = ""
        weightInputSetByUsed = nil
        lastKnownNetRemaining = net
        weightInput = Self.weightInputText(
            for: weightMode, netRemaining: net, initialWeight: initialWeight
        )
    }

    /// Writes the Used-this-print figure into the mode field. Clearing Used
    /// restores the loaded figure, but only when Used was what changed the
    /// field: a blank Used must not overwrite a Measured reading.
    private func usedThisPrintChanged(_ newValue: String) {
        guard !newValue.isEmpty || weightInputSetByUsed != nil else { return }
        let mode = Self.modeForUsedThisPrint(
            used: newValue, base: loadedRemainingValue, mode: weightMode, initialWeight: initialWeight
        )
        guard let text = Self.weightInputAfterUsedThisPrint(
            used: newValue,
            base: loadedRemainingValue,
            mode: mode,
            initialWeight: initialWeight
        ) else { return }
        if let base = loadedRemainingValue {
            lastKnownNetRemaining = base - (Self.parseWeight(newValue) ?? 0)
        }
        if mode != weightMode { weightMode = mode }
        weightInput = text
        weightInputSetByUsed = text
    }

    /// Any change to the mode field that Used did not write is the user typing
    /// a number of their own, so the Used figure no longer describes it.
    private func weightInputChanged(_ newValue: String) {
        guard Self.weightInputTakesOverUsed(newValue, setByUsed: weightInputSetByUsed) else { return }
        usedThisPrintInput = ""
        weightInputSetByUsed = nil
    }

    private func filamentNetWeightChanged() {
        guard let text = Self.refilledInitialWeight(
            current: initialWeight,
            autoFilled: autoFilledInitialWeight,
            isNewSpool: spoolToEdit == nil,
            filamentWeight: filamentNetWeight
        ) else { return }
        initialWeight = text
        autoFilledInitialWeight = text
    }

    private func emptyWeightSourceChanged() {
        guard let text = Self.refilledEmptyWeight(
            current: spoolWeight,
            autoFilled: autoFilledSpoolWeight,
            isNewSpool: spoolToEdit == nil,
            filamentWeight: newSpoolFilamentWeight,
            entryWeight: emptySpools.prefillEntry(forManufacturer: filamentManufacturer)?.weight,
            lastUsed: lastSpoolEmptyWeight
        ) else { return }
        spoolWeight = text
        autoFilledSpoolWeight = text
    }

    private func lookUpMissingSpoolWeight() async {
        // An answer belongs to its filament only: drop it when another is chosen.
        if lookedUp?.filamentId != catalogLookupFilament?.id { lookedUp = nil }
        guard let filament = catalogLookupFilament else { return }
        guard let grams = await lookUpCatalogSpoolWeight(for: filament, store: store),
              !Task.isCancelled
        else { return }
        lookedUp = (filament.id, grams)
    }

    /// What `writeBackCatalogSpoolWeight` did, so a caller reads a failure from
    /// the case, not from the polarity of a `Bool`.
    private enum CatalogWeightWriteBack {
        case notNeeded, written, failed
    }

    /// Saves the tag's or the catalogue's weight to the filament after the
    /// spool saved, but only a weight the user kept, and only to a filament
    /// that still has none (the saved filament's, not the current selection).
    /// A failure leaves the spool saved and says so.
    private func writeBackCatalogSpoolWeight(savedFilamentId: Int, savedSpoolWeight: Double?) async -> CatalogWeightWriteBack {
        let savedFilamentWeight = store.filaments.first { $0.id == savedFilamentId }?.spoolWeight
        let offer = Self.writeBackOffer(tagOffer: tagOffer, lookedUp: lookedUp, savedFilamentId: savedFilamentId)
        guard let grams = CatalogSpoolWeight.weightToSave(
            lookedUp: offer, savedFilamentId: savedFilamentId, savedSpoolWeight: savedSpoolWeight
        ), (savedFilamentWeight ?? 0) <= 0 else { return .notNeeded }
        guard await store.updateFilament(id: savedFilamentId, draft: FilamentDraft(spoolWeight: .set(grams))) else {
            store.postSaveNotice(CatalogSpoolWeight.writeBackFailedNote, record: recordLabel)
            return .failed
        }
        return .written
    }

    private func spoolWeightChanged(_ newValue: String) {
        guard !measuredInput.isEmpty,
              let net = Self.netFromMeasured(
                  measured: measuredInput, spoolWeight: newValue
              ) else { return }
        lastKnownNetRemaining = net
        weightInput = Self.weightInputText(
            for: weightMode, netRemaining: net, initialWeight: initialWeight
        )
    }

    private func weightModeChanged(from oldMode: WeightMode, to newMode: WeightMode) {
        // While Used is attached, `lastKnownNetRemaining` is already the net
        // figure, and the field may hold text the old mode cannot read back
        // (Used can switch the mode to Remaining for that very reason).
        let known = weightInputSetByUsed != nil
            ? lastKnownNetRemaining
            : Self.netRemaining(
                input: weightInput,
                mode: oldMode,
                initialWeight: initialWeight,
                spoolWeight: spoolWeight
            ) ?? lastKnownNetRemaining
        lastKnownNetRemaining = known
        weightInput = Self.weightInputText(
            for: newMode, netRemaining: known, initialWeight: initialWeight
        )
        // Switching the mode is not the user taking the figure over: the same
        // Used-this-print figure, stated in the other mode, stays attached.
        if weightInputSetByUsed != nil {
            if Self.usedSurvivesModeChange(convertedText: weightInput) {
                weightInputSetByUsed = weightInput
            } else {
                // The new mode cannot state the figure. Clear Used, visibly,
                // rather than keep a number Save would drop; the mode stays.
                usedThisPrintInput = ""
                weightInputSetByUsed = nil
            }
        }
    }

    private func tagWriteFinished(_ succeeded: Bool) {
        if succeeded, var data = nfcManager.tagDataToWrite {
            if data.name == nil {
                data.name = writingSpool?.filament.name
            }
            recentTagManager.addTag(data, format: nfcManager.writeFormatToUse)
            supportPrompts.record(.tagWriteSucceeded)
            linkWrittenTag()
        }
    }

    private func writeTag(for spool: Spool, replacing: Bool = false, reader: TagReader? = nil) {
        replacesOnWriteLink = replacing
        writingSpool = spool
        let write = SpoolTagWrite.spoolWrite(for: spool, store: store)
        run = reader.map { TagReaderRun(reader: $0, isWriting: true) }
            ?? .start(tagReader, purpose: .write(format: write.format), printer: printer, store: store)
        nfcManager.writeTag(data: write.data, format: write.format, reader: run.reader)
    }

    /// The same spool and format, written to its other tag with the iPhone.
    private func writeOtherSide(section: Int) {
        guard section < savedSpools.count else { return }
        let spool = store.spools.first { $0.id == savedSpools[section].id } ?? savedSpools[section]
        writeTag(for: spool, reader: .iPhone)
    }

    /// Tag Links: the tag just written for this spool is linked to it, as the
    /// write screen does — otherwise it would carry neither an ID nor a link
    /// and identify nothing. A link caveat reaches the user as a notice; a
    /// link that landed shows in the spool's own tag section.
    ///
    /// Queued behind the tag writes already waiting: the assign reads the store,
    /// and a list write still ahead of it would not show there yet.
    private func linkWrittenTag() {
        guard store.tagIdentity.writesLinks,
              let uid = nfcManager.lastWrittenTagUID,
              let spool = writingSpool
        else { return }
        // Counted here, not when the task first runs, so the buttons are disabled
        // from this moment.
        pendingTagWrites += 1
        let earlier = linkedTagsSave
        let replacing = replacesOnWriteLink
        replacesOnWriteLink = false
        linkedTagsSave = Task {
            defer { pendingTagWrites -= 1 }
            await earlier?.value
            let outcome = await TagLinkService.assign(uid, to: spool, in: store, replacing: replacing)
            if let note = outcome.followUpNote {
                store.postSaveNotice(note, record: Self.savedSpoolLabel(id: spool.id, filamentName: spool.filament.name))
            }
            let linked = SpoolMappingService.normalizeUID(uid)
            if outcome.didWrite, let section = savedSpools.firstIndex(where: { $0.id == spool.id }) {
                addTag(linked, toSection: section)
                syncTagSections(except: section)
            }
        }
    }

    /// A tag moved off a sibling by an assign or a move must leave that
    /// sibling's section too, or it would be listed under two spools. The store
    /// decides: a tag the sibling still holds (a failed detach) stays listed.
    /// Only removes. Rewriting a sibling's list from the store would also undo
    /// an add or a remove of its own that is still queued behind this write.
    private func syncTagSections(except section: Int) {
        let changed = listedTags(in: section)
        for (index, saved) in savedSpools.enumerated() where index != section && tagSections.indices.contains(index) {
            guard let current = store.spools.first(where: { $0.id == saved.id }) else { continue }
            tagSections[index] = Self.siblingTagsAfterMove(
                sibling: tagSections[index], movedIntoChanged: changed, heldBySibling: current.mappedCardUIDs
            )
        }
    }

    /// A sibling section's list after the changed section took tags. Only a tag
    /// that sits in the changed section and that the store no longer gives the
    /// sibling leaves; every other entry stays, including one the store does not
    /// list yet (an add still queued) and one a failed detach left with it.
    nonisolated static func siblingTagsAfterMove(
        sibling: [String], movedIntoChanged: [String], heldBySibling: [String]
    ) -> [String] {
        sibling.filter { !movedIntoChanged.contains($0) || heldBySibling.contains($0) }
    }

    /// The Add form stays open after a section's button saved it, with Save
    /// spent, so a tag-list change there is saved at once, by Edit Spool's own
    /// tag step. Queued behind any tag write already waiting, so changes land in
    /// order, and counted in `pendingTagWrites` until it ends; a failed write puts
    /// the list back to what the spool holds.
    private func saveLinkedTagsNow(section: Int) {
        guard spoolToEdit == nil, isSaved, section < savedSpools.count else { return }
        let saved = savedSpools[section]
        let record = sectionRecordLabel(section)
        pendingTagWrites += 1
        let earlier = linkedTagsSave
        linkedTagsSave = Task {
            defer { pendingTagWrites -= 1 }
            await earlier?.value
            let spool = store.spools.first { $0.id == saved.id } ?? saved
            let moves = await releasePendingMoves(section: section)
            let mapping = await persistCardUIDs(
                spoolId: spool.id,
                previous: spool.mappedCardUIDs,
                writable: spool.writableCardUIDs,
                undetachable: spool.undetachableCardUIDs,
                section: section
            )
            if !mapping.didWrite {
                tagSections[section] = (store.spools.first { $0.id == saved.id } ?? spool).mappedCardUIDs
            }
            syncTagSections(except: section)
            let movesNoted = reportMoves(moves, linked: mapping.didWrite, record: record)
            play(movesNoted ? .warning : feedback(after: mapping, primary: .saved, record: record))
        }
    }

    /// Writes an offered difference into the field it belongs to. Both
    /// branches leave the spool describing the same physical object the scale
    /// just weighed — the core weight makes `Calculated Remaining` land on the
    /// initial weight, and the used weight restates the same reading as
    /// consumption — so applying one is a relabelling, never a new claim.
    private func apply(_ suggestion: MeasuredWeightSuggestion) {
        switch suggestion {
        case .setEmptySpoolWeight(let grams):
            spoolWeight = Self.formatWeight(grams)
            autoFilledSpoolWeight = nil
        case .setUsedFilament:
            // Only the mode changes. `weightInput` already holds the remaining
            // weight the measurement derived, and `onChange(of: weightMode)`
            // converts it; its answer IS the offered number by construction:
            // initial - (measured - spool) == (initial + spool) - measured.
            // Assigning `weightInput` here as well would convert it twice.
            //
            // FilaMan has no Used segment to land on (F31 review, fix round
            // 1): the same conversion is offered as Remaining instead, rather
            // than setting a mode the picker no longer shows.
            weightMode = store.capabilities.fieldSupport.supports("used_weight", in: .spool)
                ? .used : .remaining
        }
    }

    /// Saves the spool. Add creates `count` identical spools as one batch, and
    /// only the first carries the tags the form holds (`SpoolBatch.drafts`); Edit
    /// saves its one spool as before and answers `.complete` or `.none`. Edit
    /// always dismisses when it saves. A complete Add save dismisses only when
    /// `closesOnSuccess`; a partial one (spools exist, not all) stays open, with
    /// the alert that says where it stopped.
    @discardableResult
    private func saveSpools(closesOnSuccess: Bool) async -> SpoolBatchCompleteness {
        if isSaving {
            return .none
        }
        isSaving = true
        defer { isSaving = false }

        func parseDouble(_ str: String) -> Double? {
            let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            return Double(cleaned)
        }

        let p = parseDouble(price)
        let initW = parseDouble(initialWeight)
        let spoolW = parseDouble(spoolWeight)
        let wInput = parseDouble(weightInput)

        if let p, p < 0 {
            formAlert = .invalidInput("Price cannot be negative.")
            return .none
        }
        if let initW, initW < 0 {
            formAlert = .invalidInput("Initial weight cannot be negative.")
            return .none
        }
        if let spoolW, spoolW < 0 {
            formAlert = .invalidInput("Empty spool weight cannot be negative.")
            return .none
        }
        if let wInput, wInput < 0 {
            formAlert = .invalidInput("\(weightMode.rawValue) weight cannot be negative.")
            return .none
        }
        if Self.refusesNegativeAdjustment(adjustmentPreview) {
            formAlert = .invalidInput(SpoolWeightAdjustment.negativeNote)
            return .none
        }
        let measuredW = Self.parseWeight(measuredInput)
        if let measuredW {
            if measuredW < 0 {
                formAlert = .invalidInput("Measured weight cannot be negative.")
                return .none
            }
            if let sW = spoolW, measuredW - sW < 0 {
                formAlert = .invalidInput("Measured weight cannot be lower than empty spool weight.")
                return .none
            }
        }

        var remW: Double? = nil
        var usedW: Double? = nil

        if let val = wInput {
            switch weightMode {
            case .remaining:
                remW = val
            case .used:
                usedW = val
            }
        }

        var draft = Self.spoolPayload(
            filamentId: filamentId,
            price: price,
            initialWeight: initialWeight,
            spoolWeight: spoolWeight,
            remainingWeight: remW.map { String($0) } ?? "",
            usedWeight: usedW.map { String($0) } ?? "",
            location: location,
            comment: comment,
            archived: archived,
            firstUsedISO8601: firstUsedISO8601,
            lastUsedISO8601: lastUsedISO8601,
            statusKey: statusKey,
            externalId: externalId,
            purchaseDateISO: purchaseDate.map { CalendarDateCodec.string(from: $0) } ?? "",
            loadedInitialWeight: loadedInitialWeight,
            loadedSpoolWeight: loadedSpoolWeight,
            loadedRemainingWeight: loadedRemainingWeight,
            loadedComment: loadedComment,
            loadedFirstUsed: loadedFirstUsed,
            loadedLastUsed: loadedLastUsed,
            loadedStatusKey: loadedStatusKey,
            loadedExternalId: loadedExternalId,
            loadedPurchaseDate: loadedPurchaseDate
        )
        // The GROSS reading travels alongside the net one it implies. Only
        // FilaMan reads it, to file the save as a `measurement` rather than
        // a `manual_adjust`; every other backend uses `remainingWeight`,
        // which is why that is still set in this mode.
        if let measuredW {
            draft.measuredWeight = measuredW
        }

        if let spool = spoolToEdit {
            var didSave = false
            let written = await serverLink.outcome {
                didSave = await store.updateSpool(id: spool.id, draft: draft)
                return didSave
            }
            let outcome = saveOutcome(didSave: didSave)

            if outcome.didWrite {
                let moves = await releasePendingMoves(section: 0)
                let mapping = await persistCardUIDs(
                    spoolId: spool.id,
                    previous: spool.mappedCardUIDs,
                    writable: spool.writableCardUIDs,
                    undetachable: spool.undetachableCardUIDs,
                    section: 0
                )
                let movesNoted = reportMoves(moves, linked: mapping.didWrite, record: recordLabel)

                lastSpoolPrice = price
                lastSpoolEmptyWeight = spoolWeight
                if let fId = filamentId {
                    lastSpoolFilamentId = fId
                }

                let mappingFeedback = feedback(after: mapping, primary: outcome, record: recordLabel)
                play(movesNoted ? .warning : mappingFeedback)
                isSaved = true
                finish()
                return .complete
            } else {
                formAlert = outcome.failure.map { .saveFailed(SaveNote.failure(written, otherwise: $0)) }
                return .none
            }
        } else if let fId = filamentId {
            var addDraft = draft
            addDraft.filamentId = fId
            // The list travels typed; each backend's payload builder applies
            // its OWN wire encoding. Encoding it here wrote Spoolman's
            // wrapped form into FilaMan's `custom_fields`, which its compat
            // layer wrapped again on read — invisible inside SpoolKid,
            // broken for every SpoolLink/Snapmaker U1 client (F38).
            // Only Spool 1 can hold tags before the save (D4).
            let firstSpoolUIDs = listedTags(in: 0)
            let carriesCardUIDs = Self.createCarriesCardUIDs(
                linkingActive: addsLinks,
                available: store.availableTagStores,
                hasUIDs: !firstSpoolUIDs.isEmpty
            )
            if carriesCardUIDs {
                addDraft.cardUIDs = firstSpoolUIDs
            }
            if case .setNil = addDraft.location {
                addDraft.location = .ignore
            }

            var batch: SpoolBatchResult?
            let written = await serverLink.outcome {
                batch = await store.addSpools(drafts: SpoolBatch.drafts(from: addDraft, count: count))
                return batch?.created.isEmpty == false
            }
            guard let result = batch, let spool = result.created.first else {
                if let quota = store.lastQuotaError {
                    formAlert = .limitReached(quota.errorDescription ?? "")
                } else {
                    formAlert = .saveFailed(SaveNote.failure(
                        written, otherwise: batch?.outcome.failure ?? "The spool could not be saved."
                    ))
                    holdsResave = SaveNote.holdsResave(after: written, isCreate: true)
                }
                return .none
            }
            // A complete batch's caveat is a banner, as a single save's always was.
            if let caveat = result.bannerCaveat {
                store.postSaveNotice(caveat, record: recordLabel)
            }

            // card_uids already in the POST: pass previous: the list so
            // persistCardUIDs sees no diff and skips the redundant PATCH.
            // Otherwise it links them now (a native-tag server).
            let previousUIDs: [String] = carriesCardUIDs ? firstSpoolUIDs : []
            // A spool that did not exist a moment ago has no
            // `rfid_uid`, so nothing here is undetachable and every
            // UID is writable.
            let mapping = await persistCardUIDs(
                spoolId: spool.id, previous: previousUIDs, writable: previousUIDs, undetachable: [], section: 0
            )
            // A link that did not land must not stay listed as one that did: the
            // section shows what the spool holds, as after any later list write.
            if !mapping.didWrite {
                tagSections[0] = (store.spools.first { $0.id == spool.id } ?? spool).mappedCardUIDs
            }
            // FilaMan Tags as the only store: the create linked the first tag
            // alone. Name the rest and show what the spool holds.
            if let note = TagStoreText.filamanCreateUnlinkedNote(
                listed: firstSpoolUIDs, targets: store.tagIdentity.linkTargets
            ) {
                store.postSaveNotice(note, record: recordLabel)
                tagSections[0] = (store.spools.first { $0.id == spool.id } ?? spool).mappedCardUIDs
            }
            let writeBack = await writeBackCatalogSpoolWeight(
                savedFilamentId: fId, savedSpoolWeight: spoolW
            )

            lastSpoolPrice = price
            lastSpoolEmptyWeight = spoolWeight
            lastSpoolFilamentId = fId

            let mappingFeedback = feedback(after: mapping, primary: result.outcome, record: recordLabel)
            play(writeBack == .failed ? .warning : mappingFeedback)
            isSaved = true
            savedSpools = result.created
            // Every saved spool has a section; only Spool 1 may hold tags so far.
            while tagSections.count < result.created.count { tagSections.append([]) }
            onSaveSpool?(spool, tagMoveOffer?.movedUIDs(selection: movingTagUIDs) ?? [])

            if let message = result.stopAlertMessage {
                formAlert = .batchIncomplete(message)
            } else if closesOnSuccess {
                finish()
            }
            return result.completeness
        }
        return .none
    }

    /// Classifies a write into saved / saved-with-a-caveat / not-saved and
    /// hands any caveat to the root banner (plan defect I1). A `true` with a
    /// message means the spool was written but something it carried was not —
    /// its location, or a remaining weight the backend could not adjust.
    ///
    /// Called IMMEDIATELY after the write, before `persistCardUIDs`: that is a
    /// second write, and its own result would overwrite `store.errorMessage`
    /// and hide this one.
    private func saveOutcome(didSave: Bool) -> SaveOutcome {
        let outcome = SaveOutcome.classify(
            didSave: didSave,
            message: store.errorMessage,
            failureFallback: "The spool could not be saved."
        )
        if let caveat = outcome.caveat { store.postSaveNotice(caveat, record: recordLabel) }
        return outcome
    }

    /// What the root banner calls this spool. A caveat the user cannot trace
    /// back to a row is barely a caveat — the owner's device pass reported
    /// exactly that (finding 4.2.1).
    ///
    /// Reads the filament from the CURRENT selection rather than the loaded
    /// spool, because that is the one the user is looking at: a save that
    /// changed the filament should name the new one.
    private var recordLabel: String {
        let selected = store.filaments.first { $0.id == filamentId }?.name
        if let spool = spoolToEdit {
            return Self.savedSpoolLabel(id: spool.id, filamentName: selected ?? spool.filament.name)
        }
        return selected.map { "New spool · \($0)" } ?? "New spool"
    }

    /// What a banner calls a spool that exists: "Spool #12 · PLA Matte".
    nonisolated static func savedSpoolLabel(id: Int, filamentName: String?) -> String {
        filamentName.map { "Spool #\(id) · \($0)" } ?? "Spool #\(id)"
    }

    /// What a banner about one section's tags calls its spool. After an Add save
    /// the batch's spools share a filament, so only the number tells them apart;
    /// before it, and on Edit, the form's own label.
    private func sectionRecordLabel(_ section: Int) -> String {
        guard spoolToEdit == nil, section < savedSpools.count else { return recordLabel }
        return Self.savedSpoolLabel(id: savedSpools[section].id, filamentName: savedSpools[section].filament.name)
    }

    /// Completes an "Unlink and Continue": the tag is blank now, so the shelf
    /// label can be dropped and the UID handed to this spool.
    ///
    /// Nothing is changed on any other outcome. A refused or failed clear
    /// leaves the tag labelling its shelf and the spool without the UID, which
    /// is the state the user started in and can simply retry. So does a clear
    /// whose release the registry could not save: the blank tag is still the
    /// shelf's, and a second scan offers the unlink again.
    private func handleTagClear(_ result: NFCManager.TagClearResult?) {
        guard let result, let uid = pendingUnlinkUID else { return }
        pendingUnlinkUID = nil

        switch result {
        case .cleared:
            // A UID the shelf still holds is not this spool's to take: one
            // tag, one owner.
            guard store.locationRegistry?.detachTag(uid: uid) ?? true else {
                store.postSaveNotice(
                    "The tag was erased, but this iPhone could not release it from its location, so it was not added. Scan it again to retry."
                        + (store.locationRegistry?.errorMessage.map { " \($0)" } ?? ""),
                    record: sectionRecordLabel(activeTagSection)
                )
                return
            }
            addTag(uid, toSection: activeTagSection)
            saveLinkedTagsNow(section: activeTagSection)
        case .wrongTag:
            store.postSaveNotice(
                "That was a different tag, so nothing was changed.", record: sectionRecordLabel(activeTagSection)
            )
        case .failed(let reason):
            store.postSaveNotice(reason, record: sectionRecordLabel(activeTagSection))
        }
    }

    /// "Scan tag to link" (Edit) and "Link Tag" (Add, per section): `SpoolFormTagClaim`
    /// decides; this carries it out for `activeTagSection`.
    /// Replace Tag from a link scan: the section's list becomes just the new
    /// tag. Saved at once after an Add save; an unsaved section only lists it.
    private func replaceLinkedTag(with request: TagReplaceRequest, section: Int) {
        for uid in listedTags(in: section) { removeTag(uid, fromSection: section) }
        addTag(request.uid, toSection: section)
        saveLinkedTagsNow(section: section)
    }

    private func handleLinkScan(_ result: ScanResult) {
        let section = activeTagSection
        let claim = SpoolFormTagClaim.decide(
            uid: result.cardUID,
            payloadShelfName: result.locationTag.map { payload in
                ScanResultHubView.resolvedLocationName(
                    for: payload, scannedUID: result.cardUID, registry: store.locationRegistry
                )
            },
            owner: store.owner(ofTagUID: SpoolMappingService.normalizeUID(result.cardUID ?? "")),
            // After an Add save the section's own spool is the one whose tags this
            // edits, so a tag a sibling holds is offered as a move, never doubled.
            editingSpoolID: spoolToEdit?.id ?? (section < savedSpools.count ? savedSpools[section].id : nil),
            offeredUIDs: openTagMoveOffer?.uids ?? [],
            listedUIDs: listedTags(in: section)
        )
        switch claim {
        case .ignore:
            break
        case .take(let uid):
            let editedID = spoolToEdit?.id ?? (section < savedSpools.count ? savedSpools[section].id : nil)
            let current = editedID.flatMap { id in store.spools.first { $0.id == id } }
            // Before the tag joins the list: FilaMan holds one, so the list
            // would end [old, new] and the new one would be stored nowhere.
            // An unsaved Add section asks about the tag it already lists.
            if let request = TagReplaceRequest.scanning(
                uid: uid, into: current, listed: listedTags(in: section), targets: store.tagIdentity.linkTargets
            ) {
                linkReplaceRequest = request
                return
            }
            addTag(uid, toSection: section)
            saveLinkedTagsNow(section: section)
        case .takeOffered(let uid):
            addTag(uid, toSection: section)
            movingTagUIDs.insert(uid)
        case .refuseShelf(let uid, let name):
            formAlert = .shelfTag(uid: uid, name: name)
            // A refusal must not feel like the success it is not. The write
            // path gets its jolt free from the NFC session's error
            // invalidation; a read that succeeded and was then rejected has to
            // fire its own.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .offerMove(let uid, let holder):
            formAlert = .moveTag(uid: uid, holder: holder)
        }
    }

    /// The alert on screen: the form's own first, then an NFC session's.
    private var presentedAlert: SpoolFormAlert? {
        formAlert ?? (nfcManager.alertMessage.isEmpty ? nil : .nfcError(nfcManager.alertMessage))
    }

    /// Clears the alert that was showing, leaving any other to show next.
    private func dismissAlert() {
        if formAlert != nil {
            formAlert = nil
        } else {
            nfcManager.alertMessage = ""
        }
    }

    @ViewBuilder
    private func alertActions(for alert: SpoolFormAlert) -> some View {
        switch alert {
        case .shelfTag(let uid, _):
            // The mirror of the location screen's own offer, and for the same
            // reason: refusing without a way through leaves a user holding a
            // tag they want to reuse and no way to say so.
            Button("Unlink and Continue", role: .destructive) {
                // Clear FIRST, map only once it lands. Detaching the registry
                // entry alone leaves the tag still announcing itself as that
                // shelf on the next scan — the read path recognises the
                // payload before anything else — so the spool would claim a
                // tag that still reads as a location. Erasing first means a
                // cancelled or failed clear changes nothing at all.
                pendingUnlinkUID = uid
                run = .start(tagReader, purpose: .write(format: nil), printer: printer, store: store)
                nfcManager.clearTag(expectedUID: uid, reader: run.reader)
            }
            Button("Cancel", role: .cancel) {}
        case .moveTag(let uid, let holder):
            Button("Move") {
                let section = activeTagSection
                addTag(uid, toSection: section)
                pendingMoves[uid] = PendingMove(holder: holder, section: section)
                saveLinkedTagsNow(section: section)
            }
            Button("Cancel", role: .cancel) {}
        default:
            Button("OK", role: .cancel) {}
        }
    }

    /// What releasing the agreed moves did, for the save's report.
    private struct MoveRelease {
        var released: [(uid: String, holder: TagOwner)] = []
        var notes: [String] = []
    }

    /// Runs on Save, before the form's link write: releases each move `section`
    /// agreed whose tag is still listed there (`movesToRelease`). A tag that
    /// stays with its holder leaves the section, so the write does not give it
    /// two owners.
    private func releasePendingMoves(section: Int) async -> MoveRelease {
        let moves = Self.movesToRelease(section: section, listed: listedTags(in: section), agreed: pendingMoves)
        guard !moves.isEmpty else { return MoveRelease() }
        let result = await TagHolderMove.releaseForSave(moves, in: store)
        // Spent, and only these: another section's agreed move may be queued behind this one.
        for move in moves { pendingMoves[move.uid] = nil }
        tagSections[section].removeAll { result.kept.contains($0) }
        return MoveRelease(released: moves.filter { !result.kept.contains($0.uid) }, notes: result.notes)
    }

    /// Posts what the moves could not do — a tag left with its holder, or one
    /// released but not linked because the link write failed. True when
    /// anything was posted.
    private func reportMoves(_ moves: MoveRelease, linked: Bool, record: String) -> Bool {
        var notes = moves.notes
        if !linked {
            notes += moves.released.map {
                "\($0.uid) was unlinked from \(TagHolderMove.holderPhrase($0.holder)), but could not be linked to this spool."
            }
        }
        guard let note = SaveOutcome.combinedNote(notes) else { return false }
        store.postSaveNotice(note, record: record)
        return true
    }

    /// A caveat gets a warning, never the success haptic it used to borrow.
    private func play(_ feedback: SaveFeedback?) {
        switch feedback {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case nil: break
        }
    }

    /// Writes the edited `card_uids` list to the spool, but only when the list
    /// actually changed (so a brand-new spool with no tags writes nothing).
    ///
    /// Returns what the write accomplished instead of discarding it (plan
    /// defect I3). This is a SECOND write, after the spool itself already
    /// landed, and on FilaMan it is a fail-closed stub that always returns
    /// `false` — while the SpoolLink switch is `@AppStorage` and not gated on
    /// backend, so it carries over from a Spoolman setup. Mapping a tag on
    /// FilaMan therefore saved the spool, fired the success haptic, dismissed
    /// the form, and wrote no mapping at all. Nothing to write is `.saved`:
    /// the list the form shows is what the server already has — unless a
    /// deleted chip was an `rfid_uid` SpoolKid cannot remove, which is a
    /// caveat with no write behind it (`cardUIDsToWrite`).
    ///
    /// Runs in every mode: outside Tag Links the list can only shrink, and
    /// removals must land.
    private func persistCardUIDs(
        spoolId: Int, previous: [String], writable: [String], undetachable: [String], section: Int
    ) async -> SaveOutcome {
        let shown = listedTags(in: section)
        let note = Self.undetachableRemovalNote(
            removed: previous.filter { !shown.contains($0) },
            undetachable: undetachable
        )
        guard let uids = Self.cardUIDsToWrite(shown: shown, previous: previous, writable: writable) else {
            return note.map { .savedWithCaveat($0) } ?? .saved
        }
        let didSave = await store.setCardUIDs(spoolId: spoolId, uids: uids)
        let outcome = SaveOutcome.classify(
            didSave: didSave,
            message: store.errorMessage,
            failureFallback: "The spool was saved, but its tag mapping was not."
        )
        guard outcome.didWrite, let note else { return outcome }
        return .savedWithCaveat([outcome.caveat, note].compactMap { $0 }.joined(separator: " "))
    }

    /// Archive, unarchive and delete dismiss only when the write happened; a
    /// refused one keeps the form open and says why.
    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private func runSpoolAction(failureTitle: String, fallback: String, _ write: @escaping () async -> Bool) {
        Task {
            let didWrite = await write()
            let outcome = SaveOutcome.classify(didSave: didWrite, message: store.errorMessage, failureFallback: fallback)
            if outcome.didWrite {
                finish()
            } else {
                formAlert = outcome.failure.map { .actionFailed(title: failureTitle, message: $0) }
            }
        }
    }

    /// The caveat a `card_uids` write earns for a chip the user deleted that
    /// this app cannot actually detach.
    ///
    /// The list is seeded from `mappedCardUIDs`, so it shows FilaMan's
    /// `rfid_uid`, which `setCardUIDs` never writes. Deleting that chip wrote
    /// a `card_uids` value without it, returned 200, fired the success haptic,
    /// and the chip came back on the next refresh (I1).
    ///
    /// This reports; it does not write. Making such a UID removable needs a
    /// policy decision on `rfid_uid` and is filed as debt.
    static func undetachableRemovalNote(removed: [String], undetachable: [String]) -> String? {
        let stuck = removed.filter { undetachable.contains($0) }
        guard !stuck.isEmpty else { return nil }
        return "The spool was saved, but \(stuck.joined(separator: ", ")) is still mapped to it through "
            + "FilaMan's own tag binding, which SpoolKid cannot change."
    }

    /// The `card_uids` list a save writes, or nil when there is nothing to
    /// write.
    ///
    /// `shown` is the chip list, seeded from `previous` (`mappedCardUIDs`), so
    /// a FilaMan spool's `rfid_uid` shows as a chip too. The UIDs in
    /// `previous` but not in `writable` are there ONLY through `rfid_uid`;
    /// they are dropped before comparing and writing, because SpoolKid never
    /// writes `rfid_uid`, not even by copying it into `card_uids` (final
    /// review FR-2). Deleting such a chip therefore writes nothing, and
    /// `undetachableRemovalNote` — run on the unfiltered lists — reports it.
    nonisolated static func cardUIDsToWrite(shown: [String], previous: [String], writable: [String]) -> [String]? {
        let rfidOnly = Set(previous).subtracting(writable)
        let uids = shown.filter { !rfidOnly.contains($0) }
        return uids == writable ? nil : uids
    }

    /// Whether a new spool's tags travel in its POST as `card_uids`. Only
    /// where `card_uids` is the whole mapping: a native-tag server cannot
    /// take a Spoolman Tag link in the POST, and `card_uids` there would
    /// write SpoolLink even with SpoolLink off — so it links through
    /// `setCardUIDs` once the spool exists.
    nonisolated static func createCarriesCardUIDs(
        linkingActive: Bool, available: Set<TagStore>, hasUIDs: Bool
    ) -> Bool {
        linkingActive && hasUIDs && !available.contains(.spoolmanTags)
    }

    /// Why the section adds nothing, outside Tag Links; nil while it does.
    nonisolated static func linkedTagsFooter(identity: TagIdentityPolicy) -> String? {
        guard !identity.writesLinks else { return nil }
        let how = identity.mode == .spoolID ? "the spool ID on the tag" : "neither a spool ID nor a tag link"
        return "SpoolKid identifies spools by \(how), so it adds no tag links. You can still remove one."
    }

    /// Folds a follow-up write's outcome into the primary one and returns the
    /// haptic the save has actually earned.
    ///
    /// The spool is already on the server by this point, so a follow-up that
    /// failed is a caveat on the whole save, never a failure that strands the
    /// user in a form over a record that saved fine. It reaches them through
    /// the same banner, which accumulates rather than replaces
    /// (`SpoolDataStore.postSaveNotice`), so the primary write's own caveat is
    /// not lost by adding this one.
    private func feedback(after followUp: SaveOutcome, primary: SaveOutcome, record: String) -> SaveFeedback? {
        guard let message = followUp.followUpNote else { return primary.feedback }
        store.postSaveNotice(message, record: record)
        return .warning
    }

    /// "Spool 1" until the spool exists, "Spool #12" after: the number is what
    /// the user will find in the list.
    static func tagSectionTitle(position: Int, savedSpoolID: Int?) -> String {
        savedSpoolID.map { "Spool #\($0)" } ?? "Spool \(position)"
    }

    /// Write Tag always; Link Tag only where the mode writes links. Outside Tag
    /// Links nothing is linked, so there is nothing for Link Tag to do.
    nonisolated static func tagSectionActions(writesLinks: Bool) -> [TagAction] {
        writesLinks ? [.write, .link] : [.write]
    }

    /// The button's spoken name states its spool, so no tag is written or linked
    /// by a control that does not say where it goes: "Write Tag to Spool #13".
    /// While a scan runs the visible "Scanning…" is spoken too, still naming the spool.
    static func tagButtonAccessibilityLabel(
        _ action: TagAction, position: Int, savedSpoolID: Int?, isScanning: Bool
    ) -> String {
        let spool = tagSectionTitle(position: position, savedSpoolID: savedSpoolID)
        return isScanning ? "Scanning for \(spool)" : "\(action.title) to \(spool)"
    }

    /// Why the tag buttons are about to save: they are the first thing tapped.
    /// Outside Tag Links no Link Tag is shown, so the note does not mention linking.
    static func saveFirstNote(count: Int, writesLinks: Bool) -> String {
        let what = writesLinks ? "Writing or linking a tag" : "Writing a tag"
        let which = switch count {
        case ...1: "the spool"
        case 2: "both spools"
        default: "all \(count) spools"
        }
        return "\(what) saves \(which) first."
    }

    /// Plural only for a batch: one spool keeps the title it always had.
    static func formTitle(isEditing: Bool, count: Int) -> String {
        if isEditing { return "Edit Spool" }
        return count > 1 ? "Add Spools" : "Add Spool"
    }

    /// Done once spools exist: backing out no longer undoes anything, so the
    /// button says so rather than promising to cancel a save that happened.
    static func cancelTitle(isSaved: Bool) -> String {
        isSaved ? "Done" : "Cancel"
    }
}
