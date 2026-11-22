//
//  FilamentTagsSection.swift
//  SpoolKid
//
//  Purpose: An existing filament's tag links, in its form (spec 4). Links and
//  unlinks at once, through the store — the form saves fields, not tags. A
//  tag a spool or another filament holds is offered as a move, by name.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentTagsSection: View {
    @ObservedObject var store: SpoolDataStore
    let filamentId: Int

    @EnvironmentObject private var printer: PrinterService
    @StateObject private var nfcManager = NFCManager()
    /// Which reader scans to link. Never stored.
    @State private var tagReader: TagReader = .iPhone
    @State private var scanRun = TagReaderRun()
    @State private var isScanning = false
    @State private var pendingMove: PendingMove?
    @State private var message: String?

    struct PendingMove: Identifiable {
        let uid: String
        let holder: TagOwner
        var id: String { uid }
    }

    private var filament: Filament? { store.filaments.first { $0.id == filamentId } }
    private var uids: [String] { filament?.mappedTagUIDs ?? [] }
    private var addsLinks: Bool { store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore) }

    var body: some View {
        if addsLinks || !uids.isEmpty {
            Section {
                ForEach(uids, id: \.self) { uid in
                    HStack(spacing: 10) {
                        Text(uid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await unlink(uid) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .needsServer()
                        .accessibilityLabel("Unlink \(uid)")
                    }
                }
                if addsLinks {
                    TagReaderPicker(selection: $tagReader, purpose: .read)
                        .needsServer()
                    Button {
                        message = nil
                        isScanning = true
                        // Only a tag for this filament is an answer here: a
                        // location tag is refused by the session itself.
                        scanRun = .start(tagReader, purpose: .read, printer: printer, store: store)
                        nfcManager.startScanning(rejectingLocationTags: true, reader: scanRun.reader)
                    } label: {
                        Label(
                            isScanning
                                ? (scanRun.progressText ?? "Scanning…")
                                : "Scan tag to link",
                            systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "wave.3.right"
                        )
                        .foregroundStyle(isScanning ? .orange : .accentColor)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(nfcManager.isScanning)
                    .needsServer()
                    if let filament {
                        NavigationLink {
                            WriteTagView(initialData: FilamentTagData.from(filament: filament), linkFilamentId: filament.id)
                        } label: {
                            Label("Write a New Tag", systemImage: "square.and.pencil")
                                .frame(minHeight: 44)
                        }
                    }
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Linked Tags")
            } footer: {
                if !addsLinks {
                    Text("SpoolKid adds filament tag links only in Tag Links mode. You can still remove one.")
                        .font(.subheadline)
                }
            }
            .onChange(of: nfcManager.isScanning) { _, scanning in
                guard !scanning, isScanning else { return }
                isScanning = false
                // A toolhead's failure arrives as an alert text this section never shows.
                if let failure = scanRun.toolheadFailure(alertMessage: nfcManager.alertMessage) {
                    message = failure
                    nfcManager.alertMessage = ""
                }
                let uid = SpoolMappingService.normalizeUID(nfcManager.scanResult?.cardUID ?? "")
                nfcManager.scanResult = nil
                guard !uid.isEmpty else { return }
                Task { await link(uid) }
            }
            .alert(
                Text(pendingMove.map { TagHolderMove.confirmationToFilament(uid: $0.uid, holder: $0.holder).title } ?? ""),
                isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
                presenting: pendingMove
            ) { move in
                Button("Cancel", role: .cancel) {}
                Button("Move") { Task { await performMove(move) } }
            } message: { move in
                Text(TagHolderMove.confirmationToFilament(uid: move.uid, holder: move.holder).message)
            }
        }
    }

    private func link(_ uid: String) async {
        switch store.owner(ofTagUID: uid) {
        case .none:
            break
        case .filament(let id, _) where id == filamentId:
            return
        case .location(let name):
            message = "That tag labels \(name). A tag belongs to one spool, one filament or one location."
            return
        case let holder:
            pendingMove = PendingMove(uid: uid, holder: holder)
            return
        }
        switch await store.linkFilamentTag(filamentId: filamentId, uid: uid) {
        case .linked:
            message = nil
        case .failed(let failure):
            message = failure
        case .heldBySpool(let id):
            message = "Spool #\(id) already holds this tag."
        case .heldByFilament(let id):
            message = "Filament #\(id) already holds this tag."
        }
    }

    private func performMove(_ move: PendingMove) async {
        guard let filament else { return }
        if case .notSaved(let failure) = await TagHolderMove.moveToFilament(
            uid: move.uid, from: move.holder, to: filament, in: store
        ) {
            message = failure
        } else {
            message = nil
        }
    }

    private func unlink(_ uid: String) async {
        message = nil
        if !(await store.unlinkFilamentTag(filamentId: filamentId, uid: uid)) {
            message = store.errorMessage ?? "\(uid) could not be unlinked."
        }
    }
}
