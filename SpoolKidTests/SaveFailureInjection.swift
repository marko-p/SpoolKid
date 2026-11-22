//
//  SaveFailureInjection.swift
//  SpoolKidTests
//
//  Purpose: Makes an in-memory SwiftData save fail on demand, so a writer's
//  failure branch can be tested against a real `ModelContext` rather than a
//  mock. Two test-only models: the child's to-one parent is mandatory, and
//  the parent's delete rule nullifies it, so deleting the parent leaves a
//  pending change the store refuses and the next `save()` on that context
//  throws.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData
@testable import SpoolKid

@Model
final class SaveBlockerParent {
    @Relationship(deleteRule: .nullify, inverse: \SaveBlockerChild.parent)
    var children: [SaveBlockerChild] = []

    init() {}
}

@Model
final class SaveBlockerChild {
    /// Non-optional, so the store treats it as mandatory: nullified by its
    /// parent's delete, the child no longer validates.
    var parent: SaveBlockerParent

    init(parent: SaveBlockerParent) {
        self.parent = parent
    }
}

@MainActor
enum SaveFailureInjection {
    /// An in-memory context over `models` plus the two blocker models.
    static func makeContext(for models: [any PersistentModel.Type]) throws -> ModelContext {
        let schema = Schema(models + [SaveBlockerParent.self, SaveBlockerChild.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Leaves `context` holding a delete the store refuses, so its next
    /// `save()` throws. A `rollback()` discards it with everything else.
    static func arm(_ context: ModelContext) throws {
        let parent = SaveBlockerParent()
        context.insert(parent)
        context.insert(SaveBlockerChild(parent: parent))
        try context.save()
        context.delete(parent)
    }

    /// Gives every blocker child a fresh parent, so the context can save
    /// again without discarding anything else that is pending — the state a
    /// second writer meets when the first left its failed change behind.
    static func disarm(_ context: ModelContext) throws {
        for child in try context.fetch(FetchDescriptor<SaveBlockerChild>()) {
            let parent = SaveBlockerParent()
            context.insert(parent)
            child.parent = parent
        }
    }
}
