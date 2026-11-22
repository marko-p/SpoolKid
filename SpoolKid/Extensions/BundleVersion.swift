//
//  BundleVersion.swift
//  SpoolKid
//
//  Purpose: One reader for the marketing version string, shared by the
//  Settings screen and the support prompts' upgrade trigger.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

extension Bundle {
    /// `CFBundleShortVersionString`, e.g. "1.8". Callers supply their own
    /// placeholder: Settings shows an em dash, the support policy uses "" to
    /// mean "no version seen yet".
    nonisolated var appVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
