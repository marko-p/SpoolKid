//
//  FilamentSwatch.swift
//  SpoolKid
//
//  Purpose: The round color chip for a filament or tag. One color fills the
//  circle; a coextruded filament shows equal wedges; a gradient filament
//  shows its colors top to bottom. Every surface that draws a filament's
//  color uses this, so a multi-color filament looks the same everywhere.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentSwatch: View {
    let colors: FilamentColors
    let size: CGFloat

    init(colors: FilamentColors, size: CGFloat) {
        self.colors = colors
        self.size = size
    }

    /// Equal wedges starting at the top (-90 degrees), so two colors are
    /// left and right halves.
    nonisolated static func slices(count: Int) -> [(start: Angle, end: Angle)] {
        guard count > 0 else { return [] }
        let sweep = 360.0 / Double(count)
        return (0..<count).map { index in
            (start: .degrees(-90 + sweep * Double(index)),
             end: .degrees(-90 + sweep * Double(index + 1)))
        }
    }

    /// Only the rows that are valid hexes; editor and tag rows can hold junk.
    private var drawn: [Color] {
        colors.hexes
            .compactMap(FilamentColors.normalizedHex)
            .compactMap { Color(hex: $0) }
    }

    var body: some View {
        fill
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var fill: some View {
        let valid = drawn
        if valid.isEmpty {
            Color.swatchFallback
        } else if valid.count == 1 || !colors.isMulti {
            valid[0]
        } else if colors.pattern == .gradient {
            LinearGradient(colors: valid, startPoint: .top, endPoint: .bottom)
        } else {
            let slices = Self.slices(count: valid.count)
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let radius = max(proxy.size.width, proxy.size.height)
                ZStack {
                    ForEach(valid.indices, id: \.self) { index in
                        Path { path in
                            path.move(to: center)
                            path.addArc(center: center, radius: radius,
                                        startAngle: slices[index].start, endAngle: slices[index].end,
                                        clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(valid[index])
                    }
                }
            }
        }
    }
}
