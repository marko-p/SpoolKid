//
//  PlannerImage.swift
//  SpoolKid
//
//  Purpose: The picture a plan starts from: the colour under a tap, and
//  suggested colours by clustering. A photo from the library has no reference
//  card, so its colours are as the camera saw them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import UIKit

nonisolated struct PlannerImage: Sendable {
    /// A suggested colour and a spot of the picture that has it.
    struct SuggestedColor: Equatable, Sendable {
        let hex: String
        /// Normalized, top-left origin, like a tap.
        let point: CGPoint
    }

    /// Plenty for a colour, and small enough to cluster at once.
    static let maxDimension: CGFloat = 512
    /// The circle averaged under a tap, as a fraction of the width.
    static let sampleRadius = 0.015
    /// Spots reading within this (squared Lab distance) of the best are
    /// equally good places for a suggestion's marker.
    static let markerSlack = 4.0

    let grid: PixelGrid

    init(grid: PixelGrid) {
        self.grid = grid
    }

    /// Nil when the image has no pixels to read.
    init?(image: UIImage) {
        let scale = min(1, Self.maxDimension / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing also applies the photo's orientation.
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = upright.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let curve = (0...255).map { ColorMatching.linearized(Double($0) / 255) }
        let pixels = stride(from: 0, to: bytes.count, by: 4).map {
            LinearRGB(r: curve[Int(bytes[$0])], g: curve[Int(bytes[$0 + 1])], b: curve[Int(bytes[$0 + 2])])
        }
        self.init(grid: PixelGrid(width: width, height: height, pixels: pixels))
    }

    /// The colour under a tap, highlights and shadows left out. Nil off the image.
    func color(at point: CGPoint) -> String? {
        ColorSampler.sample(grid.pixels(inCircleCenter: point, radiusFraction: Self.sampleRadius))?.color.hex
    }

    /// `count` colours by k-means in Lab, the largest first. Seeded by taking
    /// the colour farthest from those already chosen, so the same picture
    /// always suggests the same colours. Each is marked where a tap reads it
    /// best, of up to 64 of its pixels spread through the cluster, nearest
    /// the middle of those spots.
    func suggestedColors(count: Int) -> [SuggestedColor] {
        guard count > 0, !grid.pixels.isEmpty else { return [] }
        let step = max(1, grid.pixels.count / 3000)
        let samples = stride(from: 0, to: grid.pixels.count, by: step).compactMap { index -> (LinearRGB, [Double], Int)? in
            let pixel = grid.pixels[index]
            guard let lab = ColorMatching.lab(from: pixel.hex) else { return nil }
            return (pixel, [lab.l, lab.a, lab.b], index)
        }
        guard let first = samples.first else { return [] }

        func squared(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        }
        var centers = [first.1]
        while centers.count < min(count, samples.count) {
            let next = samples.max { lhs, rhs in
                centers.map { squared(lhs.1, $0) }.min() ?? 0 < centers.map { squared(rhs.1, $0) }.min() ?? 0
            }
            guard let next else { break }
            centers.append(next.1)
        }

        var members = Array(repeating: [Int](), count: centers.count)
        for _ in 0..<12 {
            members = Array(repeating: [], count: centers.count)
            for (index, sample) in samples.enumerated() {
                let nearest = centers.indices.min { squared(sample.1, centers[$0]) < squared(sample.1, centers[$1]) } ?? 0
                members[nearest].append(index)
            }
            for cluster in centers.indices where !members[cluster].isEmpty {
                let count = Double(members[cluster].count)
                centers[cluster] = (0..<3).map { axis in
                    members[cluster].reduce(0) { $0 + samples[$1].1[axis] } / count
                }
            }
        }
        return members.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.map { cluster in
            let hex = ColorSampler.mean(cluster.map { samples[$0].0 }).hex
            let lab = ColorMatching.lab(from: hex).map { [$0.l, $0.a, $0.b] } ?? samples[cluster[0]].1
            let spread = stride(from: 0, to: cluster.count, by: max(1, cluster.count / 64)).map { cluster[$0] }
            let points = spread.map { member -> (point: CGPoint, distance: Double) in
                let index = samples[member].2
                let point = CGPoint(
                    x: (Double(index % grid.width) + 0.5) / Double(grid.width),
                    y: (Double(index / grid.width) + 0.5) / Double(grid.height)
                )
                let read = color(at: point).flatMap(ColorMatching.lab(from:)).map { [$0.l, $0.a, $0.b] }
                return (point, read.map { squared($0, lab) } ?? .infinity)
            }
            // Many spots read the colour; the one nearest the middle of its
            // pixels sits inside it rather than on an edge.
            let best = points.map(\.distance).min() ?? .infinity
            let good = points.filter { $0.distance <= best + Self.markerSlack }.map(\.point)
            let middle = CGPoint(
                x: good.map(\.x).reduce(0, +) / Double(max(1, good.count)),
                y: good.map(\.y).reduce(0, +) / Double(max(1, good.count))
            )
            let point = good.min { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) } ?? .zero
            return SuggestedColor(hex: hex, point: point)
        }
    }
}
