//
//  ReleaseVersion.swift
//  SpoolKid
//
//  Purpose: Orders marketing version strings numerically, component by
//  component, so "0.17" ranks above "0.9".
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A `CFBundleShortVersionString` compared the way a human reads it.
///
/// SpoolKid's `MARKETING_VERSION` is two-component ("0.17"), so lexicographic
/// comparison would rank "0.9" above it. Components are compared numerically,
/// and a version with fewer of them is padded with zeroes.
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which would otherwise make the synthesized `Equatable` unusable from
/// nonisolated test contexts — the opt-out `SupportPromptState` already carries.
nonisolated struct ReleaseVersion: Comparable, Equatable, Hashable, Sendable {

    /// Normalised: trailing zeroes are dropped, so "0.17.0" and "0.17" are the
    /// same version and synthesized `Equatable` says so.
    let components: [Int]

    /// A component that is not an integer reads as zero rather than failing —
    /// a malformed version must never cost the user their release notes.
    init(_ string: String) {
        var parts = string
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        while parts.count > 1 && parts.last == 0 {
            parts.removeLast()
        }
        components = parts
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
