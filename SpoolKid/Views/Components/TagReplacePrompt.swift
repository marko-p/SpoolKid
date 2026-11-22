//
//  TagReplacePrompt.swift
//  SpoolKid
//
//  Purpose: The Replace Tag / Cancel dialog every person-driven link point
//  shows when FilaMan Tags is the only store a link goes to. FilaMan keeps one
//  tag per spool, so linking a second one means giving up the first.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A link that would replace the spool's current tag, waiting on the person.
nonisolated struct TagReplaceRequest: Identifiable {
    let id = UUID()
    /// The tag about to be linked. Empty for a write whose tag ID is not known
    /// until the write has finished.
    let uid: String
    /// The spool the link goes to; nil for an Add section not saved yet.
    let spool: Spool?
    /// What the prompt calls the spool.
    let spoolTitle: String
    /// The tag the spool holds now, which Replace gives up.
    let existing: String

    /// What the prompt calls a spool that is not saved yet.
    static let unsavedSpoolTitle = "This new spool"

    init(uid: String, spool: Spool, existing: String) {
        self.uid = uid
        self.spool = spool
        self.spoolTitle = spool.listTitle
        self.existing = existing
    }

    private init(uid: String, unsavedExisting existing: String) {
        self.uid = uid
        self.spool = nil
        self.spoolTitle = Self.unsavedSpoolTitle
        self.existing = existing
    }

    /// A scan-link whose tag ID is known: nil when nothing is in the way.
    static func linking(uid: String, to spool: Spool, targets: Set<TagStore>) -> TagReplaceRequest? {
        TagLinkService.replacementConflict(uid: uid, spool: spool, targets: targets)
            .map { TagReplaceRequest(uid: uid, spool: spool, existing: $0) }
    }

    /// A tag scanned into the spool form's Linked Tags list. `spool` is the
    /// store's current copy of the spool the section edits, nil in an Add
    /// section before it is saved. Nothing is stored for that one yet, but
    /// its list is what the create will link: with FilaMan Tags the only
    /// store it links one tag, so a section that already `listed` another
    /// asks too.
    static func scanning(
        uid: String, into spool: Spool?, listed: [String] = [], targets: Set<TagStore>
    ) -> TagReplaceRequest? {
        if let spool { return linking(uid: uid, to: spool, targets: targets) }
        guard targets == [.filamanTags] else { return nil }
        let normalized = SpoolMappingService.normalizeUID(uid)
        let listedNormalized = listed.map(SpoolMappingService.normalizeUID)
        guard !listedNormalized.contains(normalized),
              let existing = listedNormalized.first(where: { !$0.isEmpty }) else { return nil }
        return TagReplaceRequest(uid: uid, unsavedExisting: existing)
    }

    /// A write-then-link, checked BEFORE the write starts. When the tag's ID is
    /// not known yet (`knownUID == nil`) the new tag cannot be the held one
    /// unless it is being rewritten, so the pre-write condition is "the spool
    /// holds any tag at all" while FilaMan Tags is the only store. That can ask
    /// once more than strictly needed when the same tag is rewritten; asking is
    /// the safe side of that.
    static func writing(spool: Spool, knownUID: String?, targets: Set<TagStore>) -> TagReplaceRequest? {
        if let knownUID, !knownUID.isEmpty {
            return linking(uid: knownUID, to: spool, targets: targets)
        }
        guard targets == [.filamanTags], let existing = spool.mappedCardUIDs.first else { return nil }
        return TagReplaceRequest(uid: "", spool: spool, existing: existing)
    }
}

private struct TagReplacePromptModifier: ViewModifier {
    @Binding var request: TagReplaceRequest?
    let onReplace: (TagReplaceRequest) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            TagStoreText.replacePromptTitle,
            isPresented: Binding(
                get: { request != nil },
                set: { if !$0 { request = nil } }
            ),
            titleVisibility: .visible,
            presenting: request
        ) { pending in
            Button("Replace Tag", role: .destructive) { onReplace(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(TagStoreText.replacePromptMessage(spool: pending.spoolTitle, existing: pending.existing))
        }
    }
}

extension View {
    /// Attach to the control that started the link, so the dialog anchors to it.
    func tagReplacePrompt(
        _ request: Binding<TagReplaceRequest?>, onReplace: @escaping (TagReplaceRequest) -> Void
    ) -> some View {
        modifier(TagReplacePromptModifier(request: request, onReplace: onReplace))
    }
}
