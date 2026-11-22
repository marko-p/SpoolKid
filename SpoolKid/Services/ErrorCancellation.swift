//
//  ErrorCancellation.swift
//  SpoolKid
//
//  Purpose: Whether an error only means the work was cancelled — a closed
//  screen, not a failure.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

extension Error {
    /// True for Swift task cancellation and a cancelled URLSession load.
    nonisolated var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
