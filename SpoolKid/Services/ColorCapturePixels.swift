//
//  ColorCapturePixels.swift
//  SpoolKid
//
//  Purpose: Pixel model for camera color capture: linear-light RGB values,
//  a row-major pixel grid with circular sampling and perspective rectification,
//  the quadrilateral of a detected card, and the aspect-fill mapping between
//  the camera preview and the captured image. Pure value types; no UIKit.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CoreGraphics
import Foundation

// MARK: - LinearRGB

/// One pixel in linear-light sRGB (components 0...1). Averaging and luminance
/// are only meaningful in linear light, so grids hold this type, not hex.
nonisolated struct LinearRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses an sRGB hex string (`#` and 3-char forms accepted) into linear light.
    init?(hex: String) {
        guard let rgb = ColorMatching.parseHex(hex) else { return nil }
        self.init(r: ColorMatching.linearized(rgb.r),
                  g: ColorMatching.linearized(rgb.g),
                  b: ColorMatching.linearized(rgb.b))
    }

    /// Relative luminance (Rec. 709 weights) of the linear values.
    var luminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Largest channel, linear light.
    var maxChannel: Double {
        max(r, g, b)
    }

    /// Relative spread of the channels: (max − min) / max, 0 for black.
    var chroma: Double {
        let peak = maxChannel
        guard peak > 0 else { return 0 }
        return (peak - min(r, g, b)) / peak
    }

    /// Uppercase `RRGGBB` (no `#`) in sRGB, rounded to the nearest byte per channel.
    /// Non-finite channels are treated as 0.
    var hex: String {
        func byte(_ linear: Double) -> Int {
            let finite = linear.isFinite ? linear : 0
            return Int((ColorMatching.encoded(finite) * 255).rounded())
        }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

// MARK: - Quad

/// Four corners of a detected card in normalized image coordinates
/// (0...1, top-left origin), in clockwise order from the top-left corner.
nonisolated struct Quad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    func translated(by offset: CGVector) -> Quad {
        func move(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + offset.dx, y: p.y + offset.dy)
        }
        return Quad(topLeft: move(topLeft), topRight: move(topRight),
                    bottomRight: move(bottomRight), bottomLeft: move(bottomLeft))
    }
}

// MARK: - PixelGrid

/// A row-major grid of linear-light pixels with a top-left origin.
nonisolated struct PixelGrid: Equatable, Sendable {
    let width: Int
    let height: Int
    var pixels: [LinearRGB]

    subscript(x: Int, y: Int) -> LinearRGB {
        pixels[y * width + x]
    }

    /// Pixels whose centers fall inside a circle. `center` is normalized
    /// (0...1, top-left origin); `radiusFraction` is the radius as a fraction of `width`.
    /// Pixels outside the grid are never returned. A non-finite or negative
    /// center or radius samples nothing.
    func pixels(inCircleCenter center: CGPoint, radiusFraction: Double) -> [LinearRGB] {
        let cx = Double(center.x) * Double(width)
        let cy = Double(center.y) * Double(height)
        let radius = radiusFraction * Double(width)
        guard cx.isFinite, cy.isFinite, radius.isFinite, radius >= 0 else { return [] }

        // Bounding box in Double, clamped before any Int conversion.
        let loX = (cx - radius).rounded(.down), hiX = (cx + radius).rounded(.up)
        let loY = (cy - radius).rounded(.down), hiY = (cy + radius).rounded(.up)
        guard loX <= Double(width - 1), hiX >= 0, loY <= Double(height - 1), hiY >= 0 else { return [] }
        let x0 = Int(max(loX, 0)), x1 = Int(min(hiX, Double(width - 1)))
        let y0 = Int(max(loY, 0)), y1 = Int(min(hiY, Double(height - 1)))
        guard x0 <= x1, y0 <= y1 else { return [] }

        var result: [LinearRGB] = []
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= radius * radius {
                    result.append(self[x, y])
                }
            }
        }
        return result
    }

    /// Resamples the quadrilateral `quad` to an upright `width` × `height` grid.
    /// Each output cell samples the bilinear interpolation of the four corners at
    /// its center, then takes the nearest source pixel, clamped to the grid bounds.
    /// A non-finite quad corner maps to the nearest in-bounds pixel; an empty
    /// source grid yields black.
    func rectified(_ quad: Quad, width outWidth: Int, height outHeight: Int) -> PixelGrid {
        guard width > 0, height > 0 else {
            return PixelGrid(width: outWidth, height: outHeight,
                             pixels: Array(repeating: LinearRGB(r: 0, g: 0, b: 0), count: outWidth * outHeight))
        }
        var out: [LinearRGB] = []
        out.reserveCapacity(outWidth * outHeight)
        for j in 0..<outHeight {
            let v = (Double(j) + 0.5) / Double(outHeight)
            for i in 0..<outWidth {
                let u = (Double(i) + 0.5) / Double(outWidth)
                let top = Self.lerp(quad.topLeft, quad.topRight, u)
                let bottom = Self.lerp(quad.bottomLeft, quad.bottomRight, u)
                let p = Self.lerp(top, bottom, v)
                let x = Self.pixelIndex(Double(p.x), count: width)
                let y = Self.pixelIndex(Double(p.y), count: height)
                out.append(self[x, y])
            }
        }
        return PixelGrid(width: outWidth, height: outHeight, pixels: out)
    }

    /// Per-pixel mean of equally sized grids; nil when the list is empty or sizes differ.
    static func average(_ grids: [PixelGrid]) -> PixelGrid? {
        guard let first = grids.first else { return nil }
        guard grids.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return nil }
        let count = Double(grids.count)
        let pixels = (0..<first.pixels.count).map { index in
            LinearRGB(
                r: grids.reduce(0) { $0 + $1.pixels[index].r } / count,
                g: grids.reduce(0) { $0 + $1.pixels[index].g } / count,
                b: grids.reduce(0) { $0 + $1.pixels[index].b } / count)
        }
        return PixelGrid(width: first.width, height: first.height, pixels: pixels)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * t,
                y: Double(a.y) + (Double(b.y) - Double(a.y)) * t)
    }

    /// Nearest pixel index for a normalized coordinate, clamped to `0..<count`.
    /// NaN maps to 0; the clamp happens in Double before the Int conversion.
    private static func pixelIndex(_ normalized: Double, count: Int) -> Int {
        let scaled = normalized * Double(count)
        guard !scaled.isNaN else { return 0 }
        return Int(min(max(scaled, 0), Double(count - 1)).rounded(.down))
    }
}

// MARK: - AspectFillMapping

/// Maps between a view that shows an image with aspect-fill (scaled to cover,
/// centered, overflow cropped) and normalized image coordinates.
nonisolated struct AspectFillMapping: Equatable, Sendable {
    let viewSize: CGSize
    let imageSize: CGSize

    /// Points per image pixel when the image covers the view.
    private var scale: Double {
        max(Double(viewSize.width) / Double(imageSize.width),
            Double(viewSize.height) / Double(imageSize.height))
    }

    /// View-space position of the image's top-left corner (zero or negative: cropped).
    private var origin: CGPoint {
        let shownWidth = Double(imageSize.width) * scale
        let shownHeight = Double(imageSize.height) * scale
        return CGPoint(x: (Double(viewSize.width) - shownWidth) / 2,
                       y: (Double(viewSize.height) - shownHeight) / 2)
    }

    /// True when the mapping cannot be inverted (an empty view or image, or a
    /// non-finite scale). Degenerate mappings return zero rather than NaN.
    private var isDegenerate: Bool {
        guard imageSize.width > 0, imageSize.height > 0 else { return true }
        return !(scale.isFinite && scale > 0)
    }

    /// Normalized image point (0...1, top-left origin) under a view point.
    /// Returns `.zero` for a degenerate mapping.
    func imagePoint(fromView point: CGPoint) -> CGPoint {
        guard !isDegenerate else { return .zero }
        let o = origin
        return CGPoint(x: (Double(point.x) - Double(o.x)) / scale / Double(imageSize.width),
                       y: (Double(point.y) - Double(o.y)) / scale / Double(imageSize.height))
    }

    /// View point showing a normalized image point. Returns `.zero` for a degenerate mapping.
    func viewPoint(fromImage point: CGPoint) -> CGPoint {
        guard !isDegenerate else { return .zero }
        let o = origin
        return CGPoint(x: Double(point.x) * Double(imageSize.width) * scale + Double(o.x),
                       y: Double(point.y) * Double(imageSize.height) * scale + Double(o.y))
    }

    /// Image width fraction (0...1) covered by a horizontal length in view points.
    /// Returns 0 for a degenerate mapping.
    func imageWidthFraction(fromViewLength length: CGFloat) -> Double {
        guard !isDegenerate else { return 0 }
        return Double(length) / scale / Double(imageSize.width)
    }
}
