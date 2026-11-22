import Foundation

struct SpoolDraft {
    var filamentId: Int?
    /// Tri-state like the other text fields, and the first pair FilaMan
    /// outright REFUSES: `stocked_in_at` is create-only and `last_used_at` is
    /// derived from its own usage history, so `.set` and `.setNil` are equally
    /// unwritable there and equally worth reporting. FilaMan's spool form no
    /// longer renders either (2026-08-28), so an ordinary edit never states
    /// them — but `MigrationService` builds this draft straight from a local
    /// spool's history, bypassing the form, so a migrated `lastUsed` can still
    /// reach a FilaMan create and be silently dropped — see
    /// `FilaManRepository.unwritableDateNoteOnCreate`.
    var firstUsed: SpoolmanPatchValue<String> = .ignore
    var lastUsed: SpoolmanPatchValue<String> = .ignore
    var price: Double?
    /// The four weights are tri-state (R21). `.ignore` — the default — means
    /// "this draft says nothing about the field", which a bare `Double?` could
    /// not express: nil meant both "leave it alone" and "the user cleared it",
    /// so every save asserted whatever the form had loaded and the second of
    /// two concurrent edits silently reverted the first.
    ///
    /// `.setNil` is currently unreachable from `SpoolFormView` — an emptied
    /// weight field reads as `.ignore`, which is what it has always meant —
    /// but the backends handle it, because the same type serves the filament
    /// form, where clearing a weight IS offered.
    var initialWeight: SpoolmanPatchValue<Double> = .ignore
    var spoolWeight: SpoolmanPatchValue<Double> = .ignore
    var remainingWeight: SpoolmanPatchValue<Double> = .ignore
    var usedWeight: SpoolmanPatchValue<Double> = .ignore
    /// The GROSS scale reading, when the user stated the weight by weighing the
    /// whole spool rather than naming what is left or what is gone. Carried
    /// separately from `remainingWeight` because the net figure cannot be
    /// converted back: `remaining = measured − empty_spool_weight_g` uses the
    /// SERVER's basis, and the same save may be changing SpoolKid's copy of it.
    ///
    /// Only FilaMan reads it, and only on update: it routes the write to
    /// `POST /spools/{id}/measurements`, which records a `measurement` in the
    /// event history instead of a `manual_adjust`. Spoolman and the on-device
    /// Library have no measurement concept and use `remainingWeight`, which
    /// `SpoolFormView` fills in every mode.
    var measuredWeight: Double?
    var location: SpoolmanPatchValue<String> = .ignore
    /// Tri-state like the weights, and for the same reason — but with the
    /// OPPOSITE reading of an empty field. A blank text box on an edit means
    /// "clear this", because the form loaded whatever the record held into it;
    /// a blank weight box means "leave it alone", because the form offers no
    /// control that means clear (see `SpoolFormView.textPatch` and
    /// `weightPatch`).
    ///
    /// These two were the first fields to prove `clearFieldKeys` could not
    /// work: the key names in that set are SPOOLMAN's, so every other backend
    /// had to translate them, and `FilaManRepository` never did — clearing a
    /// comment or a lot number on FilaMan returned `true` and did nothing
    /// (R21).
    var lotNr: SpoolmanPatchValue<String> = .ignore
    var comment: SpoolmanPatchValue<String> = .ignore
    var archived: Bool?
    /// FilaMan's status **key** ("active", "archived", …), never its numeric
    /// id — `POST /spools/{id}/status` rejects the id with a 422. Never rides
    /// in the spool PATCH; `FilaManRepository.applyArchivedStatus` takes this
    /// in preference to `archived` when it is `.set` (Task 7).
    var statusKey: SpoolmanPatchValue<String> = .ignore
    /// FilaMan only; nil on Spoolman and the on-device Library.
    var externalId: SpoolmanPatchValue<String> = .ignore
    /// FilaMan only. A calendar date, carried as a string like `firstUsed`/
    /// `lastUsed` — see `SpoolFormView`'s `dateFormatter`.
    var purchaseDate: SpoolmanPatchValue<String> = .ignore
    /// The raw passthrough bucket, tri-state like everything else. `.ignore`
    /// matters more here than anywhere: `extra` is the whole object, so a save
    /// that re-asserted it overwrote any key another client had added since
    /// the form loaded — and on FilaMan it forced a read-merge-write on every
    /// single save.
    ///
    /// `.setNil` is honoured by Spoolman and the local store, where `extra` is
    /// authoritative. FilaMan **refuses** it: there `extra` IS `custom_fields`,
    /// so emptying it would take `card_uids` and a migrated instance's
    /// `spoolman_id` with it — `FilaManPayloadBuilder.spoolPayload` sends
    /// nothing rather than honour the clear.
    var extra: SpoolmanPatchValue<[String: String]> = .ignore
    /// The SpoolLink tag→spool mapping, as a list of UIDs rather than as an
    /// already-encoded `extra["card_uids"]` string.
    ///
    /// The wire encoding is **backend-specific** — Spoolman and the local store
    /// keep the JSON-string-wrapped form, FilaMan the bare comma-separated one
    /// (`CardUIDsCodec.encode` vs `encodeBare`) — so it cannot be chosen by
    /// whichever view or service builds the draft. It was, until 2026-08-23:
    /// the shared spool form encoded Spoolman's form into `extra` and every
    /// backend copied it verbatim, so a spool **created** on FilaMan carried a
    /// value its compat layer wrapped a second time on read, and third-party
    /// SpoolLink/Snapmaker U1 clients saw a double-wrapped UID list. Only they
    /// broke — `CardUIDsCodec.parse` tolerates both forms, so nothing looked
    /// wrong inside SpoolKid.
    ///
    /// `nil` means "this draft says nothing about the mapping" — leave whatever
    /// the record already carries alone. It is never "clear the mapping"; that
    /// is `setCardUIDs(spoolId:uids:)` with an empty list.
    ///
    /// Where both this and `extra["card_uids"]` are set, this wins: it is the
    /// only channel that knows which encoding the destination wants.
    var cardUIDs: [String]?
}

extension SpoolDraft {
    /// A draft that says nothing about a spool except where it now lives.
    ///
    /// Every location assignment in the app builds its draft here, so no
    /// caller can accidentally re-assert a weight or a comment it happened to
    /// have loaded — the lost-update failure the tri-state patches exist to
    /// prevent.
    static func locationAssignment(_ location: SpoolmanPatchValue<String>) -> SpoolDraft {
        var draft = SpoolDraft()
        draft.location = location
        return draft
    }
}
