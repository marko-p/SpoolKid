//
//  PrinterOutlineHeader.swift
//  SpoolKid
//
//  Purpose: The Printer tab's header: a line drawing of the U1 seen from
//  the front and above — its top as a trapezoid, the four toolheads at the
//  back with their cables, the carriage on its two rods, the front panel —
//  with the printer's name on the panel and its status on the drawn screen
//  (owner, 2026-11-09). Drawn, not a photo: the app shows no brand images.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Where things sit in the drawing, in its own 445 × 270 units, so the text
/// is laid out on the same grid as the lines. Only the last stretch of the
/// cables is drawn, so the cards stay in view.
nonisolated enum U1Outline {
    static let size = CGSize(width: 445, height: 270)

    /// The top, narrower at the back for the perspective.
    static let backLeft = CGPoint(x: 52, y: 40)
    static let backRight = CGPoint(x: 393, y: 40)
    static let frontLeft = CGPoint(x: 14, y: 164)
    static let frontRight = CGPoint(x: 431, y: 164)

    /// The opening the toolheads and the carriage sit in. Its sides run
    /// parallel to the top's.
    static let opening = [
        CGPoint(x: 84, y: 50), CGPoint(x: 361, y: 50), CGPoint(x: 392, y: 150), CGPoint(x: 53, y: 150)
    ]

    static let toolheads = [109, 167, 225, 283].map { CGRect(x: $0, y: 30, width: 52, height: 70) }
    static let cableTops: [CGFloat] = [128, 193, 256, 312]
    /// The two rods the carriage runs along, back first.
    static let rods = [CGRect(x: 70, y: 96, width: 305, height: 4), CGRect(x: 62, y: 124, width: 321, height: 4)]
    /// Runs down past the opening's front edge, which hides its bottom.
    static let carriage = CGRect(x: 203, y: 78, width: 56, height: 100)
    /// The fan on the carriage's front: half its width across, as on the U1.
    static let fan = CGPoint(x: 231, y: 130)
    static let fanRadius: CGFloat = 14

    static let screen = CGRect(x: 296, y: 182, width: 96, height: 58)
    /// The front panel left of the screen, where nothing is drawn.
    static let label = CGRect(x: 40, y: 178, width: 240, height: 64)
}

struct PrinterOutlineHeader: View {
    let name: String
    let detail: String?
    let status: String

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / U1Outline.size.width
            ZStack(alignment: .topLeading) {
                drawing(scale: scale)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: U1Outline.label.width * scale, height: U1Outline.label.height * scale, alignment: .leading)
                .offset(x: U1Outline.label.minX * scale, y: U1Outline.label.minY * scale)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .frame(width: U1Outline.screen.width * scale, height: U1Outline.screen.height * scale)
                    .offset(x: U1Outline.screen.minX * scale, y: U1Outline.screen.minY * scale)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .offset(
                        x: (U1Outline.screen.maxX + 12) * scale,
                        y: U1Outline.screen.midY * scale - 9
                    )
            }
        }
        .aspectRatio(U1Outline.size, contentMode: .fit)
        // Past this the name outgrows the panel; it still scales down to fit.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }

    private func drawing(scale: CGFloat) -> some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            let line = StrokeStyle(lineWidth: 1.5 / scale, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.style(.secondary)
            let hidden = GraphicsContext.Shading.color(Color(uiColor: .systemBackground))
            let bottom = U1Outline.size.height

            // The outside: front panel sides, then the top's sides and back,
            // its back corners rounded.
            var outside = Path()
            outside.move(to: CGPoint(x: U1Outline.frontLeft.x, y: bottom))
            outside.addArc(tangent1End: U1Outline.frontLeft, tangent2End: U1Outline.backLeft, radius: 24)
            outside.addArc(tangent1End: U1Outline.backLeft, tangent2End: U1Outline.backRight, radius: 16)
            outside.addArc(tangent1End: U1Outline.backRight, tangent2End: U1Outline.frontRight, radius: 16)
            outside.addArc(tangent1End: U1Outline.frontRight, tangent2End: CGPoint(x: U1Outline.frontRight.x, y: bottom), radius: 24)
            outside.addLine(to: CGPoint(x: U1Outline.frontRight.x, y: bottom))
            context.stroke(outside, with: ink, style: line)

            // The front edge, curving up into the sides at the rounded front
            // corners.
            var front = Path()
            front.move(to: point(onSideFrom: U1Outline.frontLeft, to: U1Outline.backLeft, atY: U1Outline.frontLeft.y - 16))
            front.addQuadCurve(to: CGPoint(x: U1Outline.frontLeft.x + 20, y: U1Outline.frontLeft.y), control: U1Outline.frontLeft)
            front.addLine(to: CGPoint(x: U1Outline.frontRight.x - 20, y: U1Outline.frontRight.y))
            front.addQuadCurve(
                to: point(onSideFrom: U1Outline.frontRight, to: U1Outline.backRight, atY: U1Outline.frontRight.y - 16),
                control: U1Outline.frontRight
            )
            context.stroke(front, with: ink, style: line)

            let opening = roundedPolygon(U1Outline.opening, radius: 8)
            context.stroke(opening, with: ink, style: line)

            // Toolheads stand in front of the opening's back edge, so they
            // hide it; each has its cable rising out of the top.
            for (head, top) in zip(U1Outline.toolheads, U1Outline.cableTops) {
                let body = Path(roundedRect: head, cornerRadius: 5)
                context.fill(body, with: hidden)
                var detail = body
                detail.move(to: CGPoint(x: head.minX + 9, y: head.minY + 18))
                detail.addLine(to: CGPoint(x: head.maxX - 9, y: head.minY + 18))
                context.stroke(detail, with: ink, style: line)
                for side: CGFloat in [-3, 3] {
                    var cable = Path()
                    cable.move(to: CGPoint(x: head.midX + side, y: head.minY))
                    cable.addCurve(
                        to: CGPoint(x: top + side, y: 0),
                        control1: CGPoint(x: head.midX + side, y: head.minY - 16),
                        control2: CGPoint(x: top + side, y: 14)
                    )
                    context.stroke(cable, with: ink, style: line)
                }
            }

            for rod in U1Outline.rods {
                let shape = Path(roundedRect: rod, cornerRadius: 2)
                context.fill(shape, with: hidden)
                context.stroke(shape, with: ink, style: line)
            }

            // The carriage rides on the rods, in front of everything behind
            // it, its fan inside; the frame's front hides its bottom.
            context.drawLayer { layer in
                // Above the opening's front edge, leaving that line whole.
                let edge = U1Outline.opening[3].y - line.lineWidth / 2
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: U1Outline.size.width, height: edge)))
                let carriage = Path(roundedRect: U1Outline.carriage, cornerRadius: 12)
                layer.fill(carriage, with: hidden)
                layer.stroke(carriage, with: ink, style: line)
                let r = U1Outline.fanRadius
                let fan = U1Outline.fan
                layer.stroke(Path(ellipseIn: CGRect(x: fan.x - r, y: fan.y - r, width: r * 2, height: r * 2)), with: ink, style: line)
                layer.stroke(Path(ellipseIn: CGRect(x: fan.x - 4, y: fan.y - 4, width: 8, height: 8)), with: ink, style: line)
            }

            context.stroke(Path(roundedRect: U1Outline.screen, cornerRadius: 6), with: ink, style: line)
        }
        // The cables fade in from the top; the panel fades out at the bottom.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// The point at height `y` on the straight side from `a` to `b`.
    private func point(onSideFrom a: CGPoint, to b: CGPoint, atY y: CGFloat) -> CGPoint {
        let t = (y - a.y) / (b.y - a.y)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
    }

    private func roundedPolygon(_ corners: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        let count = corners.count
        let start = CGPoint(
            x: (corners[count - 1].x + corners[0].x) / 2, y: (corners[count - 1].y + corners[0].y) / 2
        )
        path.move(to: start)
        for index in 0..<count {
            path.addArc(tangent1End: corners[index], tangent2End: corners[(index + 1) % count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    PrinterOutlineHeader(name: "Snapmaker U1", detail: "Extended firmware", status: "Idle")
        .padding()
}
