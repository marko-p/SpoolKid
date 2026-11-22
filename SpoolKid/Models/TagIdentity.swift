//
//  TagIdentity.swift
//  SpoolKid
//
//  Purpose: How SpoolKid identifies a spool from a tag — by tag links, by the
//  spool ID written on the tag, or by neither — and the one-time decision an
//  upgrade takes. Pure. Tag links are read in every mode; the spool ID on a
//  tag identifies a spool only in Spool ID mode.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagIdentityMode: String, CaseIterable, Sendable {
    case tagLinks, spoolID, neither

    var label: String {
        switch self {
        case .tagLinks: "Tag Links"
        case .spoolID: "Spool ID on Tag"
        case .neither: "Neither"
        }
    }
}

/// The ONE answer to "how does SpoolKid identify a spool from a tag right
/// now". Every site that used to read `write_spool_id`, the SpoolLink switch
/// or the store's two Bool link gates asks this instead. Links and the
/// on-device ledger are READ in every mode; this decides what is written and
/// whether a tag's `spool_id` counts.
nonisolated struct TagIdentityPolicy: Equatable, Sendable {
    let mode: TagIdentityMode
    /// Stores a NEW link goes to. Empty unless `mode == .tagLinks` and the
    /// active backend has somewhere to keep one.
    let linkTargets: Set<TagStore>

    var honorsSpoolID: Bool { mode == .spoolID }
    var writesSpoolID: Bool { mode == .spoolID }
    var writesLinks: Bool { !linkTargets.isEmpty }
    /// What the mode amounts to here: Tag Links with no store is Neither.
    var effectiveMode: TagIdentityMode { mode == .tagLinks && linkTargets.isEmpty ? .neither : mode }

    /// Spec 4: whether a NEW filament link may go to `store`, the backend's
    /// filament store (`SpoolDataRepository.filamentTagStore`). Only where it
    /// is a link target: Tag Links, and on Spoolman only while Spoolman Tags
    /// is on, because `card_uids` is spool-only there.
    func writesFilamentLinks(store: TagStore?) -> Bool {
        guard let store else { return false }
        return linkTargets.contains(store)
    }

    static func resolve(
        mode: TagIdentityMode, available: Set<TagStore>, nativeEnabled: Bool, spoolLinkEnabled: Bool,
        filamanTagsEnabled: Bool = false
    ) -> TagIdentityPolicy {
        guard mode == .tagLinks, !available.isEmpty else { return TagIdentityPolicy(mode: mode, linkTargets: []) }
        return TagIdentityPolicy(
            mode: mode,
            linkTargets: TagWriteTargets.resolve(
                available: available, nativeEnabled: nativeEnabled, spoolLinkEnabled: spoolLinkEnabled,
                filamanTagsEnabled: filamanTagsEnabled
            )
        )
    }

    /// The policy as the stored settings say now — the one reader of
    /// `tag_identity_mode` and the two Tag Identity store switches. While the
    /// mode is unset it answers with the upgrade rule and persists nothing;
    /// the decision is persisted elsewhere, once (`SpoolDataStore`).
    static func current(
        available: Set<TagStore>, storesAreNew: Bool = false, defaults: UserDefaults = .standard
    ) -> TagIdentityPolicy {
        let nativeEnabled = defaults.object(forKey: AppConfig.spoolmanNativeTagsEnabledKey) as? Bool ?? true
        let spoolLinkEnabled = defaults.bool(forKey: AppConfig.spoolmanPersistCardUIDKey)
        // FilaMan reads its own two switches; the Spoolman keys are Spoolman's.
        let isFilaMan = available.contains(.filamanTags)
        let stored = defaults.string(forKey: AppConfig.tagIdentityModeKey).flatMap(TagIdentityMode.init(rawValue:))
        let mode = stored ?? TagIdentityMigration.decide(
            isFreshInstall: !defaults.bool(forKey: AppConfig.hasCompletedWelcomeKey),
            writeSpoolID: defaults.object(forKey: AppConfig.legacyWriteSpoolIdKey) as? Bool ?? true,
            spoolLinkEnabled: spoolLinkEnabled,
            nativeEnabled: nativeEnabled,
            available: available,
            storesAreNew: storesAreNew
        ).mode
        return resolve(
            mode: mode, available: available, nativeEnabled: nativeEnabled,
            spoolLinkEnabled: isFilaMan ? FilaManTagSwitches.spoolLinkEnabled(defaults) : spoolLinkEnabled,
            filamanTagsEnabled: isFilaMan && FilaManTagSwitches.tagsEnabled(defaults)
        )
    }
}

/// The two FilaMan Tags switches, read the same way everywhere. Off by
/// default for an upgrader; a fresh install turns `tagsEnabled` on.
nonisolated enum FilaManTagSwitches {
    static func tagsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: AppConfig.filamanTagsEnabledKey)
    }

    static func spoolLinkEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppConfig.filamanSpoolLinkEnabledKey) as? Bool ?? true
    }
}

/// The one-time choice an upgrade makes from the settings it replaces.
nonisolated enum TagIdentityMigration {
    struct Decision: Equatable, Sendable {
        let mode: TagIdentityMode
        /// Both Write Spool ID and linking were on: say what changed.
        let explain: Bool
    }

    /// `available`: the tag stores the active backend keeps now. A switch
    /// counts only where it could have taken effect: SpoolLink was inert
    /// where there is no store at all, and Spoolman Tags defaulted to on
    /// everywhere. `storesAreNew`: the backend's store did not exist before
    /// this release — the on-device Library's (spec 2). No switch took
    /// effect there, and an upgrader who wrote no spool IDs starts on Tag
    /// Links, which only adds.
    static func decide(
        isFreshInstall: Bool, writeSpoolID: Bool, spoolLinkEnabled: Bool, nativeEnabled: Bool,
        available: Set<TagStore>, storesAreNew: Bool = false
    ) -> Decision {
        if isFreshInstall { return Decision(mode: .tagLinks, explain: false) }
        if storesAreNew { return Decision(mode: writeSpoolID ? .spoolID : .tagLinks, explain: false) }
        let linking = (spoolLinkEnabled && !available.isEmpty)
            || (nativeEnabled && available.contains(.spoolmanTags))
        switch (writeSpoolID, linking) {
        case (true, true): return Decision(mode: .tagLinks, explain: true)
        case (false, true): return Decision(mode: .tagLinks, explain: false)
        case (true, false): return Decision(mode: .spoolID, explain: false)
        case (false, false): return Decision(mode: .neither, explain: false)
        }
    }

    /// At launch, before any view: a new install starts on Tag Links. Deciding
    /// later would misread it — a new user who connects a 0.27 server after
    /// the welcome guide would look like an upgrader with both on.
    static func persistFreshInstallIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: AppConfig.tagIdentityModeKey) == nil,
              !defaults.bool(forKey: AppConfig.hasCompletedWelcomeKey)
        else { return }
        defaults.set(TagIdentityMode.tagLinks.rawValue, forKey: AppConfig.tagIdentityModeKey)
        defaults.set(true, forKey: AppConfig.filamanTagsEnabledKey)
    }

    /// Once, when the active backend's tag stores are known: persist the
    /// upgrade's mode and, when both were on, owe the explanation. True when
    /// it decided now. The pending flag is written BEFORE the mode, so the
    /// explanation can never be lost between the two writes.
    @discardableResult
    static func persistUpgradeIfNeeded(
        available: Set<TagStore>, storesAreNew: Bool = false, storesKnown: Bool, defaults: UserDefaults = .standard
    ) -> Bool {
        guard storesKnown, defaults.string(forKey: AppConfig.tagIdentityModeKey) == nil else { return false }
        // The same rule `TagIdentityPolicy.current` answers with, so the
        // persisted decision never contradicts the provisional one.
        let decision = decide(
            isFreshInstall: !defaults.bool(forKey: AppConfig.hasCompletedWelcomeKey),
            writeSpoolID: defaults.object(forKey: AppConfig.legacyWriteSpoolIdKey) as? Bool ?? true,
            spoolLinkEnabled: defaults.bool(forKey: AppConfig.spoolmanPersistCardUIDKey),
            nativeEnabled: defaults.object(forKey: AppConfig.spoolmanNativeTagsEnabledKey) as? Bool ?? true,
            available: available,
            storesAreNew: storesAreNew
        )
        if decision.explain { defaults.set(true, forKey: AppConfig.tagIdentityExplanationPendingKey) }
        defaults.set(decision.mode.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return true
    }
}
