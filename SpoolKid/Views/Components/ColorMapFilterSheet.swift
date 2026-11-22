//
//  ColorMapFilterSheet.swift
//  SpoolKid
//
//  Purpose: Color filter sheet for Manage Spools — spectrum map with
//  availability islands, achromatic strip, harmony chips, tolerance slider.
//  Renders only; all math in ColorFilterService.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ColorMapFilterSheet: View {
    @Binding var spec: ColorFilterSpec?
    let islands: [ColorFilterService.ColorIsland]
    let summary: String?

    @AppStorage(AppConfig.colorMapIslandBaseDiameterKey) private var islandBaseDiameter: Double = 12
    @Environment(\.dismiss) private var dismiss

    private let stripHeight: CGFloat = 20

    private var anchorIsAchromatic: Bool {
        guard let spec else { return false }
        return ColorFilterService.isAchromatic(spec.anchorHex)
    }

    private var toleranceBinding: Binding<Double> {
        Binding(
            get: { spec?.toleranceDeltaE ?? ColorFilterService.defaultTolerance },
            set: { spec?.toleranceDeltaE = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            harmonyChips
            spectrumMap
            achromaticStrip
            toleranceRow
            readoutRow
        }
        .padding()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Filter by Color")
                .font(.headline)
            Spacer()
            Button("Clear") { spec = nil }
                .disabled(spec == nil)
        }
    }

    // MARK: - Harmony chips

    private var harmonyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ColorHarmony.allCases) { harmony in
                    chip(for: harmony)
                }
            }
        }
    }

    private func chip(for harmony: ColorHarmony) -> some View {
        let isSelected = spec?.harmony == harmony
        let isDisabled = spec == nil || (harmony.requiresChromaticAnchor && anchorIsAchromatic)
        return Button {
            spec?.harmony = harmony
        } label: {
            Text(harmony.displayName)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    // MARK: - Spectrum map

    private var spectrumMap: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                spectrumBase
                Color(.systemBackground).opacity(0.78)
                ForEach(islands.filter { $0.hue != nil }) { island in
                    let diameter = ColorFilterService.islandDiameter(spoolCount: island.spoolCount, baseDiameter: islandBaseDiameter)
                    Circle()
                        .fill(Color(hex: island.hex) ?? .gray)
                        .frame(width: diameter, height: diameter)
                        .position(ColorFilterService.mapPoint(hue: island.hue!, lightness: island.lightness, in: size))
                }
                if let spec {
                    if spec.harmony.isHueBand {
                        bandOverlay(spec: spec, size: size)
                        anchorDot(spec: spec, size: size)
                    } else {
                        selectionOverlay(spec: spec, size: size)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let hex = ColorFilterService.snappedHex(nearMapPoint: location, islands: islands, in: size)
                    ?? ColorFilterService.hex(atMapPoint: location, in: size)
                select(hex)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var spectrumBase: some View {
        ZStack {
            LinearGradient(
                colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) },
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0), location: 0.5),
                    .init(color: .black.opacity(0), location: 0.5),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Anchor + harmony target circles; each drawn at x and x ± width so
    /// circles crossing the hue seam show wrapped.
    @ViewBuilder
    private func selectionOverlay(spec: ColorFilterSpec, size: CGSize) -> some View {
        let radius = CGFloat(ColorFilterService.unitRadius(tolerance: spec.toleranceDeltaE)) * size.width
        let targets = ColorFilterService.targets(for: spec)
        ForEach(Array(targets.enumerated()), id: \.element) { index, target in
            if let center = ColorFilterService.mapPoint(forHex: target.hex, in: size) {
                let isAnchor = index == 0
                let r = radius
                ForEach([-1, 0, 1], id: \.self) { wrap in
                    let position = CGPoint(x: center.x + CGFloat(wrap) * size.width, y: center.y)
                    dashedCircle(radius: r, emphasized: isAnchor)
                        .position(position)
                    if !isAnchor {
                        Text(target.role)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .position(x: position.x, y: min(position.y + r + 10, size.height - 8))
                    }
                }
                if isAnchor {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                        .position(center)
                }
            }
        }
    }

    /// Dashed vertical band for hue-band modes: anchor hue ± tolerance°,
    /// full height (Monochromatic) or from the anchor's lightness down
    /// (Shades). Drawn at x and x ± width for the hue seam.
    @ViewBuilder
    private func bandOverlay(spec: ColorFilterSpec, size: CGSize) -> some View {
        if let anchor = ColorMatching.hsl(from: spec.anchorHex), !anchorIsAchromatic {
            let halfWidth = CGFloat(spec.toleranceDeltaE / 360) * size.width
            let centerX = CGFloat(anchor.h / 360) * size.width
            let top = spec.harmony == .shades ? (1 - CGFloat(anchor.l)) * size.height : 0
            ForEach([-1, 0, 1], id: \.self) { wrap in
                ZStack {
                    Rectangle().stroke(.black.opacity(0.35), lineWidth: 4)
                    Rectangle().stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .frame(width: halfWidth * 2, height: size.height - top)
                .position(x: centerX + CGFloat(wrap) * size.width, y: top + (size.height - top) / 2)
            }
        }
    }

    @ViewBuilder
    private func anchorDot(spec: ColorFilterSpec, size: CGSize) -> some View {
        if let center = ColorFilterService.mapPoint(forHex: spec.anchorHex, in: size) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                .position(center)
        }
    }

    private func dashedCircle(radius: CGFloat, emphasized: Bool) -> some View {
        ZStack {
            Circle().stroke(.black.opacity(0.35), lineWidth: 4)
            Circle().stroke(.white.opacity(emphasized ? 1 : 0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    // MARK: - Achromatic strip

    private var achromaticStrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing)
                ForEach(islands.filter { $0.hue == nil }) { island in
                    let diameter = min(ColorFilterService.islandDiameter(spoolCount: island.spoolCount, baseDiameter: islandBaseDiameter), stripHeight - 4)
                    Circle()
                        .fill(Color(hex: island.hex) ?? .gray)
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                        .frame(width: diameter, height: diameter)
                        .position(x: ColorFilterService.stripX(forLightness: island.lightness, width: width), y: stripHeight / 2)
                }
                if let spec, anchorIsAchromatic,
                   let hsl = ColorMatching.hsl(from: spec.anchorHex) {
                    Circle()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .background(Circle().stroke(.black.opacity(0.35), lineWidth: 4))
                        .frame(width: stripHeight - 2, height: stripHeight - 2)
                        .position(x: ColorFilterService.stripX(forLightness: hsl.l, width: width), y: stripHeight / 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let hex = ColorFilterService.snappedHex(nearStripX: location.x, islands: islands, width: width)
                    ?? ColorFilterService.hex(atStripFraction: location.x / max(width, 1))
                select(hex)
            }
        }
        .frame(height: stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Tolerance

    private var toleranceRow: some View {
        HStack(spacing: 10) {
            Text("Tolerance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Slider(value: toleranceBinding, in: ColorFilterService.toleranceRange, step: 1)
                .disabled(spec == nil)
            Text(ColorFilterService.toleranceLabel(harmony: spec?.harmony ?? .single, tolerance: spec?.toleranceDeltaE ?? ColorFilterService.defaultTolerance))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    // MARK: - Readout

    private var readoutRow: some View {
        HStack(spacing: 10) {
            if let spec {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: spec.anchorHex) ?? Color.swatchFallback)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.swatchBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("#\(ColorMatching.normalize(spec.anchorHex) ?? spec.anchorHex)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    if let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if anchorIsAchromatic {
                        Text("Pick a chromatic color for harmonies")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Tap the map to pick a color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Selection

    private func select(_ hex: String) {
        if var current = spec {
            current.anchorHex = hex
            if current.harmony.requiresChromaticAnchor && ColorFilterService.isAchromatic(hex) {
                current.harmony = .single
            }
            spec = current
        } else {
            spec = ColorFilterSpec(anchorHex: hex, toleranceDeltaE: ColorFilterService.defaultTolerance, harmony: .single)
        }
    }
}
