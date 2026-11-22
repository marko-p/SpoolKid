//
//  LocationAssignmentView.swift
//  SpoolKid
//
//  Purpose: The guided spool→location session. Two slots, each fillable by
//  scanning a tag or picking from a list, and one status line that always says
//  what to do next.
//
//  The location slot is sticky: after an assignment the spool slot clears and
//  the shelf stays, so stocking a shelf costs one scan per spool. The
//  auto-chain into a location scan fires only while no shelf is held.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationAssignmentView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss

    var initialLocationName: String? = nil

    @StateObject private var nfcManager = NFCManager()
    @State private var state = LocationAssignmentState()
    @State private var showSpoolPicker = false
    @State private var showLocationPicker = false
    @State private var unresolvedTagUID: String?
    /// The unlinked tag the spool picker was opened FOR, when a link can be
    /// stored; `nil` when the picker was opened from the slot's own button.
    @State private var pickerLinkUID: String?
    /// The spool chosen while `pickerLinkUID` was set. Offered for linking
    /// only once the picker sheet has gone: an alert raised from inside a
    /// sheet's own callback renders with its buttons dead (ui-patterns.md).
    /// The slot is filled only after the offer is answered — filling it can
    /// start the location scan, whose NFC sheet would bury the question.
    @State private var chosenSpoolForLink: Spool?
    @State private var linkOffer: LinkOffer?
    /// `onAppear` can re-fire for sheet content. Without this guard, a second
    /// firing after the user taps "Change" on the location slot would silently
    /// reinstate the shelf they just cleared — and commit a held spool to it.
    /// Seed at most once per presentation; never re-derive over the user's own
    /// "Change" action. Mirrors `SpoolDataStore.seedBackendKindSelection`'s
    /// idempotency guard.
    @State private var didSeedLocation = false

    var body: some View {
        VStack(spacing: 20) {
            Text(state.statusLine)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
                .accessibilityIdentifier("assignment.status")

            slotCard(
                title: "Spool",
                systemImage: "circle.dashed",
                filled: state.spool?.label,
                isScanning: state.scanning == .spool,
                scanTitle: "Scan Spool Tag",
                pickTitle: "Choose a Spool",
                onScan: { beginScan(.spool) },
                onPick: { pickerLinkUID = nil; showSpoolPicker = true },
                onClear: { LocationAssignmentState.reduce(&state, .clearedSpool) }
            )

            slotCard(
                title: "Location",
                systemImage: "mappin.and.ellipse",
                filled: state.location?.name,
                isScanning: state.scanning == .location,
                scanTitle: "Scan Location Tag",
                pickTitle: "Choose a Location",
                onScan: { beginScan(.location) },
                onPick: { showLocationPicker = true },
                onClear: { LocationAssignmentState.reduce(&state, .clearedLocation) }
            )

            if !state.assignments.isEmpty {
                List(state.assignments, id: \.spoolId) { assignment in
                    Text("\(assignment.spoolLabel) → \(assignment.locationName)")
                        .font(.subheadline)
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding(.top)
        .navigationTitle("Assign Spools")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            guard !didSeedLocation else { return }
            didSeedLocation = true
            if let initialLocationName {
                LocationAssignmentState.reduce(&state, .gotLocation(.init(name: initialLocationName)))
            }
        }
        // One observer for the whole session, the shape `TagsTabView` uses: the
        // session ENDING is the event, and whether it produced a result is read
        // there. A cancelled or timed-out iOS sheet produces no result, and
        // without this branch the slot would sit on "Waiting for a tag…" with
        // no scan, pick or cancel control until the sheet is closed — which
        // discards the session list.
        .onChange(of: nfcManager.isScanning) { _, isScanning in
            guard !isScanning, state.scanning != nil else { return }
            guard let result = nfcManager.scanResult else {
                LocationAssignmentState.reduce(&state, .cancelledScan)
                return
            }
            // Cleared before handling: the auto-chain starts the next scan from
            // inside `handle`, and its result must not find this one waiting.
            nfcManager.scanResult = nil
            handle(result)
        }
        .sheet(isPresented: $showSpoolPicker, onDismiss: offerLinkIfChosen) {
            NavigationStack {
                SpoolSelectionView { spool in
                    showSpoolPicker = false
                    if pickerLinkUID != nil {
                        chosenSpoolForLink = spool
                    } else {
                        apply(.gotSpool(.init(id: spool.id, label: spool.listTitle)))
                    }
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            NavigationStack {
                List(knownLocations, id: \.self) { name in
                    Button(name) {
                        showLocationPicker = false
                        apply(.gotLocation(.init(name: name)))
                    }
                }
                .navigationTitle("Choose a Location")
            }
        }
        .alert("Tag Isn't Linked to a Spool", isPresented: Binding(
            get: { unresolvedTagUID != nil },
            set: { if !$0 { unresolvedTagUID = nil } }
        )) {
            Button("Choose a Spool") {
                pickerLinkUID = Self.linkOfferUID(
                    unresolvedUID: unresolvedTagUID,
                    writesLinks: store.tagIdentity.writesLinks
                )
                unresolvedTagUID = nil
                showSpoolPicker = true
            }
            Button("Cancel", role: .cancel) { unresolvedTagUID = nil }
        } message: {
            Text(unresolvedTagMessage)
        }
        .alert("Link This Tag?", isPresented: Binding(
            get: { linkOffer != nil },
            set: { if !$0 { linkOffer = nil } }
        ), presenting: linkOffer) { offer in
            Button("Link") {
                link(offer)
                apply(.gotSpool(.init(id: offer.spoolId, label: offer.spoolLabel)))
            }
            Button("Not Now", role: .cancel) {
                apply(.gotSpool(.init(id: offer.spoolId, label: offer.spoolLabel)))
            }
        } message: { offer in
            Text("Link the tag you scanned to \(offer.spoolLabel), so scanning it finds this spool next time.")
        }
    }

    private var unresolvedTagMessage: String {
        let canLink = Self.linkOfferUID(
            unresolvedUID: unresolvedTagUID,
            writesLinks: store.tagIdentity.writesLinks
        ) != nil
        return canLink
            ? "No spool claims this tag. Choose the spool it belongs to, and you can link the tag to it."
            : "No spool claims this tag. Choose the spool it belongs to, or link it from the Tags tab first."
    }

    private var knownLocations: [String] {
        ManageLocationsView.mergedLocations(
            observed: store.spools.compactMap(\.location),
            known: store.locations,
            registered: store.registeredLocations.map(\.name)
        )
    }

    // MARK: - Slot rendering

    @ViewBuilder
    private func slotCard(
        title: String,
        systemImage: String,
        filled: String?,
        isScanning: Bool,
        scanTitle: String,
        pickTitle: String,
        onScan: @escaping () -> Void,
        onPick: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let filled {
                HStack {
                    Text(filled)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Change", action: onClear)
                        .buttonStyle(.bordered)
                }
            } else if isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for a tag…")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button(scanTitle, action: onScan)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button(pickTitle, action: onPick)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .needsServer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Events

    private func beginScan(_ target: LocationAssignmentState.Target) {
        LocationAssignmentState.reduce(&state, .beganScanning(target))
        nfcManager.startScanning()
    }

    private func handle(_ result: ScanResult) {
        if let payload = result.locationTag {
            let name = ScanResultHubView.resolvedLocationName(
                for: payload, scannedUID: result.cardUID, registry: store.locationRegistry
            )
            apply(.gotLocation(.init(name: name)))
            return
        }

        guard let uid = result.cardUID else {
            LocationAssignmentState.reduce(&state, .cancelledScan)
            return
        }

        // Same guard as `ScanResultHubView.performResolve`, and for the same
        // reason: only a scan that actually decoded as filament data proves the
        // tag is no longer a location tag. A location tag whose NDEF read
        // failed arrives UID-only, and healing there would drop the registry's
        // claim on a real location tag on one bad read.
        if result.tagData != nil {
            ScanResultHubView.healRegistry(afterReadingSpoolTagWithUID: uid, registry: store.locationRegistry)
        }

        guard let spool = store.findSpool(byCardUID: uid) else {
            LocationAssignmentState.reduce(&state, .cancelledScan)
            unresolvedTagUID = uid
            return
        }
        apply(.gotSpool(.init(id: spool.id, label: spool.listTitle)))
    }

    // MARK: - Linking an unlinked tag

    struct LinkOffer {
        let uid: String
        let spoolId: Int
        let spoolLabel: String
    }

    /// Which unlinked tag, if any, to offer for linking once its spool is
    /// picked: only where the identity mode writes links (the gate
    /// `WriteTagView` uses for the same write).
    nonisolated static func linkOfferUID(unresolvedUID: String?, writesLinks: Bool) -> String? {
        guard writesLinks else { return nil }
        return unresolvedUID
    }

    private func offerLinkIfChosen() {
        if let uid = pickerLinkUID, let spool = chosenSpoolForLink {
            linkOffer = LinkOffer(uid: uid, spoolId: spool.id, spoolLabel: spool.listTitle)
        }
        pickerLinkUID = nil
        chosenSpoolForLink = nil
    }

    /// Through `TagLinkService.assign`, the funnel every spool claim passes
    /// through: it refuses a tag a location owns and releases any other spool
    /// still holding this one. A clean link is silent, like any clean save.
    private func link(_ offer: LinkOffer) {
        guard let spool = store.spools.first(where: { $0.id == offer.spoolId }) else {
            store.postSaveNotice("The tag was not linked: this spool is no longer in the list.", record: offer.spoolLabel)
            return
        }
        Task {
            let outcome = await TagLinkService.assign(offer.uid, to: spool, in: store)
            if let note = outcome.followUpNote {
                store.postSaveNotice(note, record: offer.spoolLabel)
            }
        }
    }

    /// The one place an event reaches the reducer and its effect is performed.
    private func apply(_ event: LocationAssignmentState.Event) {
        switch LocationAssignmentState.reduce(&state, event) {
        case .none:
            break
        case .startLocationScan:
            beginScan(.location)
        case .commit(let assignment):
            commit(assignment)
        }
    }

    private func commit(_ assignment: LocationAssignmentState.Assignment) {
        Task {
            let ok = await store.updateSpool(
                id: assignment.spoolId,
                draft: .locationAssignment(.set(assignment.locationName))
            )
            if ok {
                LocationAssignmentState.reduce(&state, .assignmentSucceeded)
            } else {
                LocationAssignmentState.reduce(&state, .assignmentFailed)
                store.postSaveNotice(
                    store.errorMessage ?? "The spool could not be moved.",
                    record: assignment.spoolLabel
                )
            }
        }
    }
}
