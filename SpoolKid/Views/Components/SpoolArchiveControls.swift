//
//  SpoolArchiveControls.swift
//  SpoolKid
//
//  Purpose: Archive, or for an archived spool Unarchive and Delete Spool
//  Permanently. Delete is offered only once a spool is archived (owner,
//  2026-11-03). Shared by the spool form and the Spool page; the caller runs
//  each write and reports its outcome.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolArchiveControls: View {
    let spool: Spool
    @ObservedObject var store: SpoolDataStore
    let confirmBeforeDelete: Bool
    /// Runs a write: its failure-alert title, the fallback failure text, and
    /// the write itself.
    let run: (_ failureTitle: String, _ fallback: String, _ write: @escaping () async -> Bool) -> Void

    var body: some View {
        Group { controls }.needsServer()
    }

    @ViewBuilder private var controls: some View {
        if spool.archived == true {
            Button {
                run("Could Not Unarchive Spool", "The spool could not be unarchived.") {
                    await store.setSpoolArchived(id: spool.id, archived: false)
                }
            } label: {
                Label("Unarchive Spool", systemImage: "arrow.uturn.up")
                    .frame(maxWidth: .infinity)
            }
            DestructiveFormButton(
                title: "Delete Spool Permanently",
                confirmTitle: "Delete Spool?",
                confirmMessage: "\(spool.filament.name ?? "This spool") will be permanently deleted from \(store.capabilities.storageNoun). This cannot be undone.",
                confirmBeforeDelete: confirmBeforeDelete
            ) {
                run("Could Not Delete Spool", "The spool could not be deleted.") {
                    await store.deleteSpool(id: spool.id)
                }
            }
        } else {
            DestructiveFormButton(
                title: "Archive Spool",
                confirmTitle: "Archive Spool?",
                confirmMessage: "It will be hidden from the spool list. You can show archived spools again from the list menu.",
                confirmBeforeDelete: confirmBeforeDelete
            ) {
                run("Could Not Archive Spool", "The spool could not be archived.") {
                    await store.setSpoolArchived(id: spool.id, archived: true)
                }
            }
        }
    }
}
