//
//  FilaManRepositoryTests.swift
//  SpoolKidTests
//
//  Purpose: Task 16b — the pure decision logic behind `FilaManRepository`'s
//  fetch ordering, write plumbing, and fail-closed stubs. Network methods
//  themselves aren't unit-testable without a live server (no seam was added
//  for that — see the task report), so this covers what's extracted as pure
//  functions: dependency resolution during mapping, UID matching, location-
//  patch resolution, and the Task 19 stub contracts.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct FilaManRepositoryTests {
    private func makeFilament(id: Int, manufacturerId: Int) -> FilaManFilament {
        FilaManFilament(
            id: id, manufacturerId: manufacturerId, designation: "F\(id)", materialType: "PLA",
            materialSubgroup: nil, diameterMm: 1.75, rawMaterialWeightG: 1000, defaultSpoolWeightG: 140,
            price: nil, densityG_cm3: 1.24, colorMode: nil, multiColorStyle: nil, customFields: nil, colors: nil
        )
    }

    private func makeSpool(id: Int, filamentId: Int, locationId: Int? = nil) -> FilaManSpool {
        FilaManSpool(
            id: id, filamentId: filamentId, statusId: FilaManSpoolStatus.active, lotNumber: nil,
            rfidUid: nil, externalId: nil, locationId: locationId, purchaseDate: nil, purchasePrice: nil,
            stockedInAt: nil, lastUsedAt: nil, initialTotalWeightG: 1000, emptySpoolWeightG: 140,
            remainingWeightG: 800, createdAt: nil, customFields: nil
        )
    }

    // MARK: - mapFilaments (vendor resolution)

    @Test func mapFilamentsResolvesVendorByManufacturerId() {
        let vendor = Vendor(id: 7, name: "Prusament")
        let filaments = FilaManRepository.mapFilaments([makeFilament(id: 1, manufacturerId: 7)], vendors: [vendor])

        #expect(filaments.first?.vendor?.id == 7)
        #expect(filaments.first?.vendor?.name == "Prusament")
    }

    @Test func mapFilamentsLeavesVendorNilWhenManufacturerUnknown() {
        let filaments = FilaManRepository.mapFilaments([makeFilament(id: 1, manufacturerId: 99)], vendors: [])

        #expect(filaments.first?.vendor == nil)
    }

    // MARK: - mapSpools (filament dependency resolution + drop-on-missing)

    @Test func mapSpoolsResolvesFilamentById() {
        let filament = Filament(id: 5, name: "PLA Basic")
        let spools = FilaManRepository.mapSpools([makeSpool(id: 40, filamentId: 5)], filaments: [filament], locationsById: [:])

        #expect(spools.count == 1)
        #expect(spools.first?.filament.id == 5)
    }

    /// This should only happen from a genuine server-side data-integrity gap
    /// (`loadSpools` always resolves filaments before spools) — pins that it
    /// degrades by dropping the spool rather than crashing.
    @Test func mapSpoolsDropsASpoolWhoseFilamentIsNotFound() {
        let spools = FilaManRepository.mapSpools(
            [makeSpool(id: 40, filamentId: 999)], filaments: [Filament(id: 5, name: "PLA Basic")], locationsById: [:]
        )

        #expect(spools.isEmpty)
    }

    @Test func mapSpoolsResolvesLocationName() {
        let filament = Filament(id: 5, name: "PLA Basic")
        let spools = FilaManRepository.mapSpools(
            [makeSpool(id: 40, filamentId: 5, locationId: 3)], filaments: [filament], locationsById: [3: "Shelf B"]
        )

        #expect(spools.first?.location == "Shelf B")
    }

    @Test func mapSpoolsKeepsOnlyResolvableSpoolsAmongAMix() {
        let filament = Filament(id: 5, name: "PLA Basic")
        let dtos = [makeSpool(id: 40, filamentId: 5), makeSpool(id: 41, filamentId: 999)]
        let spools = FilaManRepository.mapSpools(dtos, filaments: [filament], locationsById: [:])

        #expect(spools.map(\.id) == [40])
    }

    // MARK: - findSpool(in:byCardUID:)

    @Test func findSpoolMatchesByNormalizedCardUID() {
        let filament = Filament(id: 1, name: "PLA")
        let spool = Spool(id: 10, filament: filament, extra: ["card_uids": "AABBCCDD"], statusId: nil, externalId: nil, purchaseDate: nil)

        let found = FilaManRepository.findSpool(in: [spool], byCardUID: "aa:bb-cc dd")

        #expect(found?.id == 10)
    }

    @Test func findSpoolMatchesByFilaManRfidUID() {
        let filament = Filament(id: 1, name: "PLA")
        let spool = Spool(id: 11, filament: filament, rfidUID: "11223344", statusId: nil, externalId: nil, purchaseDate: nil)

        let found = FilaManRepository.findSpool(in: [spool], byCardUID: "11:22:33:44")

        #expect(found?.id == 11)
    }

    @Test func findSpoolReturnsNilWhenNoSpoolMatches() {
        let filament = Filament(id: 1, name: "PLA")
        let spool = Spool(id: 10, filament: filament, extra: ["card_uids": "AABBCCDD"], statusId: nil, externalId: nil, purchaseDate: nil)

        #expect(FilaManRepository.findSpool(in: [spool], byCardUID: "DEADBEEF") == nil)
    }

    // MARK: - Location resolution
    //
    // Task 17 (F25) split this into two seams: `plannedLocationResolution`
    // decides what a draft's free-text name means against the locations FilaMan
    // already has — covered in FilaManMappingTests, including the `.create`
    // case this used to collapse into `.ignore` — and `resolveLocation` then
    // performs it, returning either a wire patch or a `.failed` message that a
    // caller cannot mistake for "nothing was requested".
    //
    // The F24 rule that `.ignore` and `.setNil` must stay distinct on the wire
    // is pinned in FilaManPayloadBuilderTests, where the encoding lives.

    // MARK: - Task 19: the writes are real, the stubs are gone
    //
    // This replaces `setCardUIDsFailsClosed`, which pinned the OPPOSITE
    // contract: refuse outright, because a bare `true` would tell a user a tag
    // was mapped when it was not. Task 19 made the write real, so that
    // contract is retired rather than merely unmet.
    //
    // What is worth pinning now is that whatever the write reports arrives on
    // THIS type's `errorMessage`. It is a stored property (see `testConnection`),
    // so a failure the *service* knows about stays invisible to
    // `SaveOutcome.classify` — and to the user — unless it is copied across.
    //
    // The test does not claim the write succeeds or fails: there is no network seam
    // here, so that depends on whether the machine running the suite happens to
    // have a reachable FilaMan configured. Its assertions hold either way. The
    // substance of what gets written is pinned on the pure seams below.

    @Test func setCardUIDsSurfacesTheServicesOwnOutcomeOnThisType() async {
        let service = FilaManService()
        let repo = FilaManRepository(service: service)

        let ok = await repo.setCardUIDs(spoolId: 1, uids: ["AABBCCDD"])

        // Nothing is cached, so the plan cannot be built: the repository itself
        // says why (Task 4 — it used to defer straight to the service).
        #expect(ok == false)
        #expect(repo.errorMessage == "Spool #1 could not be found in FilaMan.")
        #expect(repo.errorMessage != "Mapping tags to spools on FilaMan isn't implemented yet.")
    }

    // MARK: - F39: `SpoolDraft.archived` is a status transition, not a field
    //
    // `FilaManPayloadBuilder` never read `draft.archived`, so flipping Archived
    // in the spool form PATCHed, got a 200, fired the success haptic and
    // dismissed — with nothing archived. `SpoolmanPayloadBuilder` and
    // `LocalRepository` both honour it, so this was a substitutability break as
    // well as a silent success. `MigrationService` reaches the same path, which
    // silently un-archived every archived local spool it migrated.
    //
    // The mechanism trap: archiving is `POST /spools/{id}/status`, and the
    // status is ONE field holding six values. "Not archived" is not a value —
    // writing `active` unconditionally would flatten `new`, `opened`, `drying`
    // and `empty` on every ordinary save. So the decision is a comparison, and
    // it lives on this pure seam.

    /// Every status FilaMan defines, so a new one cannot quietly escape these.
    private static let allStatusIds = [
        FilaManSpoolStatus.new, FilaManSpoolStatus.opened, FilaManSpoolStatus.drying,
        FilaManSpoolStatus.active, FilaManSpoolStatus.empty, FilaManSpoolStatus.archived
    ]
    private static let unarchivedStatusIds = [
        FilaManSpoolStatus.new, FilaManSpoolStatus.opened, FilaManSpoolStatus.drying,
        FilaManSpoolStatus.active, FilaManSpoolStatus.empty
    ]

    @Test func noStatusPostWhenTheDraftSaysNothingAboutArchiving() {
        for status in Self.allStatusIds {
            #expect(FilaManRepository.archivedStatusTransition(wanted: nil, currentStatusId: status) == nil)
        }
    }

    /// FilaMan creates a spool as `new` (1). A create carrying `archived: false`
    /// — which every spool form save does — must not force `active` over that.
    @Test func noStatusPostWhenAnUnarchivedDraftMeetsANonArchivedSpool() {
        for status in Self.unarchivedStatusIds {
            #expect(FilaManRepository.archivedStatusTransition(wanted: false, currentStatusId: status) == nil)
        }
    }

    @Test func archivingPostsWhenTheSpoolIsNotYetArchived() {
        for status in Self.unarchivedStatusIds {
            #expect(FilaManRepository.archivedStatusTransition(wanted: true, currentStatusId: status) == true)
        }
    }

    @Test func unarchivingPostsOnlyForASpoolThatIsActuallyArchived() {
        #expect(FilaManRepository.archivedStatusTransition(wanted: false, currentStatusId: FilaManSpoolStatus.archived) == false)
    }

    @Test func noStatusPostWhenAnArchivedDraftMeetsAnAlreadyArchivedSpool() {
        #expect(FilaManRepository.archivedStatusTransition(wanted: true, currentStatusId: FilaManSpoolStatus.archived) == nil)
    }

    /// The read mapping and the write decision must agree on what "archived"
    /// means, or a spool could be shown as archived and refuse to unarchive.
    @Test func theTransitionAgreesWithTheReadMappingOnWhatArchivedMeans() {
        for archived in [true, false] {
            let statusId = FilaManSpoolStatus.id(archived: archived)
            #expect(FilaManRepository.archivedStatusTransition(wanted: archived, currentStatusId: statusId) == nil)
            #expect(FilaManRepository.archivedStatusTransition(wanted: !archived, currentStatusId: statusId) == !archived)
        }
    }

    // MARK: - Task 7 fix round 1: statusKeyTransition (no test existed for
    // either this pure seam or the caveat its failure produces — the picker's
    // sibling to F39's archivedStatusTransition coverage above).

    /// `.set` wins outright: a picker choice needs no comparison against the
    /// spool's current status, unlike the boolean (R21 — `SpoolFormView` only
    /// ever states a picker value the user actually changed from what loaded).
    @Test func aSetStatusKeyIsAlwaysANeededTransitionRegardlessOfCurrentStatus() {
        for currentStatusId in Self.allStatusIds {
            #expect(FilaManRepository.statusKeyTransition(
                statusKey: .set("drying"), archived: nil, currentStatusId: currentStatusId
            ) == "drying")
        }
    }

    /// An untouched picker (`.ignore`) falls back to the boolean, exactly as
    /// before the picker existed.
    @Test func anIgnoredStatusKeyFallsBackToTheArchivedFlag() {
        #expect(FilaManRepository.statusKeyTransition(
            statusKey: .ignore, archived: true, currentStatusId: FilaManSpoolStatus.active
        ) == FilaManSpoolStatus.key(archived: true))
    }

    /// Neither the picker nor the flag asked for anything: no transition is
    /// needed, and nothing should be posted.
    @Test func noTransitionIsNeededWhenNeitherThePickerNorTheFlagAsksForOne() {
        for currentStatusId in Self.allStatusIds {
            #expect(FilaManRepository.statusKeyTransition(
                statusKey: .ignore, archived: nil, currentStatusId: currentStatusId
            ) == nil)
        }
    }

    /// The fallback path still declines a no-op transition — an unarchived
    /// draft meeting an already-unarchived spool asks for nothing, same as
    /// `archivedStatusTransition` alone.
    @Test func theFallbackPathStillDeclinesANoOpTransition() {
        #expect(FilaManRepository.statusKeyTransition(
            statusKey: .ignore, archived: false, currentStatusId: FilaManSpoolStatus.new
        ) == nil)
    }

    /// The caveat when a status write fails — worded field-first, not
    /// "Archived — the spool could not be…", since the picker's failure isn't
    /// only ever an archive/unarchive. Pure, so the exact wording is pinned
    /// without needing a live FilaMan to fail against.
    @Test func aFailedStatusWriteProducesACaveatNamingTheField() {
        struct SomeError: LocalizedError {
            var errorDescription: String? { "the server refused it." }
        }

        #expect(FilaManRepository.statusNotChangedNote(SomeError())
                == "Status — not changed: the server refused it.")
    }

    // MARK: - cardUIDsField (the encoding both writers share)

    /// Task 18: FilaMan's Spoolman-compat layer JSON-encodes each custom field
    /// on read, so the value written natively must be BARE. Writing Spoolman's
    /// wrapped form here would double-wrap it through that layer — invisible to
    /// SpoolKid, broken for every other SpoolLink client.
    @Test func cardUIDsFieldWritesTheBareEncodingNotSpoolmansWrappedOne() {
        let field = FilaManRepository.cardUIDsField(["aa:bb-cc dd", "11223344"])

        #expect(field == ["card_uids": "AABBCCDD,11223344"])
    }

    @Test func cardUIDsFieldEncodesAnEmptyListAsAnEmptyValue() {
        #expect(FilaManRepository.cardUIDsField([]) == ["card_uids": ""])
    }

    // MARK: - F30: what `FilamentCreate` actually requires

    private var completeDraft: FilamentDraft {
        FilamentDraft(name: "PLA Basic", vendorId: .set(7), material: "PLA", diameter: 1.75)
    }

    private func missingRequirement(_ draft: FilamentDraft) -> String? {
        guard case .missing(let message) = FilaManRepository.createRequirements(of: draft) else {
            return nil
        }
        return message
    }

    @Test func everyMissingRequirementIsListed() {
        // `createRequirements` reports only the first, which is right for a
        // one-sentence `errorMessage` and useless for building a form.
        let bare = FilamentDraft()

        #expect(FilaManRepository.missingRequirements(of: bare)
                == [.name, .material, .diameter, .manufacturer])
        #expect(FilaManRepository.missingRequirements(of: completeDraft).isEmpty)
    }

    @Test func theSentenceAndTheListCannotDisagree() {
        // One source of truth: the sentence is derived from the list's first
        // entry, so a requirement added to one is added to both.
        let noMaterial = FilamentDraft(name: "PLA Basic", vendorId: .set(7), diameter: 1.75)

        #expect(FilaManRepository.missingRequirements(of: noMaterial) == [.material])
        #expect(missingRequirement(noMaterial) == FilaManRepository.sentence(for: .material))
    }

    @Test func whitespaceDoesNotSatisfyAStringRequirement() {
        let blank = FilamentDraft(name: "  ", vendorId: .set(7), material: "\t", diameter: 1.75)

        #expect(FilaManRepository.missingRequirements(of: blank) == [.name, .material])
    }

    @Test func aCompleteDraftSatisfiesTheRequirementsAndCarriesItsManufacturer() {
        #expect(
            FilaManRepository.createRequirements(of: completeDraft) == .satisfied(manufacturerId: 7)
        )
    }

    /// The guard that already existed. Kept as its own case so the three added
    /// below cannot be read as replacing it.
    @Test func aDraftWithoutAManufacturerIsRefusedClientSide() {
        var draft = completeDraft
        draft.vendorId = .ignore

        #expect(missingRequirement(draft)?.contains("manufacturer") == true)
    }

    /// A draft that asks to CLEAR the manufacturer counts as missing one, not
    /// as a clear to attempt: FilaMan answers a null `manufacturer_id` with a
    /// **500**, which carries no message worth passing on.
    @Test func aDraftClearingItsManufacturerIsRefusedTheSameWay() {
        var draft = completeDraft
        draft.vendorId = .setNil

        #expect(missingRequirement(draft)?.contains("manufacturer") == true)
    }

    /// `FilamentCreate` requires `designation`/`material_type`/`diameter_mm`
    /// too, so a draft missing any of them used to reach the server and come
    /// back as a raw 422 — the exact outcome the manufacturer guard exists to
    /// prevent.
    @Test func aDraftWithoutANameIsRefusedClientSide() {
        var draft = completeDraft
        draft.name = nil

        #expect(missingRequirement(draft)?.contains("name") == true)
    }

    @Test func aDraftWithoutAMaterialIsRefusedClientSide() {
        var draft = completeDraft
        draft.material = nil

        #expect(missingRequirement(draft)?.contains("material") == true)
    }

    @Test func aDraftWithoutADiameterIsRefusedClientSide() {
        var draft = completeDraft
        draft.diameter = nil

        #expect(missingRequirement(draft)?.contains("diameter") == true)
    }

    /// A blank string is not a designation. `FilamentFormView` gates Save on a
    /// non-empty name, but `MigrationService` assembles drafts with no such
    /// gate — and whitespace would satisfy a bare `nil` check.
    @Test func aDraftWhoseNameIsOnlyWhitespaceIsRefusedClientSide() {
        var draft = completeDraft
        draft.name = "   "

        #expect(missingRequirement(draft)?.contains("name") == true)
    }

    @Test func aDraftWhoseMaterialIsOnlyWhitespaceIsRefusedClientSide() {
        var draft = completeDraft
        draft.material = "\t"

        #expect(missingRequirement(draft)?.contains("material") == true)
    }

    /// One sentence, naming one thing to fix — reporting all four at once
    /// would be a wall of text on a form the user is looking at.
    @Test func theMessageNamesTheFirstMissingRequirementOnly() {
        let message = missingRequirement(FilamentDraft())

        #expect(message?.contains("name") == true)
        #expect(message?.contains("material") == false)
    }

    // MARK: - Filament fields FilaMan will not clear (R21 stage 4)

    @Test func clearingAManufacturerIsReported() {
        var draft = FilamentDraft()
        draft.vendorId = .setNil

        #expect(FilaManRepository.unclearableFilamentNote(draft)?.contains("manufacturer") == true)
    }

    /// Clearing the colours means `colors: []`, a full REPLACE that would take
    /// the primary colour too. The note says so, because "could not" alone
    /// would not explain why.
    @Test func clearingTheExtraColoursIsReportedWithItsReason() {
        var draft = FilamentDraft()
        draft.multiColorHexes = .setNil

        let note = FilaManRepository.unclearableFilamentNote(draft)

        #expect(note?.contains("colours") == true)
        #expect(note?.contains("main one") == true)
    }

    /// Switching a multi-colour back to single sends the primary colour with the
    /// pair cleared. Colours are then replaced by that one colour, which is a
    /// change the user asked for, so nothing is refused.
    @Test func unclearableNoteIgnoresSwitchToSingle() {
        var draft = FilamentDraft()
        draft.colorHex = "FF0000"
        draft.multiColorHexes = .setNil
        draft.multiColorDirection = .setNil

        #expect(FilaManRepository.unclearableFilamentNote(draft) == nil)
    }

    @Test func bothRefusalsShareOneSentence() {
        var draft = FilamentDraft()
        draft.vendorId = .setNil
        draft.multiColorDirection = .setNil

        let note = FilaManRepository.unclearableFilamentNote(draft)

        #expect(note?.contains("manufacturer") == true)
        #expect(note?.contains("colours") == true)
    }

    /// `external_id` has NO filament-side field on FilaMan at all, so a clear
    /// there is a no-op about something the backend does not have. Reporting
    /// it would be noise the user can do nothing with (owner's call).
    @Test func clearingAnExternalIdIsDeliberatelyNotReported() {
        var draft = FilamentDraft()
        draft.externalId = .setNil

        #expect(FilaManRepository.unclearableFilamentNote(draft) == nil)
    }

    @Test func aDraftThatClearsNothingRefusedReportsNothing() {
        #expect(FilaManRepository.unclearableFilamentNote(FilamentDraft()) == nil)
    }

    /// `.setNil` on the colours is NOT an empty hex list: an empty `colors`
    /// array is the wipe this refuses. It must read as "say nothing", so
    /// `applyFilamentColors` skips the request entirely.
    /// A switch to single colour carries the primary colour and clears the
    /// pair, so the write is that one colour and nothing else.
    @Test func switchToSingleDraftWritesOnlyTheSingleHex() {
        var draft = FilamentDraft()
        draft.colorHex = "FF0000"
        draft.multiColorHexes = .setNil
        draft.multiColorDirection = .setNil

        #expect(FilaManRepository.colorHexes(from: draft) == ["ff0000"])
    }

    @Test func clearingTheColoursYieldsNoHexesRatherThanAnEmptyWrite() {
        var draft = FilamentDraft()
        draft.colorHex = "FF0000"
        draft.multiColorHexes = .setNil

        #expect(FilaManRepository.colorHexes(from: draft) == ["ff0000"])
    }

    // MARK: - Dates FilaMan will not take (probed 2026-08-25)
    //
    // `unwritableDateNoteOnUpdate` and its tests were deleted 2026-08-28:
    // FilaMan's spool form no longer renders First Used or Last Used, so an
    // ordinary edit can no longer state either — `updateSpool` can never
    // receive anything but `.ignore` for them any more. The create-side note
    // below stays: `MigrationService` builds `SpoolDraft.lastUsed` straight
    // from a local spool's history, bypassing the form, so a migrated date
    // can still reach `addSpool` and still be silently dropped by FilaMan.

    /// A create DOES keep `stocked_in_at`, so only the other one is reported.
    @Test func aCreateReportsOnlyLastUsed() {
        #expect(
            FilaManRepository.unwritableDateNoteOnCreate(
                firstUsed: .set("2026-01-01T00:00:00Z"), lastUsed: .ignore
            ) == nil
        )

        let note = FilaManRepository.unwritableDateNoteOnCreate(
            firstUsed: .set("2026-01-01T00:00:00Z"), lastUsed: .set("2026-02-02T00:00:00Z")
        )
        #expect(note?.contains("Last Used") == true)
        #expect(note?.contains("First Used") == false)
    }

    // MARK: - Comment FilaMan will not take on a vendor or spool create (2026-08-28)
    //
    // Task 6 stopped emulating `comment` in `custom_fields`. The form path is
    // closed on both entities, but `MigrationService` still builds `comment`
    // straight from local history, bypassing the form — same story as the
    // dates above.

    @Test func aStatedCommentIsReportedOnCreate() {
        let note = FilaManRepository.unwritableCommentNoteOnCreate("Bench spool")

        #expect(note?.contains("Comment") == true)
    }

    @Test func aNilOrEmptyCommentSaysNothingOnCreate() {
        #expect(FilaManRepository.unwritableCommentNoteOnCreate(nil) == nil)
        #expect(FilaManRepository.unwritableCommentNoteOnCreate("") == nil)
    }

    // MARK: - The filament four FilaMan will not take on create (2026-08-28)
    //
    // Same story: Task 6 stopped emulating Article Number / Comment /
    // Extruder Temp / Bed Temp, and only `MigrationService` can still state
    // any of them (the form path is closed).

    @Test func allFourStatedFilamentFieldsAreEachNamedOnCreate() {
        var draft = FilamentDraft()
        draft.articleNumber = .set("AB-1")
        draft.comment = .set("Great filament")
        draft.extruderTemp = .set(210)
        draft.bedTemp = .set(60)

        let note = FilaManRepository.unwritableFilamentFieldsNoteOnCreate(draft)

        #expect(note?.contains("Article Number") == true)
        #expect(note?.contains("Comment") == true)
        #expect(note?.contains("Extruder Temp") == true)
        #expect(note?.contains("Bed Temp") == true)
    }

    @Test func onlyTheStatedFilamentFieldsAreNamedOnCreate() {
        var draft = FilamentDraft()
        draft.comment = .set("Great filament")

        let note = FilaManRepository.unwritableFilamentFieldsNoteOnCreate(draft)

        #expect(note?.contains("Comment") == true)
        #expect(note?.contains("Article Number") == false)
        #expect(note?.contains("Extruder Temp") == false)
        #expect(note?.contains("Bed Temp") == false)
    }

    @Test func aFilamentDraftThatStatesNoneOfTheFourSaysNothingOnCreate() {
        #expect(FilaManRepository.unwritableFilamentFieldsNoteOnCreate(FilamentDraft()) == nil)
    }

    // MARK: - external_id on filaments and manufacturers (2026-09-24)
    //
    // FilaMan has an `external_id` column on spools only. A migrated filament
    // or manufacturer that carries one used to lose it with no word said —
    // the payload builders never emit the key.

    @Test func aStatedFilamentExternalIDIsNamedOnCreate() {
        var draft = FilamentDraft()
        draft.externalId = .set("SKU-9")

        let note = FilaManRepository.unwritableFilamentFieldsNoteOnCreate(draft)

        #expect(note?.contains("External ID") == true)
    }

    @Test func aStatedManufacturerExternalIDIsNamedOnCreate() {
        let note = FilaManRepository.unwritableVendorFieldsNoteOnCreate(comment: nil, externalId: "M-1")

        #expect(note?.contains("External ID") == true)
        #expect(note?.contains("Comment") == false)
    }

    @Test func aManufacturerCommentAndExternalIDAreBothNamedOnCreate() {
        let note = FilaManRepository.unwritableVendorFieldsNoteOnCreate(comment: "Local shop", externalId: "M-1")

        #expect(note?.contains("Comment") == true)
        #expect(note?.contains("External ID") == true)
    }

    @Test func aManufacturerStatingNeitherSaysNothingOnCreate() {
        #expect(FilaManRepository.unwritableVendorFieldsNoteOnCreate(comment: nil, externalId: nil) == nil)
        #expect(FilaManRepository.unwritableVendorFieldsNoteOnCreate(comment: "", externalId: "") == nil)
    }

    // MARK: - Wiring

    @Test func capabilitiesReportFilaManKind() {
        let repo = FilaManRepository(service: FilaManService())

        #expect(repo.capabilities.kind == .filaman)
        #expect(repo.capabilities.isOnDeviceStorage == false)
    }

    @Test func lastQuotaErrorIsAlwaysNil() {
        let repo = FilaManRepository(service: FilaManService())

        #expect(repo.lastQuotaError == nil)
    }
}
