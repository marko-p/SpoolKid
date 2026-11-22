//
//  LoadoutPicks.swift
//  SpoolKid
//
//  Purpose: The colours picked for Color Matching, in order, and how a match
//  reads in words. Pure, so the screens only render it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LoadoutPicks: Codable, Equatable, Sendable {
    static let cap = 12

    struct Pick: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var hex: String
        /// Where it was tapped, 0…1 of the image. Nil for a suggested colour.
        var point: Point?
    }

    struct Point: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
    }

    private(set) var picks: [Pick] = []

    /// False at the cap.
    @discardableResult
    mutating func add(hex: String, point: Point? = nil) -> Bool {
        guard picks.count < Self.cap else { return false }
        picks.append(Pick(hex: hex, point: point))
        return true
    }

    mutating func remove(id: Pick.ID) {
        picks.removeAll { $0.id == id }
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { picks[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { picks.remove(at: index) }
        picks.insert(contentsOf: moving, at: destination - before)
    }

    var hexes: [String] { picks.map(\.hex) }
}

/// How a match reads.
nonisolated enum LoadoutPlanText {
    static func label(deltaE: Double) -> String {
        if deltaE < 2 { return "Looks the same" }
        if deltaE < 5 { return "Close" }
        return "Visible difference"
    }
}
