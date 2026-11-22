//
//  ReferenceCardOutline.swift
//  SpoolKid
//
//  Purpose: The draggable outline of the grey reference card on the live and
//  review screens. Dragging inside moves the whole card, each corner handle
//  moves only that corner, and the ✕ turns card correction off for this reading;
//  the outline then stays as a dimmed suggestion that a drag restores.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// The named coordinate space of the full-screen camera/photo layer. Drags are
/// measured in it, so a handle that moves under the finger does not skew them.
enum ColorCaptureStageSpace {
    static let name = "colorCaptureStage"
}

struct ReferenceCardOutline: View {
    let card: Quad
    let mapping: AspectFillMapping
    /// Lowest the label's center may sit, so it clears the top bar.
    let minLabelY: CGFloat
    let onChange: (Quad) -> Void
    let onRemove: () -> Void
    /// A removed card's detected outline, drawn dimmed without label or ✕. Dragging it brings the card back.
    var isSuggestion = false

    @State private var moveBase: Quad?
    @State private var cornerBase: CGPoint?

    private static let handleSize: CGFloat = 44
    private static let stroke = Color.yellow

    private var corners: [(WritableKeyPath<Quad, CGPoint>, CGPoint)] {
        [(\.topLeft, card.topLeft), (\.topRight, card.topRight),
         (\.bottomRight, card.bottomRight), (\.bottomLeft, card.bottomLeft)]
    }

    var body: some View {
        let points = [card.topLeft, card.topRight, card.bottomRight, card.bottomLeft]
            .map { mapping.viewPoint(fromImage: $0) }
        let shown = displayedImageSize
        ZStack {
            outline(points)
                .fill(Self.stroke.opacity(0.1))
                .gesture(moveGesture(shown: shown))
            outline(points)
                .stroke(Self.stroke, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .allowsHitTesting(false)
            ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
                handle(for: corner.0, at: mapping.viewPoint(fromImage: corner.1), shown: shown)
            }
            if !isSuggestion {
                label(above: points)
            }
        }
        .opacity(isSuggestion ? 0.4 : 1)
    }

    // MARK: - Pieces

    private func outline(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private func label(above points: [CGPoint]) -> some View {
        let top = points.map(\.y).min() ?? 0
        let midX = points.map(\.x).reduce(0, +) / CGFloat(max(points.count, 1))
        return HStack(spacing: 0) {
            Text("Grey card · drag to adjust")
                .font(.caption)
                .padding(.leading, 12)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove grey card")
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.6), in: Capsule())
        .position(x: midX, y: min(max(top - 30, minLabelY), max(mapping.viewSize.height - 30, minLabelY)))
    }

    private func handle(for key: WritableKeyPath<Quad, CGPoint>, at point: CGPoint, shown: CGSize) -> some View {
        Circle()
            .fill(Self.stroke)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
            .frame(width: Self.handleSize, height: Self.handleSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named(ColorCaptureStageSpace.name))
                    .onChanged { value in
                        guard shown.width > 0, shown.height > 0 else { return }
                        let base = cornerBase ?? card[keyPath: key]
                        cornerBase = base
                        var moved = card
                        moved[keyPath: key] = CGPoint(
                            x: min(max(base.x + value.translation.width / shown.width, 0), 1),
                            y: min(max(base.y + value.translation.height / shown.height, 0), 1))
                        onChange(moved)
                    }
                    .onEnded { _ in cornerBase = nil }
            )
            .position(point)
    }

    private func moveGesture(shown: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named(ColorCaptureStageSpace.name))
            .onChanged { value in
                guard shown.width > 0, shown.height > 0 else { return }
                let base = moveBase ?? card
                moveBase = base
                // Clamp the translation, not the corners, so the card keeps its shape.
                let xs = [base.topLeft, base.topRight, base.bottomRight, base.bottomLeft].map(\.x)
                let ys = [base.topLeft, base.topRight, base.bottomRight, base.bottomLeft].map(\.y)
                let dx = min(max(value.translation.width / shown.width, -(xs.min() ?? 0)), 1 - (xs.max() ?? 1))
                let dy = min(max(value.translation.height / shown.height, -(ys.min() ?? 0)), 1 - (ys.max() ?? 1))
                onChange(base.translated(by: CGVector(dx: dx, dy: dy)))
            }
            .onEnded { _ in moveBase = nil }
    }

    /// The whole image's size in view points (larger than the view when cropped).
    private var displayedImageSize: CGSize {
        let origin = mapping.viewPoint(fromImage: .zero)
        let far = mapping.viewPoint(fromImage: CGPoint(x: 1, y: 1))
        return CGSize(width: far.x - origin.x, height: far.y - origin.y)
    }
}
