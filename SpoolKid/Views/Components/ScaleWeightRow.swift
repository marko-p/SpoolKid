//
//  ScaleWeightRow.swift
//  SpoolKid
//
//  Purpose: One row that puts the paired scale's live reading next to a weight
//  field. Shared by the weigh session and the spool form so the two screens
//  cannot drift apart — the same connection, the same number, the same words.
//
//  It does not choose a scale. Choosing happens once, in Settings → Bluetooth
//  Scale (`ScaleSetupView`); here there is either a scale or a way to go and
//  set one up.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A live weight from the paired scale, and one tap to take it.
///
/// The reading is never written into the field on its own. A weight that
/// appears without being asked for is the same failure as a prefilled measured
/// weight: it lets someone confirm a number they never put on a scale. So the
/// button says what it will do and the figure is on it. (The weigh session's
/// scale MODE is the deliberate exception — see `WeighSessionView`.)
struct ScaleWeightRow: View {

    @EnvironmentObject private var scale: BLEScaleService
    @State private var showingSetup = false

    /// Called with the grams the user chose to take.
    let onUse: (Int) -> Void

    var body: some View {
        Group {
            if scale.paired == nil {
                setupPrompt
            } else {
                pairedRow
            }
        }
        // Reconnects the paired scale, and does nothing at all when there is
        // none — which is what keeps the Bluetooth permission prompt off a
        // screen about spools.
        .onAppear { scale.ensureConnected() }
        .sheet(isPresented: $showingSetup) {
            NavigationStack {
                ScaleSetupView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSetup = false }
                        }
                    }
            }
        }
    }

    private var setupPrompt: some View {
        HStack {
            Button {
                showingSetup = true
            } label: {
                Label("Set Up a Bluetooth Scale", systemImage: "scalemass")
            }
            // Without an explicit style the enclosing Form row swallows the tap:
            // a row holding a TextField and a Button becomes one target, and the
            // Button never fires. It looked like plain text on the owner's device
            // (2026-09-08). Every Button in this row needs the same treatment.
            .buttonStyle(.borderless)
            Spacer()
            InfoButton(
                title: "Bluetooth Scale",
                lines: ["Set one up once and its weight lands here on its own. Also in Settings → Bluetooth Scale."]
            )
        }
    }

    private var waitingReason: String {
        if scale.hasOptOuts {
            return "Some of this scale's services are switched off in Diagnostics, so no weight can arrive."
        }
        if let message = scale.availability.message {
            return message
        }
        if scale.connected == nil {
            return "Switch the scale on — SpoolKid reconnects on its own."
        }
        // The scale says nothing about a load that is not changing, so a
        // spool already on the pan when the link came up stays unreported.
        return scale.knowsZero
            ? "Waiting for the scale. Put the spool on — if it is already on, nudge the pan."
            : "Take everything off the pan — SpoolKid is learning what this scale calls zero."
    }

    /// What can be said about the number on the button.
    enum Status: Equatable {
        /// The scale called it steady: the number on its display.
        case steady
        /// Still arriving; the settled reading may be on its way.
        case moving
        /// A link drop swallowed what came after it, or it predates this link.
        /// Waiting will not help — the scale only speaks when the load changes.
        case missed
        /// Zero, at rest. This scale never calls an empty pan steady.
        case emptyPan
        /// A weight at rest the scale never called steady — what a wrong zero
        /// looks like on an empty pan.
        case unsteadyAtRest
    }

    nonisolated static func status(of reading: AiLinkScaleReading, held: AiLinkScaleZero.HeldFrame) -> Status {
        if reading.isSettled { return .steady }
        switch held {
        case .arriving: return .moving
        case .cutOff, .none: return .missed
        case .final: return reading.grams == 0 ? .emptyPan : .unsteadyAtRest
        }
    }

    private static func caption(for status: Status) -> String {
        switch status {
        case .steady: return "Steady. This is the number on the scale's display."
        case .moving: return "Still moving — wait for it to settle."
        case .missed: return "The connection dropped before the scale confirmed this reading, so it may be off. Nudge the pan for a confirmed one."
        case .emptyPan: return "Pan is empty."
        case .unsteadyAtRest: return "The scale has not called this steady. If the pan is empty, zero it below."
        }
    }

    @ViewBuilder
    private var pairedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(scale.paired?.name ?? "Scale", systemImage: "scalemass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reading = scale.reading {
                Button {
                    onUse(reading.grams)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Use")
                        Spacer()
                        Text("\(reading.grams) g")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!reading.isSettled)

                Text(Self.caption(for: Self.status(of: reading, held: scale.heldFrame)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Says WHY it is silent when the reason is something the user
                // did elsewhere. Without this the screen sits on "waiting"
                // forever after a tester switches off the very characteristic
                // the weight arrives on, in a different part of the app.
                Text(waitingReason)
                    .font(.subheadline)
                    .foregroundStyle(scale.hasOptOuts ? .orange : .secondary)
            }

            // The correction, not a calibration step: the zero is learned by
            // watching, and this is here for the one time that goes wrong.
            if scale.canSetZero {
                Button("Pan is empty — zero it") { scale.setZeroToCurrentReading() }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
    }
}
