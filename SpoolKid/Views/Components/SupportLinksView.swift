//
//  SupportLinksView.swift
//  SpoolKid
//
//  Purpose: The two support destinations — GitHub Sponsors and Ko-fi — as one
//  reusable pair, shared by the Settings screen and the support prompt sheet.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Buttons rather than `Link`s, deliberately: `Link` gives no callback, and the
/// support prompt has to know that the user tapped through in order to stop
/// asking for a while. Opening the URL is still the button's action — `onOpen`
/// is a notification alongside it, not the behaviour (A6).
///
/// Appearance, destinations and order are exactly what `SettingsView` shipped
/// before the extraction.
struct SupportLinksView: View {
    var onOpen: () -> Void = {}

    @Environment(\.openURL) private var openURL

    private static let sponsorsPink = Color(red: 0.91, green: 0.29, blue: 0.67)
    private static let kofiBlue = Color(red: 0.25, green: 0.55, blue: 0.96)

    var body: some View {
        VStack(spacing: 8) {
            button(
                title: "Sponsor on GitHub",
                symbol: "heart.fill",
                tint: Self.sponsorsPink,
                url: AppConfig.sponsorsURL
            )
            button(
                title: "Support on Ko-fi",
                symbol: "cup.and.saucer.fill",
                tint: Self.kofiBlue,
                url: AppConfig.kofiURL
            )
        }
    }

    private func button(title: String, symbol: String, tint: Color, url: URL) -> some View {
        Button {
            // Open the URL BEFORE the notification: in `SupportChoiceSheet`,
            // `onOpen` also dismisses the sheet, and opening a URL from a view
            // mid-dismissal is a needless ordering risk. `SettingsView`'s default
            // `onOpen` is a no-op, so this reorder changes nothing there.
            openURL(url)
            onOpen()
        } label: {
            HStack {
                Spacer()
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.vertical, 12)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
