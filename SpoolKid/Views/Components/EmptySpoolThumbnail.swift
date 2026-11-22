//
//  EmptySpoolThumbnail.swift
//  SpoolKid
//
//  Purpose: An empty spool's photo at a fixed square size, or a placeholder
//  when it has none. Decorative to VoiceOver: the row around it says what
//  the spool is. The stored JPEG is decoded once per photo and shrunk to the
//  thumbnail's pixel size, not decoded at full size on every body pass.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import UIKit

struct EmptySpoolThumbnail: View {
    let photo: Data?
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "circle.circle")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: photo) { image = await thumbnail() }
    }

    /// The photo scaled so its short edge fills the square at the display's
    /// pixel density (the view is `scaledToFill`). `UIImage(data:)` has scale
    /// 1, so its point size is its pixel size.
    private func thumbnail() async -> UIImage? {
        guard let photo, let full = UIImage(data: photo) else { return nil }
        let ratio = size * displayScale / min(full.size.width, full.size.height)
        guard ratio < 1 else { return full }
        let target = CGSize(width: full.size.width * ratio, height: full.size.height * ratio)
        return await full.byPreparingThumbnail(ofSize: target) ?? full
    }
}
