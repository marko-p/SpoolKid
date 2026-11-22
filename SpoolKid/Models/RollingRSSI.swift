//
//  RollingRSSI.swift
//  SpoolKid
//
//  Purpose: Average a peripheral's signal strength over a short window, so a
//  list ordered by "which one is nearest" can be ordered by signal strength
//  without the rows trading places while they are read.
//
//  A single RSSI reading wanders by several dB between one advertisement and
//  the next; the mean over a few seconds does not.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct RollingRSSI: Equatable {

    struct Sample: Equatable {
        let at: Date
        let value: Int
    }

    /// Long enough to smooth the hop between advertisements, short enough that
    /// picking the phone up and walking to the bench is reflected before the
    /// user has finished looking.
    static let window: TimeInterval = 3

    private(set) var samples: [Sample] = []

    /// Record a sighting and forget the ones that have aged out.
    mutating func add(_ value: Int, at now: Date = Date()) {
        samples.append(Sample(at: now, value: value))
        samples.removeAll { now.timeIntervalSince($0.at) > Self.window }
    }

    /// The mean over the window. Nil until something has been seen — a
    /// peripheral with no sighting has no signal strength, and reporting one
    /// (0 dBm, which reads as "touching the phone") would sort it to the top.
    var average: Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0) { $0 + $1.value }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}
