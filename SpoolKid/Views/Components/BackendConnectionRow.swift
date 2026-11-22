//
//  BackendConnectionRow.swift
//  SpoolKid
//
//  Purpose: The active backend's row — its name, symbol and live reachability —
//  opening the Backend screen. One row, two entry points: the top of the
//  Library tab and the top of Settings.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct BackendConnectionRow: View {
    /// Bumped by a host whose own refresh should re-probe too — the Library's
    /// pull-to-refresh. Appearing and returning to the foreground re-probe
    /// without it.
    var probeToken = 0

    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.scenePhase) private var scenePhase

    /// Live presentational reachability of the active backend's server, driven
    /// by the repository's lightweight `checkReachability` probe. Distinct from
    /// the sticky connection flag (which gates SpoolLink/migration features);
    /// this only drives the row's color + label so a server that drops off the
    /// LAN is shown as "Unreachable" instead of staying green.
    /// `nil` means a probe is in flight and has not answered yet.
    @State private var reachability: BackendReachability?
    @State private var healthCheckInProgress = false

    var body: some View {
        let caps = store.capabilities
        NavigationLink {
            SpoolmanSettingsView()
        } label: {
            HStack {
                Label(caps.connectionRowLabel, systemImage: caps.tabSymbol)
                Spacer()
                Circle()
                    .fill(BackendReachability.statusColor(for: reachability))
                    .frame(width: 10, height: 10)
                Text(BackendReachability.statusText(for: reachability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Unstructured on purpose, as before the row was shared: a `.task`
        // would be cancelled when the row scrolls away, and a cancelled probe
        // can land "Unreachable" after its replacement was refused by the
        // in-progress guard.
        .onAppear { Task { await refreshReachability() } }
        .onChange(of: probeToken) { _, _ in
            Task { await refreshReachability() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshReachability() }
            }
        }
    }

    /// Re-probes the ACTIVE backend's reachability (display only — never
    /// touches any sticky connection flag, and never `errorMessage`; see
    /// `SpoolDataRepository.checkReachability`). Which address gets probed, and
    /// whether a probe happens at all, is the repository's business — this used
    /// to read `spoolmanUrl` and call `SpoolmanService.healthCheck` directly,
    /// which on FilaMan probed a blank Spoolman URL and reported "Not
    /// configured" for a live server.
    ///
    /// Guards against overlapping probes, and against a late answer landing
    /// after the user changed the server underneath it.
    private func refreshReachability() async {
        guard !healthCheckInProgress else { return }
        healthCheckInProgress = true
        reachability = nil
        let probedTarget = store.connectionTarget
        let result = await store.checkReachability()
        healthCheckInProgress = false
        // Only commit if the probe still describes the server on screen.
        if probedTarget == store.connectionTarget {
            reachability = result
        }
    }
}
