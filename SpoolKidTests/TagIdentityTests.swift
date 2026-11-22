//
//  TagIdentityTests.swift
//  SpoolKidTests
//
//  The one policy every tag-identity question goes through (spec
//  2026-10-09-tag-identity-mode-design.md §1, §5).
//

import Foundation
import Testing
@testable import SpoolKid

struct TagIdentityPolicyTests {
    private let both: Set<TagStore> = [.cardUIDs, .spoolmanTags]

    @Test func tagLinksOnANativeTagServerFollowTheSwitches() {
        let p = TagIdentityPolicy.resolve(mode: .tagLinks, available: both, nativeEnabled: true, spoolLinkEnabled: false)
        #expect(p.linkTargets == [.spoolmanTags])
        #expect(p.writesLinks && !p.writesSpoolID && !p.honorsSpoolID)
        #expect(p.effectiveMode == .tagLinks)
    }

    /// Decision 7: on a single-store backend Tag Links IS that store, whatever
    /// the SpoolLink switch says.
    @Test func tagLinksOnASingleStoreBackendIsThatStore() {
        let p = TagIdentityPolicy.resolve(mode: .tagLinks, available: [.cardUIDs], nativeEnabled: true, spoolLinkEnabled: false)
        #expect(p.linkTargets == [.cardUIDs])
    }

    @Test func tagLinksWithNowhereToLinkBehavesAsNeither() {
        let p = TagIdentityPolicy.resolve(mode: .tagLinks, available: [], nativeEnabled: true, spoolLinkEnabled: true)
        #expect(p.linkTargets.isEmpty)
        #expect(!p.writesLinks && !p.writesSpoolID && !p.honorsSpoolID)
        #expect(p.effectiveMode == .neither)
    }

    @Test(arguments: [Set<TagStore>(), [.cardUIDs], [.cardUIDs, .spoolmanTags]])
    func spoolIDWritesTheIDAndNoLinks(available: Set<TagStore>) {
        let p = TagIdentityPolicy.resolve(mode: .spoolID, available: available, nativeEnabled: true, spoolLinkEnabled: true)
        #expect(p.linkTargets.isEmpty)
        #expect(p.writesSpoolID && p.honorsSpoolID && !p.writesLinks)
        #expect(p.effectiveMode == .spoolID)
    }

    @Test(arguments: [Set<TagStore>(), [.cardUIDs], [.cardUIDs, .spoolmanTags]])
    func neitherWritesNothing(available: Set<TagStore>) {
        let p = TagIdentityPolicy.resolve(mode: .neither, available: available, nativeEnabled: true, spoolLinkEnabled: true)
        #expect(p.linkTargets.isEmpty)
        #expect(!p.writesSpoolID && !p.honorsSpoolID && !p.writesLinks)
    }

    @Test func modeLabels() {
        #expect(TagIdentityMode.allCases.map(\.label) == ["Tag Links", "Spool ID on Tag", "Neither"])
    }

    // MARK: - current(available:defaults:)

    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        for (key, value) in values { d.set(value, forKey: key) }
        return d
    }

    @Test func aStoredModeWins() {
        let d = defaults([AppConfig.tagIdentityModeKey: "neither", AppConfig.hasCompletedWelcomeKey: true])
        #expect(TagIdentityPolicy.current(available: both, defaults: d).mode == .neither)
    }

    /// Unset mode: the provisional answer is the upgrade rule, never persisted.
    @Test func anUnsetModeAnswersWithTheUpgradeRule() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.legacyWriteSpoolIdKey: true])
        #expect(TagIdentityPolicy.current(available: [.cardUIDs], defaults: d).mode == .spoolID)
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == nil)
    }

    @Test func aMissingLegacyKeyCountsAsItsOldDefaultOn() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true])
        #expect(TagIdentityPolicy.current(available: [.cardUIDs], defaults: d).mode == .spoolID)
    }

    // MARK: - FilaMan Tags

    private let filaman: Set<TagStore> = [.cardUIDs, .filamanTags]

    @Test func filamanTargetsFollowBothSwitches() {
        #expect(TagWriteTargets.resolve(available: filaman, nativeEnabled: true, spoolLinkEnabled: true, filamanTagsEnabled: false) == [.cardUIDs])
        #expect(TagWriteTargets.resolve(available: filaman, nativeEnabled: true, spoolLinkEnabled: true, filamanTagsEnabled: true) == [.cardUIDs, .filamanTags])
        #expect(TagWriteTargets.resolve(available: filaman, nativeEnabled: true, spoolLinkEnabled: false, filamanTagsEnabled: true) == [.filamanTags])
        #expect(TagWriteTargets.resolve(available: filaman, nativeEnabled: true, spoolLinkEnabled: false, filamanTagsEnabled: false) == [.cardUIDs])
    }

    /// The FilaMan switches are their own keys: the Spoolman SpoolLink key,
    /// left on or off, is not read on a FilaMan backend.
    @Test func filamanPolicyReadsItsOwnKeys() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.tagIdentityModeKey: "tagLinks"])
        #expect(TagIdentityPolicy.current(available: filaman, defaults: d).linkTargets == [.cardUIDs])
        d.set(true, forKey: AppConfig.filamanTagsEnabledKey)
        #expect(TagIdentityPolicy.current(available: filaman, defaults: d).linkTargets == [.cardUIDs, .filamanTags])
        d.set(false, forKey: AppConfig.filamanSpoolLinkEnabledKey)
        #expect(TagIdentityPolicy.current(available: filaman, defaults: d).linkTargets == [.filamanTags])
    }

    @Test func filamanSwitchesDefaultAsSpecified() {
        let d = defaults([:])
        #expect(FilaManTagSwitches.tagsEnabled(d) == false)
        #expect(FilaManTagSwitches.spoolLinkEnabled(d) == true)
    }

    @Test func aFreshInstallTurnsFilamanTagsOn() {
        let d = defaults([:])
        TagIdentityMigration.persistFreshInstallIfNeeded(defaults: d)
        #expect(d.bool(forKey: AppConfig.filamanTagsEnabledKey) == true)
        #expect(FilaManTagSwitches.tagsEnabled(d))
    }

    @Test func anUpgradeLeavesFilamanTagsOff() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true])
        TagIdentityMigration.persistFreshInstallIfNeeded(defaults: d)
        #expect(d.object(forKey: AppConfig.filamanTagsEnabledKey) == nil)
        #expect(FilaManTagSwitches.tagsEnabled(d) == false)
    }
}

struct TagIdentityMigrationTests {
    /// `storeAvailable: false` is a backend with no store at all;
    /// `storesAreNew: true` is the Library since spec 2.
    private func decide(
        fresh: Bool = false, writeSpoolID: Bool, spoolLink: Bool, native: Bool = true,
        nativeAvailable: Bool = false, storeAvailable: Bool = true, storesAreNew: Bool = false
    ) -> TagIdentityMigration.Decision {
        let available: Set<TagStore> = !storeAvailable ? [] : nativeAvailable ? [.cardUIDs, .spoolmanTags] : [.cardUIDs]
        return TagIdentityMigration.decide(
            isFreshInstall: fresh, writeSpoolID: writeSpoolID, spoolLinkEnabled: spoolLink,
            nativeEnabled: native, available: available, storesAreNew: storesAreNew
        )
    }

    @Test func aFreshInstallStartsOnTagLinksSilently() {
        #expect(decide(fresh: true, writeSpoolID: true, spoolLink: true) == .init(mode: .tagLinks, explain: false))
    }

    @Test func bothOnLandsOnTagLinksAndExplains() {
        #expect(decide(writeSpoolID: true, spoolLink: true) == .init(mode: .tagLinks, explain: true))
    }

    /// Spoolman Tags defaulted to on everywhere; it counts only where it took effect.
    @Test func nativeTagsCountOnlyWhereTheServerKeepsThem() {
        #expect(decide(writeSpoolID: true, spoolLink: false, nativeAvailable: true) == .init(mode: .tagLinks, explain: true))
        #expect(decide(writeSpoolID: true, spoolLink: false, nativeAvailable: false) == .init(mode: .spoolID, explain: false))
        #expect(decide(writeSpoolID: true, spoolLink: false, native: false, nativeAvailable: true) == .init(mode: .spoolID, explain: false))
    }

    /// The SpoolLink switch was inert where no store existed (the Library);
    /// left on from an earlier server, it counts for nothing there.
    @Test func aSpoolLinkSwitchWithNoStoreCountsForNothing() {
        #expect(decide(writeSpoolID: true, spoolLink: true, storeAvailable: false) == .init(mode: .spoolID, explain: false))
        #expect(decide(writeSpoolID: false, spoolLink: true, storeAvailable: false) == .init(mode: .neither, explain: false))
    }

    @Test func linkingOnlyKeepsTagLinks() {
        #expect(decide(writeSpoolID: false, spoolLink: true) == .init(mode: .tagLinks, explain: false))
    }

    @Test func neitherOnIsNeither() {
        #expect(decide(writeSpoolID: false, spoolLink: false) == .init(mode: .neither, explain: false))
    }

    /// The Library's store is new in this release (spec 2): no switch took
    /// effect there, so an upgrader who wrote no spool IDs starts on Tag
    /// Links, which only adds — silently.
    @Test func aLibraryUpgraderWhoWroteNoSpoolIDsStartsOnTagLinks() {
        #expect(decide(writeSpoolID: false, spoolLink: false, storesAreNew: true) == .init(mode: .tagLinks, explain: false))
        #expect(decide(writeSpoolID: false, spoolLink: true, storesAreNew: true) == .init(mode: .tagLinks, explain: false))
    }

    /// One who wrote spool IDs keeps them; a SpoolLink switch left on from an
    /// earlier server counts for nothing, so there is nothing to explain.
    @Test func aLibraryUpgraderWhoWroteSpoolIDsKeepsSpoolID() {
        #expect(decide(writeSpoolID: true, spoolLink: false, storesAreNew: true) == .init(mode: .spoolID, explain: false))
        #expect(decide(writeSpoolID: true, spoolLink: true, storesAreNew: true) == .init(mode: .spoolID, explain: false))
    }

    @Test func aFreshInstallStartsOnTagLinksOnTheLibraryToo() {
        #expect(decide(fresh: true, writeSpoolID: true, spoolLink: false, storesAreNew: true) == .init(mode: .tagLinks, explain: false))
    }

    @Test func aLibraryUpgradeWithSpoolIDsOffPersistsTagLinks() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.legacyWriteSpoolIdKey: false])
        #expect(TagIdentityMigration.persistUpgradeIfNeeded(
            available: [.cardUIDs], storesAreNew: true, storesKnown: true, defaults: d
        ))
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(d.bool(forKey: AppConfig.tagIdentityExplanationPendingKey) == false)
    }

    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        for (key, value) in values { d.set(value, forKey: key) }
        return d
    }

    @Test func aFreshInstallIsDecidedAtLaunch() {
        let d = defaults([:])
        TagIdentityMigration.persistFreshInstallIfNeeded(defaults: d)
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(d.bool(forKey: AppConfig.tagIdentityExplanationPendingKey) == false)
    }

    @Test func anUpgraderIsNotTouchedAtLaunch() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true])
        TagIdentityMigration.persistFreshInstallIfNeeded(defaults: d)
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == nil)
    }

    @Test func anUpgradeWaitsUntilTheStoresAreKnown() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.spoolmanPersistCardUIDKey: true])
        #expect(!TagIdentityMigration.persistUpgradeIfNeeded(available: [], storesKnown: false, defaults: d))
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == nil)
    }

    @Test func anUpgradeWithBothOnPersistsAndOwesTheExplanation() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.spoolmanPersistCardUIDKey: true])
        #expect(TagIdentityMigration.persistUpgradeIfNeeded(available: [.cardUIDs], storesKnown: true, defaults: d))
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(d.bool(forKey: AppConfig.tagIdentityExplanationPendingKey))
    }

    /// "Reset All Data" leaves an app that has never been welcomed; the
    /// persisted decision answers it as `current` does — a new install.
    @Test func anUnwelcomedInstallIsDecidedAsANewOne() {
        let d = defaults([:])
        #expect(TagIdentityMigration.persistUpgradeIfNeeded(available: [], storesKnown: true, defaults: d))
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(d.bool(forKey: AppConfig.tagIdentityExplanationPendingKey) == false)
    }

    @Test func theDecisionRunsOnce() {
        let d = defaults([AppConfig.hasCompletedWelcomeKey: true, AppConfig.tagIdentityModeKey: "spoolID"])
        #expect(!TagIdentityMigration.persistUpgradeIfNeeded(available: [.cardUIDs], storesKnown: true, defaults: d))
        #expect(d.string(forKey: AppConfig.tagIdentityModeKey) == "spoolID")
    }
}
