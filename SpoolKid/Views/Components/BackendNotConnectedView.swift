//
//  BackendNotConnectedView.swift
//  SpoolKid
//
//  Purpose: The one "this backend isn't connected" screen, shared by the Home
//  dashboard and the Library tab. It is the only thing a stranded user can
//  see, so it has to be a way out rather than a dead end.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Shown when the ACTIVE backend is a server with no validated connection.
///
/// Both the copy and the action exist because of F37. The Backend picker is a
/// Local user's **only** route to the connection form — the form renders only
/// once its backend is selected — and the picker writes
/// `AppConfig.backendKindKey` on the first tap, before anything is validated.
/// It must: a backend cannot be tested before it is chosen. Abandoning setup
/// there (server not up, wrong URL, phone put down) leaves the next launch
/// resolving to a server that cannot answer, and Home and Library both said
/// only "configure your server". Nothing said the on-device library still
/// existed, or that the choice could be reversed; Home's action was worse than
/// useless, opening **iOS** Settings, where `Settings.bundle` carries no server
/// configuration at all.
///
/// Resolution itself is deliberately NOT self-healing. Falling back to the
/// local Library whenever a stored server kind looks unvalidated would empty
/// the library of a Spoolman user whose server is merely **offline** — a worse
/// failure, and a silent override of an explicit choice. So the recovery lives
/// on the failure screen instead of in `SpoolDataStore.resolveBackendKind`.
///
/// `symbol` is the caller's, because the two surfaces illustrate different
/// things: the Library tab shows the backend's own `tabSymbol`, the dashboard a
/// chart glyph.
struct BackendNotConnectedView: View {
    let capabilities: BackendCapabilities
    let symbol: String
    let onOpenBackendSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(Self.title(for: capabilities), systemImage: symbol)
        } description: {
            Text(Self.description(for: capabilities))
        } actions: {
            Button(Self.actionTitle, action: onOpenBackendSettings)
        }
    }

    static func title(for capabilities: BackendCapabilities) -> String {
        "No \(capabilities.displayName) Connection"
    }

    /// Names the three things a stranded user needs and none of which the
    /// previous copy carried: which backend is selected, that it can still be
    /// set up, and that switching back to the on-device Library is possible and
    /// destroys nothing.
    ///
    /// The last sentence claims only what is true of *this* action — changing
    /// backends never touches local rows. Migration can wipe them, but that is
    /// a separate, explicitly confirmed step.
    static func description(for capabilities: BackendCapabilities) -> String {
        "SpoolKid is set to use \(capabilities.displayName), which isn't connected yet. "
        + "Set up the server, or switch the backend back to "
        + "\(BackendCapabilities.local.displayName) to see the spools stored on this iPhone. "
        + "Switching backends never deletes anything."
    }

    /// Names the destination rather than a generic "Settings": the whole defect
    /// was an action that led somewhere with no backend configuration in it.
    static let actionTitle = "Backend Settings"
}
