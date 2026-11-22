import Testing
@testable import SpoolKid

/// The Extra JSON control is gone; the `extra` transport it shared with the
/// SpoolLink mapping is not. This is the test that fails loudly if a later
/// cleanup deletes the wrong one.
struct CardUIDsSurviveExtraRemovalTests {
    @Test func aTagMappingStillReachesTheExtraPayload() {
        let patch = CardUIDsCodec.applyingWrapped(["04A1B2C3D4E5F6"], to: .ignore)

        guard case .set(let fields) = patch else {
            Issue.record("card_uids no longer produces an extra payload")
            return
        }
        #expect(fields["card_uids"] != nil)
    }

    @Test func noEntityStillOffersAnExtraJSONField() {
        for entity in LibraryEntity.allCases {
            #expect(FieldCatalog.fields(for: entity).contains { $0.id == "extra" } == false,
                    "\(entity.rawValue) still offers Extra JSON")
        }
    }
}
