//
//  SpoolFormWeightModeTests.swift
//  SpoolKidTests
//
//  The Weight Status picker offers three readings of the same spool, and one
//  `weightInput` holds all three. Switching modes left the number untouched, so
//  a spool with 750 g left reported 750 g *used* and 750 g *on the scale* —
//  three different physical claims, all wrong but one. Reported 2026-08-24.
//

import Testing
@testable import SpoolKid

struct SpoolFormWeightModeTests {
    private typealias Mode = SpoolFormView.WeightMode

    // MARK: - Reading the field

    @Test func remainingIsReadAsItself() {
        #expect(
            SpoolFormView.netRemaining(
                input: "750", mode: .remaining, initialWeight: "1000", spoolWeight: "238"
            ) == 750
        )
    }

    @Test func usedIsInitialMinusTheEntry() {
        #expect(
            SpoolFormView.netRemaining(
                input: "250", mode: .used, initialWeight: "1000", spoolWeight: "238"
            ) == 750
        )
    }

    /// Measured is no longer a MODE — it is its own row with its own field,
    /// so its conversion has its own function. Still the scale reading, so the
    /// core still comes off.
    @Test func measuredIsGrossAndLosesTheCore() {
        #expect(SpoolFormView.netFromMeasured(measured: "988", spoolWeight: "238") == 750)
    }

    /// No core weight entered means the core weighs nothing, which is the same
    /// assumption the save path makes.
    @Test func measuredWithNoCoreWeightIsTakenAsNet() {
        #expect(SpoolFormView.netFromMeasured(measured: "750", spoolWeight: "") == 750)
    }

    @Test func anUnreadableMeasurementConvertsToNothing() {
        #expect(SpoolFormView.netFromMeasured(measured: "", spoolWeight: "238") == nil)
        #expect(SpoolFormView.netFromMeasured(measured: "abc", spoolWeight: "238") == nil)
    }

    @Test func usedNeedsAnInitialWeightToMeanAnything() {
        #expect(
            SpoolFormView.netRemaining(
                input: "250", mode: .used, initialWeight: "", spoolWeight: "238"
            ) == nil
        )
    }

    @Test func anEmptyFieldReadsAsNothing() {
        for mode in Mode.allCases {
            #expect(
                SpoolFormView.netRemaining(
                    input: "", mode: mode, initialWeight: "1000", spoolWeight: "238"
                ) == nil
            )
        }
    }

    @Test func aCommaDecimalIsAccepted() {
        #expect(
            SpoolFormView.netRemaining(
                input: "750,5", mode: .remaining, initialWeight: "1000", spoolWeight: "0"
            ) == 750.5
        )
    }

    // MARK: - Writing the field

    @Test func remainingShowsWhatIsLeft() {
        #expect(SpoolFormView.weightInputText(for: .remaining, netRemaining: 750, initialWeight: "1000") == "750")
    }

    @Test func usedShowsInitialMinusRemaining() {
        #expect(SpoolFormView.weightInputText(for: .used, netRemaining: 750, initialWeight: "1000") == "250")
    }

    @Test func usedIsBlankWithoutAnInitialWeight() {
        #expect(SpoolFormView.weightInputText(for: .used, netRemaining: 750, initialWeight: "") == "")
    }

    @Test func nothingKnownShowsNothing() {
        for mode in Mode.allCases {
            #expect(SpoolFormView.weightInputText(for: mode, netRemaining: nil, initialWeight: "1000") == "")
        }
    }

    /// Whole grams read as whole grams — "750", never "750.0".
    @Test func aWholeNumberOfGramsHasNoDecimalPoint() {
        #expect(SpoolFormView.weightInputText(for: .remaining, netRemaining: 750.0, initialWeight: "1000") == "750")
        #expect(SpoolFormView.weightInputText(for: .remaining, netRemaining: 750.5, initialWeight: "1000") == "750.5")
    }

    // MARK: - Round trip

    /// Switching Remaining → Used → Remaining must land on the same spool.
    @Test func theThreeModesDescribeOneSpool() {
        let initial = "1000", core = "238"
        let remaining = SpoolFormView.netRemaining(
            input: "750", mode: .remaining, initialWeight: initial, spoolWeight: core
        )
        let asUsed = SpoolFormView.weightInputText(for: .used, netRemaining: remaining, initialWeight: initial)
        #expect(asUsed == "250")

        let backAgain = SpoolFormView.netRemaining(
            input: asUsed, mode: .used, initialWeight: initial, spoolWeight: core
        )
        #expect(backAgain == 750)
    }

    // MARK: - Captions

    /// The whole point of this round: which frame each number is in, said in
    /// the UI rather than only in the docs.
    @Test func everyCaptionNamesItsFrame() {
        #expect(SpoolFormView.weightModeCaption(.remaining).contains("NET"))
        #expect(SpoolFormView.weightModeCaption(.used).contains("NET"))
        #expect(SpoolFormView.measuredWeightCaption.contains("GROSS"))
        #expect(SpoolFormView.initialWeightCaption.contains("NET"))
    }

    /// The owner looked for Used on FilaMan and reported it missing. It had
    /// never been there; what changed was that the picker stopped rendering
    /// once Remaining was its only mode. Absence now explains itself.
    @Test func aSingleModeBackendExplainsWhyThereIsNoChoice() {
        let note = SpoolFormView.singleWeightModeNote("FilaMan")
        #expect(note.contains("FilaMan"))
        #expect(note.lowercased().contains("used weight"))
        #expect(!note.isEmpty)
    }

    @Test func theNoteNamesWhicheverBackendIsAsking() {
        #expect(SpoolFormView.singleWeightModeNote("Spoolman").hasPrefix("Spoolman"))
    }

    @Test func noCaptionIsEmpty() {
        for mode in Mode.allCases {
            #expect(!SpoolFormView.weightModeCaption(mode).isEmpty)
        }
        #expect(!SpoolFormView.initialWeightCaption.isEmpty)
        #expect(!SpoolFormView.spoolWeightCaption.isEmpty)
    }

    // MARK: - R21: an untouched weight field says nothing

    /// The bug this closes. `SpoolFormView` loads a spool's weights into its
    /// fields on appear, so before R21 every save re-asserted them — and the
    /// second of two concurrent edits silently reverted the first.
    @Test func aFieldStillHoldingItsLoadedValueIsIgnored() {
        #expect(SpoolFormView.weightPatch(current: "1000", loaded: "1000") == .ignore)
    }

    @Test func anEditedFieldIsAsserted() {
        #expect(SpoolFormView.weightPatch(current: "900", loaded: "1000") == .set(900))
    }

    /// Creating: nothing was loaded, so everything stated is stated.
    @Test func everyStatedFieldIsAssertedWhenCreating() {
        #expect(SpoolFormView.weightPatch(current: "1000", loaded: "") == .set(1000))
    }

    /// An emptied field is `.ignore`, not `.setNil` — that is what empty has
    /// always meant here, and the form offers no "clear this weight" control.
    /// Reading it as a clear would wipe weights for users who simply blanked a
    /// box.
    @Test func anEmptiedFieldDoesNotClearTheStoredWeight() {
        #expect(SpoolFormView.weightPatch(current: "", loaded: "1000") == .ignore)
        #expect(SpoolFormView.weightPatch(current: "   ", loaded: "1000") == .ignore)
    }

    @Test func gibberishIsNotAWeight() {
        #expect(SpoolFormView.weightPatch(current: "abc", loaded: "1000") == .ignore)
    }

    /// The decimal comma some locales produce must not read as an edit.
    @Test func aCommaDecimalMatchesItsDotEquivalent() {
        #expect(SpoolFormView.weightPatch(current: "1000,5", loaded: "1000.5") == .ignore)
        #expect(SpoolFormView.weightPatch(current: "1000,5", loaded: "1000") == .set(1000.5))
    }

    // MARK: - R21: the weight pair stays indivisible (F31)

    /// Editing the gross figure alone must still state the basis, or
    /// `spoolWeightKeys` refuses both keys and the edit is silently lost.
    @Test func editingTheGrossFigureStatesTheUntouchedBasis() {
        let pair = SpoolFormView.weightPairPatch(
            initialWeight: "900", loadedInitialWeight: "1000",
            spoolWeight: "250", loadedSpoolWeight: "250"
        )

        #expect(pair.initial == .set(900))
        #expect(pair.basis == .set(250))
    }

    /// A spool with no basis at all: stating the gross figure states a zero
    /// basis, which is what FilaMan needs to avoid inheriting the filament's
    /// default and rewriting the number (F31).
    @Test func editingTheGrossFigureWithNoBasisStatesZero() {
        let pair = SpoolFormView.weightPairPatch(
            initialWeight: "900", loadedInitialWeight: "1000",
            spoolWeight: "", loadedSpoolWeight: ""
        )

        #expect(pair.initial == .set(900))
        #expect(pair.basis == .set(0))
    }

    /// Touching neither still says nothing — the pair rule must not turn an
    /// untouched form into a write.
    @Test func touchingNeitherWeightStatesNeither() {
        let pair = SpoolFormView.weightPairPatch(
            initialWeight: "1000", loadedInitialWeight: "1000",
            spoolWeight: "250", loadedSpoolWeight: "250"
        )

        #expect(pair.initial == .ignore)
        #expect(pair.basis == .ignore)
    }

    /// Editing the basis alone travels alone — there is no gross figure to
    /// convert, but the user did change the core weight.
    @Test func editingTheBasisAloneStatesOnlyTheBasis() {
        let pair = SpoolFormView.weightPairPatch(
            initialWeight: "1000", loadedInitialWeight: "1000",
            spoolWeight: "300", loadedSpoolWeight: "250"
        )

        #expect(pair.initial == .ignore)
        #expect(pair.basis == .set(300))
    }

    // MARK: - Used this print (#17)

    /// Renamed from "Used": the lifetime figure it names is the total the
    /// spool has consumed, which the per-print Used field must not be
    /// confused with.
    @Test func lifetimeModeIsCalledTotalUsed() {
        #expect(Mode.used.rawValue == "Total Used")
    }

    @Test func usedThisPrintTakesGramsOffTheLoadedRemaining() {
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "52", base: 812, mode: .remaining, initialWeight: "1000"
            ) == "760"
        )
    }

    /// The same result, stated in the other mode: Total Used is initial minus
    /// what is left, so 1000 - 760.
    @Test func usedThisPrintReadsInTotalUsedMode() {
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "52", base: 812, mode: .used, initialWeight: "1000"
            ) == "240"
        )
    }

    /// Clearing Used puts back the figure the spool was loaded with.
    @Test func clearingUsedRestoresTheLoadedRemaining() {
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "", base: 812, mode: .remaining, initialWeight: "1000"
            ) == "812"
        )
    }

    @Test func usedThisPrintNeedsALoadedRemaining() {
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "52", base: nil, mode: .remaining, initialWeight: "1000"
            ) == nil
        )
    }

    /// Zero, negative and unreadable grams state nothing — the field is left
    /// as the user had it rather than being rewritten from a bad entry.
    /// Total Used cannot state the figure without an Initial Filament Weight,
    /// so Used moves the form to Remaining rather than letting Save drop it.
    @Test func usedThisPrintSwitchesToRemainingWhenTotalUsedCannotStateIt() {
        #expect(
            SpoolFormView.modeForUsedThisPrint(
                used: "52", base: 812, mode: .used, initialWeight: ""
            ) == .remaining
        )
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "52", base: 812, mode: .remaining, initialWeight: ""
            ) == "760"
        )
    }

    /// Loaded remaining above the initial weight is the same unstatable case.
    @Test func usedThisPrintSwitchesWhenTheLoadedRemainingExceedsInitial() {
        #expect(
            SpoolFormView.modeForUsedThisPrint(
                used: "52", base: 1200, mode: .used, initialWeight: "1000"
            ) == .remaining
        )
    }

    @Test func usedThisPrintKeepsTotalUsedWhenItCanStateTheFigure() {
        #expect(
            SpoolFormView.modeForUsedThisPrint(
                used: "52", base: 812, mode: .used, initialWeight: "1000"
            ) == .used
        )
    }

    /// Clearing Used is not an entry to resolve, so it never switches the mode.
    @Test func clearingUsedNeverSwitchesTheMode() {
        #expect(
            SpoolFormView.modeForUsedThisPrint(
                used: "", base: 812, mode: .used, initialWeight: ""
            ) == .used
        )
    }

    /// The takeover rule: text Used itself wrote keeps Used; any other text is
    /// the user typing a figure of their own.
    @Test func aProgrammaticTextEqualToUsedsKeepsUsed() {
        #expect(!SpoolFormView.weightInputTakesOverUsed("760", setByUsed: "760"))
    }

    @Test func aDifferentTextIsATakeoverOfUsed() {
        #expect(SpoolFormView.weightInputTakesOverUsed("700", setByUsed: "760"))
    }

    /// Switching to Total Used with no Initial Filament Weight converts the
    /// figure to "", which Save would drop. Used is then cleared, not kept.
    @Test func aModeSwitchThatCannotStateUsedDropsIt() {
        let converted = SpoolFormView.weightInputText(for: .used, netRemaining: 760, initialWeight: "")
        #expect(!SpoolFormView.usedSurvivesModeChange(convertedText: converted))
    }

    @Test func aModeSwitchThatStatesUsedKeepsIt() {
        let converted = SpoolFormView.weightInputText(for: .used, netRemaining: 760, initialWeight: "1000")
        #expect(SpoolFormView.usedSurvivesModeChange(convertedText: converted))
    }

    @Test func withNoUsedFigureThereIsNothingToTakeOver() {
        #expect(!SpoolFormView.weightInputTakesOverUsed("700", setByUsed: nil))
    }

    @Test func aUsedEntryThatIsNotPositiveGramsStatesNothing() {
        for used in ["0", "-5", "abc"] {
            #expect(
                SpoolFormView.weightInputAfterUsedThisPrint(
                    used: used, base: 812, mode: .remaining, initialWeight: "1000"
                ) == nil
            )
        }
    }

    /// Total Used with a Used larger than what remains: the field reads 1088 g
    /// against an initial 1000 g. The preview says "less than 0 g", so Save
    /// must refuse rather than write a used figure above the initial weight.
    @Test func saveRefusesAUsedThatWouldLeaveLessThanZero() {
        #expect(
            SpoolFormView.weightInputAfterUsedThisPrint(
                used: "900", base: 812, mode: .used, initialWeight: "1000"
            ) == "1088"
        )
        #expect(
            SpoolFormView.refusesNegativeAdjustment(
                SpoolFormView.adjustmentPreview(used: "900", measured: "", loadedRemaining: 812, spoolWeight: "")
            )
        )
    }

    @Test func saveAllowsAUsedThatLeavesWeightAboveZero() {
        #expect(
            !SpoolFormView.refusesNegativeAdjustment(
                SpoolFormView.adjustmentPreview(used: "52", measured: "", loadedRemaining: 812, spoolWeight: "")
            )
        )
    }

    /// A Measured reading below the empty spool weight is refused the same way,
    /// whatever the Input Mode.
    @Test func saveRefusesAMeasuredReadingThatLeavesLessThanZero() {
        #expect(
            SpoolFormView.refusesNegativeAdjustment(
                SpoolFormView.adjustmentPreview(used: "", measured: "100", loadedRemaining: 812, spoolWeight: "238")
            )
        )
    }

    @Test func saveWithNoAdjustmentIsNotRefusedForNegativeWeight() {
        #expect(!SpoolFormView.refusesNegativeAdjustment(nil))
    }
}
