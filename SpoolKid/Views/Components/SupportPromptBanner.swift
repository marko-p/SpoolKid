//
//  SupportPromptBanner.swift
//  SpoolKid
//
//  Purpose: The root-level support ask. Shares SaveNoticeBanner's slot and
//  surface, but auto-hides — an optional ask is not news the way a half-failed
//  write is.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SupportPromptBanner: View {
    let content: SupportBannerContent
    let onSupport: () -> Void
    let onDismiss: () -> Void
    let onAutoHide: () -> Void

    /// The ask withdraws itself rather than sitting there. `SaveNoticeBanner`
    /// stays until acknowledged because a partial failure is news the user has
    /// to see; an ask is not, and an ask that will not leave is the thing people
    /// remember about an app.
    ///
    /// 30s, raised from 12 after the owner's device pass: 12 was enough to READ
    /// the ask but not enough to decide about it, and deciding is the whole
    /// point of showing it.
    private var autoHideSeconds: Double {
        switch content {
        case .ask: return 30
        case .thanks: return 3
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.title)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                // Sized up across the board after the owner's device pass:
                // the body was `.caption`, which was a struggle to read at
                // arm's length at the bench — the exact distance this banner
                // is read from.
                Text(headline)
                    .font(.title3.weight(.semibold))
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .ask = content {
                    // "Not now" leads, "Support" trails: the affirmative
                    // action sits under the reading thumb, and the way out is
                    // where a cancel is expected (owner's device pass).
                    HStack(spacing: 16) {
                        Button(SupportPromptCopy.notNowButton, action: onDismiss)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)

                        Button(SupportPromptCopy.supportButton, action: onSupport)
                            .font(.body.weight(.semibold))
                            .writeTagButtonStyle()
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        // Neither state has a trailing control any more — the corner X went
        // when "Not now" took over dismissal — so both need a real inset or
        // the wrapping body text reaches the glass edge.
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .noticeSurface()
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: content) {
            try? await Task.sleep(for: .seconds(autoHideSeconds))
            guard !Task.isCancelled else { return }
            onAutoHide()
        }
    }

    private var glyph: String {
        switch content {
        case .ask: return "heart.fill"
        case .thanks: return "hands.clap.fill"
        }
    }

    private var headline: String {
        switch content {
        case .ask(let reason): return SupportPromptCopy.headline(for: reason)
        case .thanks: return SupportPromptCopy.thanksHeadline
        }
    }

    private var bodyText: String {
        switch content {
        case .ask(let reason): return SupportPromptCopy.body(for: reason)
        case .thanks: return SupportPromptCopy.thanksBody
        }
    }
}
