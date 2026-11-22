//
//  SpoolFormInitialWeightTests.swift
//  SpoolKidTests
//
//  What a new spool's Initial Filament Weight starts as, and the size chips
//  under it. Reported 2026-10-25: a spool created from a Prusament
//  OpenPrintTag (818 g) made the next, manually added spool open at 818 g,
//  because the form remembered the last value saved. Owner: the tag's weight,
//  else the filament's own net weight, else 1000; Spoolman's six sizes as
//  chips, in Add Spool only.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolFormInitialWeightTests {

    // MARK: - Prefill

    @Test func theTagsInitialWeightBeatsTheFilaments() {
        #expect(SpoolFormView.newSpoolInitialWeight(tagWeight: 818, filamentWeight: 1000) == "818")
    }

    @Test func withoutATagWeightTheFilamentsNetWeightIsUsed() {
        #expect(SpoolFormView.newSpoolInitialWeight(tagWeight: nil, filamentWeight: 750) == "750")
        #expect(SpoolFormView.newSpoolInitialWeight(tagWeight: 0, filamentWeight: 750) == "750")
    }

    @Test func withNeitherANewSpoolStartsAt1000() {
        #expect(SpoolFormView.newSpoolInitialWeight(tagWeight: nil, filamentWeight: nil) == "1000")
        // 0 means the filament states none.
        #expect(SpoolFormView.newSpoolInitialWeight(tagWeight: nil, filamentWeight: 0) == "1000")
    }

    // MARK: - Following the filament

    @Test func anUntouchedInitialWeightFollowsTheFilament() {
        #expect(SpoolFormView.refilledInitialWeight(
            current: "1000", autoFilled: "1000", isNewSpool: true, filamentWeight: 750
        ) == "750")
        #expect(SpoolFormView.refilledInitialWeight(
            current: "750", autoFilled: "750", isNewSpool: true, filamentWeight: nil
        ) == "1000")
    }

    @Test func aTypedPickedOrTagWeightIsNeverOverwritten() {
        // Typed over the filled-in value.
        #expect(SpoolFormView.refilledInitialWeight(
            current: "900", autoFilled: "1000", isNewSpool: true, filamentWeight: 750
        ) == nil)
        // A chip tap, or a tag's weight, leaves nothing auto-filled.
        #expect(SpoolFormView.refilledInitialWeight(
            current: "818", autoFilled: nil, isNewSpool: true, filamentWeight: 750
        ) == nil)
        // Edit Spool never refills.
        #expect(SpoolFormView.refilledInitialWeight(
            current: "1000", autoFilled: "1000", isNewSpool: false, filamentWeight: 750
        ) == nil)
    }

    // MARK: - Size chips

    @Test func theSizeChipsAreSpoolmansSix() {
        #expect(SpoolFormView.initialWeightPresets.map(SpoolFormView.presetLabel)
            == ["250 g", "500 g", "750 g", "1 kg", "2 kg", "3 kg"])
    }

    @Test func theChipMatchingTheFieldIsSelected() {
        #expect(SpoolFormView.isPresetSelected(1000, field: "1000"))
        #expect(SpoolFormView.isPresetSelected(1000, field: "1000.0"))
        #expect(!SpoolFormView.isPresetSelected(1000, field: "999"))
        #expect(!SpoolFormView.isPresetSelected(1000, field: ""))
    }
}
