//
//  SearchQuery.swift
//  SpoolKid
//
//  Purpose: One rule for what a typed search query matches, shared by every
//  list that offers a search field.
//
//  Why it exists: each list used to test the WHOLE query string against each
//  field on its own — `name.contains(q) || vendor.contains(q) || …`. That
//  answers "AzureFilm" and "PLA" but not "AzureFilm PLA", because no single
//  field holds both, so the most natural way to narrow a long list returned
//  nothing at all (bench pass 2026-09-04).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SearchQuery {

    /// True when every whitespace-separated token in `query` appears in at
    /// least one of `fields`. Tokens may come from DIFFERENT fields and in any
    /// order, which is how people actually type: manufacturer then material,
    /// or material then colour.
    ///
    /// A blank query matches everything — callers render the unfiltered list.
    static func matches(_ query: String, in fields: [String?]) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }

        let haystack = fields.compactMap { $0 }.filter { !$0.isEmpty }
        guard !haystack.isEmpty else { return false }

        return tokens.allSatisfy { token in
            haystack.contains { field in
                field.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
        }
    }
}
