//
//  TagDumpDiff.swift
//  SpoolKid
//
//  Purpose: Say which pages moved between two dumps of one tag.
//
//  This is what turns "print from this spool and scan it again" into an
//  answer. It answered the question it was built for on 2026-09-12: a factory
//  Anycubic tag dumped before and after a print showed no changed pages, so
//  the ACE writes nothing back (issue #5).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagDumpDiff {

    /// One page that differs. A nil side means that dump did not reach this
    /// page — two walks of one tag can end at different places.
    nonisolated struct PageChange: Equatable {
        let page: Int
        let before: String?
        let after: String?
    }

    static func changes(from before: TagDump, to after: TagDump) -> [PageChange] {
        let pageCount = max(before.pages.count, after.pages.count)
        return (0..<max(pageCount, 0)).compactMap { page in
            let old = page < before.pages.count ? before.pages[page] : nil
            let new = page < after.pages.count ? after.pages[page] : nil
            guard old != new else { return nil }
            return PageChange(page: page, before: old, after: new)
        }
    }
}
