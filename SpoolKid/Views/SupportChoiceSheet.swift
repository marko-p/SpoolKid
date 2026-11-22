//
//  SupportChoiceSheet.swift
//  SpoolKid
//
//  Purpose: Where the banner's Support button leads — the same two destinations
//  the Settings screen offers, without leaving the tab the user is on.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SupportChoiceSheet: View {
    /// Called when the user actually taps through to a support destination —
    /// which is all the app can ever observe. It never claims a contribution
    /// happened.
    let onOpen: () -> Void

    /// "Don't show again" — the sheet's own way to stop the asks without
    /// visiting either support page.
    let onOptOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(SupportPromptCopy.sheetBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SupportLinksView {
                onOpen()
                dismiss()
            }

            VStack(spacing: 4) {
                Button(SupportPromptCopy.sheetDismissButton) { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)

                Button(SupportPromptCopy.sheetOptOutButton) {
                    onOptOut()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(24)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }
}
