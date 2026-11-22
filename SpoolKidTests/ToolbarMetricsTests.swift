//
//  ToolbarMetricsTests.swift
//  SpoolKidTests
//

import Testing
import CoreGraphics
@testable import SpoolKid

struct ToolbarMetricsTests {
    @Test func collapsesWithTwoControlsWhenScrolledIn() {
        #expect(ToolbarMetrics.shouldCollapse(collapsibleCount: 2, transitionProgress: 0.8) == true)
    }

    @Test func doesNotCollapseSingleControl() {
        #expect(ToolbarMetrics.shouldCollapse(collapsibleCount: 1, transitionProgress: 1.0) == false)
    }

    @Test func doesNotCollapseBeforeThreshold() {
        #expect(ToolbarMetrics.shouldCollapse(collapsibleCount: 3, transitionProgress: 0.2) == false)
    }

    @Test func collapsesExactlyAtBoundaryProgress() {
        // threshold is exclusive: just past it collapses, at/below does not.
        #expect(ToolbarMetrics.shouldCollapse(collapsibleCount: 2, transitionProgress: 0.5) == false)
        #expect(ToolbarMetrics.shouldCollapse(collapsibleCount: 2, transitionProgress: 0.51) == true)
    }
}
