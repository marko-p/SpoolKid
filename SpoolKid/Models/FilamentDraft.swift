import Foundation

/// Declaration ORDER is load-bearing: it is the memberwise initialiser's
/// argument order, and dozens of call sites depend on it. The clearable and
/// set-only fields are therefore interleaved rather than grouped — each is
/// labelled instead.
struct FilamentDraft {
    /// Set-only. Spoolman requires it, and no form offers a way to clear one.
    var name: String?
    /// Tri-state (R21 stage 4). FilaMan REFUSES a clear here with a **500** —
    /// `manufacturer_id` is required — so `.setNil` is reported, never sent.
    var vendorId: SpoolmanPatchValue<Int> = .ignore
    /// Set-only, and required by FilaMan (`createRequirements`).
    var material: String?
    var price: SpoolmanPatchValue<Double> = .ignore
    /// Set-only. FilaMan requires a diameter; density has no clear control.
    var density: Double?
    var diameter: Double?
    var weight: SpoolmanPatchValue<Double> = .ignore
    var spoolWeight: SpoolmanPatchValue<Double> = .ignore
    /// FilaMan has no native scalar for any of these four, and — since
    /// 2026-08-28 — no longer emulates them in `custom_fields` either: none
    /// is rendered on FilaMan's filament form any more, and
    /// `FilaManPayloadBuilder.filamentPayload` no longer writes them.
    var articleNumber: SpoolmanPatchValue<String> = .ignore
    var comment: SpoolmanPatchValue<String> = .ignore
    var extruderTemp: SpoolmanPatchValue<Int> = .ignore
    var bedTemp: SpoolmanPatchValue<Int> = .ignore
    /// Set-only: the primary colour. Clearing it is `colors: []` on FilaMan,
    /// which wipes every colour the filament has.
    var colorHex: String?
    /// Tri-state, but FilaMan refuses both: a colour clear is a full REPLACE
    /// with an empty list, which takes the primary colour with it. Reported.
    var multiColorHexes: SpoolmanPatchValue<String> = .ignore
    var multiColorDirection: SpoolmanPatchValue<String> = .ignore
    /// Tri-state. FilaMan has **no filament-side field at all** for this, so a
    /// clear there is a no-op — and deliberately NOT reported (owner's call,
    /// 2026-08-25): there is nothing the user could do about a field the
    /// backend does not have.
    var externalId: SpoolmanPatchValue<String> = .ignore
    /// Tri-state. On FilaMan this is `custom_fields`, which is additive so
    /// `card_uids` and a migrated instance's `spoolman_id` survive an
    /// ordinary edit — `FilaManPayloadBuilder.filamentPayload` sends nothing
    /// rather than honour a `.setNil` clear.
    var extra: SpoolmanPatchValue<[String: String]> = .ignore
    /// Tri-state HueForge TD (mm). Each repository applies it in its own write
    /// path — it wins over a `td` key carried in `extra`.
    var transmissionDistance: SpoolmanPatchValue<Double> = .ignore
}
