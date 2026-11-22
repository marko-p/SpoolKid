//
//  LocalIdSequence.swift
//  SpoolKid
//
//  Purpose: SwiftData model that holds a per-kind monotonic counter for
//  allocating persistent local ids. One row per kind (vendor, filament, spool).
//  The counter is incremented inside the same ModelContext write that inserts
//  the row, so allocation is transactional and resets with the store.
//
//  NOTE: the kind column is deliberately NOT named `entity` — that collides with
//  CoreData's reserved `NSManagedObject.entity` keypath and makes any
//  `#Predicate` over it trap at runtime (uncatchable, crashes the process).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData

@Model
final class LocalIdSequence {
    @Attribute(.unique) var kind: String
    var next: Int

    init(kind: String, next: Int = 1) {
        self.kind = kind
        self.next = next
    }
}
