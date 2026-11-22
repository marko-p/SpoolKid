//
//  InfoButton.swift
//  SpoolKid
//
//  Purpose: The (i) that explains how a section works, in a popover opened on
//  tap. One implementation for the Scan Hub, the spool form, the scale row,
//  Weigh and the Home cards (UI simplification, spec 2026-09-27, D5).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct InfoButton: View {
    let title: String
    let lines: [String]
    /// The one-time TipKit tip that points this button out, or nil.
    var introTip: (any Tip)? = nil

    @State private var isShowingInfo = false

    var body: some View {
        Button {
            // Using the feature retires its tip; a tap outside the popover
            // only hides it until the screen reappears.
            introTip?.invalidate(reason: .actionPerformed)
            isShowingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Borderless: in a Form row, a default-styled Button makes the whole
        // row one tap target and never fires (ScaleWeightRow, 2026-09-08).
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(title)")
        .popoverTip(introTip)
        .popover(isPresented: $isShowingInfo) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // A popover opened from a Form section header inherits that
            // header's uppercase text case on some iOS versions — without
            // this the explanation itself would render IN CAPITALS.
            .textCase(nil)
            .padding()
            .frame(idealWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }
}
