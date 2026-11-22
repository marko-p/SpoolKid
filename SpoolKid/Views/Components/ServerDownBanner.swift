//
//  ServerDownBanner.swift
//  SpoolKid
//
//  Purpose: How a down filament server shows: one banner with Try Again,
//  controls that need the server greyed out, last data dimmed. Every screen
//  reads `\.serverLink` through these, never its own check.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// What views know about the server link. The default locks nothing, so
/// previews and anything outside `ContentView` behave as before.
struct ServerLinkState {
    var isDown = false
    var backendName = ""
    var retry: @MainActor () -> Void = {}
    /// Runs a save and says whether it may have saved without an answer.
    var outcome: @MainActor (() async -> Bool) async -> WriteOutcome<Void> = { write in
        await write() ? .saved(()) : .failed
    }
}

/// What a form says about saving while the server is in trouble.
nonisolated enum SaveNote {
    static let unknown = "This may not have saved. Check once the server is back."
    static let unsureCreate = "This may already have saved. Check the list before you save again."

    /// After a create that may have arrived, Save waits for an explicit
    /// "Save Again": a second tap would otherwise make a duplicate.
    static func holdsResave(after outcome: WriteOutcome<Void>, isCreate: Bool) -> Bool {
        isCreate && outcome.isUnknown
    }

    /// Shown above a form while the server can't be reached.
    static func text(isDown: Bool, backendName: String) -> String? {
        isDown ? "Can't reach \(backendName). What you typed is kept; Save comes back when it does." : nil
    }

    /// A failed save's message: the unknown copy when it may have saved.
    static func failure(_ outcome: WriteOutcome<Void>, otherwise message: String) -> String {
        outcome.isUnknown ? unknown : message
    }
}

/// The note atop a form while the server can't be reached.
struct ServerDownFormNote: View {
    @Environment(\.serverLink) private var serverLink

    var body: some View {
        if let text = SaveNote.text(isDown: serverLink.isDown, backendName: serverLink.backendName) {
            Section {
                Label(text, systemImage: "wifi.exclamationmark").font(.subheadline)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var serverLink = ServerLinkState()
}

/// What Home and Library show for the server's state.
nonisolated enum ServerDownPresentation: Equatable {
    case normal
    /// The last list loaded, dimmed.
    case staleList
    /// Nothing loaded since launch: the existing not-connected screen.
    case notConnected

    static func decide(isDown: Bool, hasLoadedRows: Bool) -> ServerDownPresentation {
        guard isDown else { return .normal }
        return hasLoadedRows ? .staleList : .notConnected
    }
}

struct ServerDownBanner: View {
    /// Home and Library say their list may be old.
    var showsStaleNote = false
    @Environment(\.serverLink) private var serverLink

    var body: some View {
        if serverLink.isDown {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").accessibilityHidden(true)
                    Text("Can't reach \(serverLink.backendName)").font(.headline)
                    Spacer()
                    Button("Try Again") { serverLink.retry() }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                }
                if showsStaleNote {
                    Text("Showing the last list loaded. It may be out of date.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

private struct NeedsServer: ViewModifier {
    @Environment(\.serverLink) private var serverLink
    func body(content: Content) -> some View { content.disabled(serverLink.isDown) }
}

private struct StaleWhileServerDown: ViewModifier {
    @Environment(\.serverLink) private var serverLink
    func body(content: Content) -> some View { content.opacity(serverLink.isDown ? 0.6 : 1) }
}

extension View {
    /// Greyed out while the server can't be reached.
    func needsServer() -> some View { modifier(NeedsServer()) }

    /// Dimmed while the server can't be reached; still readable and scrollable.
    func staleWhileServerDown() -> some View { modifier(StaleWhileServerDown()) }
}
