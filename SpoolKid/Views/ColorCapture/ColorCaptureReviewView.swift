//
//  ColorCaptureReviewView.swift
//  SpoolKid
//
//  Purpose: The review half of the color capture screen: the swatch(es) to hold
//  next to the spool, the hex, what was ignored and why, and the Use Color and
//  Retake buttons. The photo and the sample circle are drawn by the screen.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ColorCaptureReviewView: View {
    @ObservedObject var model: ColorCaptureModel
    /// Tallest the scrolling part may grow; Retake and Use Color stay below it.
    let maxScrollHeight: CGFloat
    let onUse: (String) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                content
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { contentHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, newValue in contentHeight = newValue }
                        })
            }
            .frame(height: contentHeight > 0 ? min(contentHeight, maxScrollHeight) : maxScrollHeight)
            .scrollBounceBehavior(.basedOnSize)

            buttons
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onAppear {
            if let reading = model.reading {
                AccessibilityNotification.Announcement("Color captured, #\(reading.savedHex)").post()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            Text("Hold this next to the spool")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            swatches

            if let reading = model.reading {
                Text("#" + reading.savedHex)
                    .font(.title3.monospaced().weight(.semibold))
                    .accessibilityLabel("Color \(reading.savedHex)")
                lines(for: reading)
            }

            Text("Drag the circle to re-sample")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ColorCaptureSizeSlider(model: model)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                model.retake()
            } label: {
                Text("Retake")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("colorCapture.retake")

            Button {
                if let reading = model.reading {
                    onUse(reading.savedHex)
                }
            } label: {
                Text("Use Color")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.reading == nil)
            .accessibilityIdentifier("colorCapture.useColor")
        }
    }

    // MARK: - Swatches

    @ViewBuilder
    private var swatches: some View {
        if let reading = model.reading {
            if model.activeCard != nil, let corrected = reading.correctedHex {
                HStack(spacing: 12) {
                    swatch(hex: reading.rawHex, caption: "Raw", accessibilityName: "Raw color")
                    swatch(hex: corrected, caption: "Corrected", accessibilityName: "Corrected color")
                }
            } else {
                swatch(hex: reading.savedHex, caption: model.activeCard == nil ? "No card used" : nil,
                       accessibilityName: "Captured color")
            }
        } else {
            swatch(hex: nil, caption: nil, accessibilityName: "Captured color")
        }
    }

    private func swatch(hex: String?, caption: String?, accessibilityName: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hex.flatMap { Color(hex: $0) } ?? Color.swatchFallback)
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.swatchBorder, lineWidth: 1))
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hex.map { "\(accessibilityName) #\($0)" } ?? accessibilityName)
    }

    // MARK: - Notes

    @ViewBuilder
    private func lines(for reading: ColorCaptureReading) -> some View {
        VStack(spacing: 4) {
            let percent = Int((reading.ignoredFraction * 100).rounded())
            if percent >= 1 {
                Text("\(percent)% ignored (glare and shadows)")
            }
            if reading.ignoredFraction > 0.5 {
                Text("Most of the circle was ignored — tilt the spool or move the light.")
            }
            if reading.usedFallback {
                Text("Too bright — the reading may be too light; move away from the light or tilt the spool.")
            }
            ForEach(Array(reading.notes.enumerated()), id: \.offset) { _, note in
                Text(note.message)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

private extension ColorCaptureReading.Note {
    var message: String {
        switch self {
        case .cardCoversSample: "The outline covers the sample circle, so no correction was applied."
        case .cardNotRecognized: "The outline isn't on a grey card, so no correction was applied."
        case .patchClipped: "Part of the card is too bright to use."
        case .patchTooDark: "Part of the card is too dark to use."
        }
    }
}
