//
//  DiagnosticsPreference.swift
//  SpoolKid
//
//  Purpose: Fold the old per-feature OCR-archive switch into the one
//  diagnostics switch, once, at launch. Pure over an injected `UserDefaults`
//  so the migration can be tested rather than reasoned about — a migration
//  that silently turns a released opt-in back off is the kind of thing nobody
//  reports, they just stop contributing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum DiagnosticsPreference {

    /// Carries a user who had `save_ocr_archives` on into the unified switch.
    ///
    /// The legacy key was registered with a default of `false`, so a stored
    /// `true` can only have come from the user — no "was it explicitly set"
    /// check is needed. The key is then removed, which is also what makes this
    /// idempotent: a later launch finds nothing to migrate, so a tester who
    /// turns diagnostics back off does not have it switched on again.
    ///
    /// Deliberately one-way. Diagnostics being ON is never migrated back into
    /// the legacy key, because nothing reads it any more.
    static func migrateLegacyOCRArchiveSwitch(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppConfig.saveOCRArchivesKey) != nil else { return }
        if defaults.bool(forKey: AppConfig.saveOCRArchivesKey) {
            defaults.set(true, forKey: AppConfig.diagnosticsEnabledKey)
        }
        defaults.removeObject(forKey: AppConfig.saveOCRArchivesKey)
    }
}
