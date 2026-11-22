//
//  DragAutoScroll.swift
//  SpoolKid
//
//  Purpose: Whether a dragging finger is asking the list to scroll, and which
//  row to scroll to next. Geometry only — the view owns the `ScrollViewProxy`
//  and the ticking, this owns the decisions, so they are tested without a
//  device.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CoreGraphics
import Foundation

nonisolated enum DragAutoScroll {
    enum Edge: Equatable, Sendable {
        case top
        case bottom
    }

    /// How close to an edge the finger has to get before the list starts
    /// moving. Roughly two rows, so the zone is reachable without pinning the
    /// finger to the bezel.
    static let zoneDepth: CGFloat = 90

    /// The edge the finger is asking for, or `nil` for the neutral middle.
    ///
    /// `bounds` is the list's own rect in the same space the drag reports in
    /// (`ArrangeSpace`).
    static func edge(for point: CGPoint, in bounds: CGRect, depth: CGFloat = zoneDepth) -> Edge? {
        guard bounds.width > 0, bounds.height > 0, depth > 0 else { return nil }

        // A point nowhere near the list is not a drag toward its edge. This is
        // not hypothetical: `dragLocation` is (0, 0) until the first gesture
        // update lands, and against a list that starts below a navigation bar
        // that would otherwise read as "hard against the top" and scroll.
        guard bounds.insetBy(dx: -depth, dy: -depth).contains(point) else { return nil }

        // The two zones must never meet: on a short list a full-depth zone at
        // each end would leave no neutral band, so every position in it would
        // scroll and the drag could not be aimed at all.
        let zone = min(depth, bounds.height / 3)

        if point.y < bounds.minY + zone { return .top }
        if point.y > bounds.maxY - zone { return .bottom }
        return nil
    }

    /// Where to start counting from: the index, in the list's own order, of the
    /// header nearest the finger. `nil` when nothing on screen has been
    /// measured yet, which is the view's cue not to scroll.
    static func nearestIndex(to y: CGFloat, orderedNames: [String], frames: [String: CGRect]) -> Int? {
        orderedNames.indices
            .compactMap { index in frames[orderedNames[index]].map { (index: index, distance: abs($0.midY - y)) } }
            .min { $0.distance < $1.distance }?
            .index
    }
}
