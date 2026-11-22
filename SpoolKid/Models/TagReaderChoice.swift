//
//  TagReaderChoice.swift
//  SpoolKid
//
//  Purpose: Which reader reads or writes a tag: the iPhone, or a toolhead's
//  reader on the printer. Never stored; each operation takes it afresh.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagReader: Equatable, Hashable, Sendable {
    case iPhone
    /// A toolhead's index, 0-based.
    case toolhead(Int)
}
