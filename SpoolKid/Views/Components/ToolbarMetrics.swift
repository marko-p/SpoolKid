//
//  ToolbarMetrics.swift
//  SpoolKid
//
//  Purpose: Single source of truth for trailing-toolbar control size + spacing
//  across HarmonizedSearchList views, plus the pure rule for collapsing those
//  controls into a "…" menu when the search field lifts into the toolbar.
//

import CoreGraphics

nonisolated enum ToolbarMetrics {
    /// Horizontal spacing between inline trailing controls, shared by every
    /// HarmonizedSearchList view.
    static let controlSpacing: CGFloat = 18

    /// Point size for inline trailing-control glyphs, for consistent sizing.
    static let iconPointSize: CGFloat = 17

    /// Collapse trailing controls into a single "…" menu once the search field
    /// has substantially entered the toolbar AND there are 2+ collapsible
    /// controls crowding it. `threshold` is exclusive.
    static func shouldCollapse(
        collapsibleCount: Int,
        transitionProgress: CGFloat,
        threshold: CGFloat = 0.5
    ) -> Bool {
        collapsibleCount >= 2 && transitionProgress > threshold
    }
}
