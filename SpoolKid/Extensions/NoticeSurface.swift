//
//  NoticeSurface.swift
//  SpoolKid
//
//  Purpose: The one glass surface used by every root-level notice — the save
//  notice and the support prompt — so they read as one family rather than
//  several looks.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

extension View {
    /// Liquid glass on iOS 26+, the material it replaced below that — the same
    /// conditional the Write-Tag button and the keyboard Done bar already use.
    ///
    /// Lived privately inside `SaveNoticeBanner` until the support prompt needed
    /// the identical treatment; copying it would have created the second
    /// implementation A4 exists to prevent.
    @ViewBuilder
    func noticeSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color(.label).opacity(0.12), radius: 12, x: 0, y: 4)
            )
        }
    }

    /// The raised card a dragged row becomes. Same `#available` structure as
    /// `noticeSurface()` at a row-appropriate radius — one family, not a
    /// copied conditional.
    @ViewBuilder
    func dragLiftSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color(.label).opacity(0.22), radius: 16, x: 0, y: 6)
            )
        }
    }
}
