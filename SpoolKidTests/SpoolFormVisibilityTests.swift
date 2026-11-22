import Foundation
import Testing
@testable import SpoolKid

struct SpoolFormVisibilityTests {
    /// The form helper routes through the support∩preference intersection and
    /// returns this entity's fields. It asserts the DEFAULT only: the helper
    /// takes capabilities, not a `UserDefaults`, so a toggle cannot be injected
    /// here. Toggle behaviour is covered directly, against an injected suite,
    /// in `FieldVisibilityStoreTests`.
    @Test func spoolFormHidesArchivedByDefault() {
        let ids = SpoolFormView.visibleFieldIDs(for: BackendCapabilities.spoolman)

        #expect(!ids.contains("archived"))
    }

    @Test func spoolPayloadCanClearLocation() {
        let draft = SpoolFormView.spoolPayload(
            filamentId: 1,
            price: "",
            initialWeight: "1000",
            spoolWeight: "140",
            remainingWeight: "800",
            usedWeight: "",
            location: "",
            comment: "",
            archived: false,
            firstUsedISO8601: "",
            lastUsedISO8601: ""
        )

        if case .setNil = draft.location {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }

    /// One picker, no switch (audit S2): choosing None always clears.
    @Test func anEmptyLocationAlwaysClears() {
        #expect(SpoolFormView.locationPatch(for: "") == .setNil)
        #expect(SpoolFormView.locationPatch(for: "  ") == .setNil)
        #expect(SpoolFormView.locationPatch(for: " Shelf A ") == .set("Shelf A"))
    }

    // `clearFieldKeysStillCarryAnEmptiedExtra` was the last of these. `extra`
    // is a patch value now and `SpoolDraft.clearFieldKeys` is gone entirely.

    // The Extra JSON box (`extraPatch`/`droppedExtraNote`) is gone as of
    // 2026-08-28 (task 4, backend-aware fields): Spoolman's `extra` is a
    // typed registry holding only `card_uids`, which travels through
    // `CardUIDsCodec` now, not a free-form textarea.

    // `comment`, `lot_nr`, `first_used` and `last_used` used to be asserted
    // above. Same idea, said in the type instead of in a set of Spoolman key
    // names (R21) — an emptied box on an edit still clears the field.
    @Test func anEmptiedTextBoxClearsOnUpdate() {
        #expect(SpoolFormView.textPatch(current: "", loaded: "bench") == .setNil)
        #expect(SpoolFormView.textPatch(current: "   ", loaded: "bench") == .setNil)
        #expect(SpoolFormView.textPatch(current: " desk ", loaded: "bench") == .set("desk"))
    }

    /// A box still holding what was loaded says nothing — the lost update
    /// `weightPatch` closes, on text. Two people editing one spool: the second
    /// save must not re-assert a comment it never touched.
    @Test func anUntouchedTextBoxSaysNothing() {
        #expect(SpoolFormView.textPatch(current: "bench", loaded: "bench") == .ignore)
        #expect(SpoolFormView.textPatch(current: " bench ", loaded: "bench") == .ignore)
        #expect(SpoolFormView.textPatch(current: "", loaded: "") == .ignore)
    }

    /// The create side falls out of the same rule: nothing was loaded, so an
    /// empty box says nothing and a stated one is a set.
    @Test func anEmptyTextBoxSaysNothingOnCreate() {
        #expect(SpoolFormView.textPatch(current: "", loaded: "") == .ignore)
        #expect(SpoolFormView.textPatch(current: " bench ", loaded: "") == .set("bench"))
    }
}
