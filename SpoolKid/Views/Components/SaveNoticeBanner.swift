//
//  SaveNoticeBanner.swift
//  SpoolKid
//
//  Purpose: Root-level notice for a write that LANDED but could not do
//  everything it was asked (plan defect I1).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Shows `SpoolDataStore.saveNotice` above the tab bar until the user dismisses
/// it.
///
/// An overlay rather than an alert, deliberately: the form that produced the
/// caveat is a sheet dismissing at the same moment, and an alert raised from
/// the root while that sheet is still on screen is at the mercy of UIKit's
/// presentation queue. An overlay is just a view — it cannot be swallowed, and
/// a notice the user never sees would be the very silent success this exists
/// to end. For the same reason it does not auto-hide: a partial failure is
/// worth an acknowledgement, and the sheet's dismissal animation would eat the
/// first moments of any timer.
///
/// The headline read "Saved, with a problem" until 2026-08-28. It contradicted
/// its own body — the save succeeded and a *field* was refused — which is what
/// the owner's device pass reported (finding 4.2.1).
struct SaveNoticeBanner: View {
    let notice: SaveNotice
    let onDismiss: () -> Void

    private var headline: String {
        notice.entries.count == 1 ? "Saved without one change" : "Saved without some changes"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.headline)
                ForEach(notice.entries) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        if let record = entry.record {
                            Text(record)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .noticeSurface()
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
