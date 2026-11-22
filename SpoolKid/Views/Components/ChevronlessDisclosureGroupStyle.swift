//
//  ChevronlessDisclosureGroupStyle.swift
//  SpoolKid
//
//  Purpose: A `DisclosureGroupStyle` that draws only the label and, when
//  expanded, the content — no trailing disclosure indicator. Tapping the
//  label still toggles the group, exactly like the system style; a shelf row
//  already carries its own `›` detail button and drag grip, so the system
//  chevron said nothing a tap on the shelf name didn't already say.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ChevronlessDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { configuration.isExpanded.toggle() }
                }

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

extension DisclosureGroupStyle where Self == ChevronlessDisclosureGroupStyle {
    static var chevronless: ChevronlessDisclosureGroupStyle { .init() }
}
