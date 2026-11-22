//
//  ColorCaptureGuideView.swift
//  SpoolKid
//
//  Purpose: The color capture guide: four swipeable pages on light, framing,
//  the optional grey card and comparing the result, ending in Start. Presented
//  as a sheet over the camera, the first time and from the ? button.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ColorCaptureGuideView: View {
    let onStart: () -> Void

    @State private var page = 0

    private struct Section {
        let heading: String?
        let bullets: [String]
    }

    private struct Page {
        let title: String
        let note: String?
        let sections: [Section]
    }

    private static let pages: [Page] = [
        Page(title: "Use good, even light", note: nil, sections: [
            Section(heading: "Good", bullets: [
                "Daylight from a window, but not direct sun",
                "A daylight LED (5000–6500 K), ideally labelled CRI 90+ or 95+"
            ]),
            Section(heading: "Bad", bullets: [
                "Warm yellow bulbs",
                "Colored or RGB lights",
                "Mixing daylight and lamp light",
                "The phone's flash or torch (it adds glare and hot spots)"
            ])
        ]),
        Page(title: "Fill the circle with filament", note: nil, sections: [
            Section(heading: nil, bullets: [
                "Aim at the wound filament on the spool, not a single loose strand",
                "Hold the phone 10–20 cm away",
                "Tilt slightly so no bright reflection sits in the circle",
                "Keep the phone's shadow off the spool",
                "Shrink the circle if it reaches the spool's rim"
            ])
        ]),
        Page(title: "A grey card makes it more accurate", note: "Optional", sections: [
            Section(heading: nil, bullets: [
                "Put a grey card (white / grey / black) right next to the spool, in the same light",
                "SpoolKid finds it on its own; drag the outline if it's wrong",
                "DIY: plain matte white paper works for white; home-printed grey often isn't truly neutral (ink casts, paper brighteners)",
                "No card? You still get a reading, without the correction."
            ])
        ]),
        Page(title: "Compare, then save", note: nil, sections: [
            Section(heading: nil, bullets: [
                "On the review screen, hold the phone next to the spool and compare",
                "Not close? Retake, or fine-tune by hand afterwards",
                "Silk, glitter, translucent and dual-color filaments are hard to capture; expect to fine-tune",
                "Screens show colors differently; a printer's display may not match the phone"
            ])
        ])
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, content in
                    pageView(content)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page == Self.pages.count - 1 {
                Button(action: onStart) {
                    Text("Start")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
                .accessibilityIdentifier("colorCapture.guideStart")
            }
        }
    }

    private func pageView(_ content: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.title2.bold())
                    if let note = content.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.headline)
                        }
                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                Text(bullet)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 56)
        }
    }
}
