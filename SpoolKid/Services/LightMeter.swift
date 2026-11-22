//
//  LightMeter.swift
//  SpoolKid
//
//  Purpose: Light-level check for camera color capture. Converts the camera's
//  aperture, exposure time and ISO into EV100, warns when the scene is too dark
//  for a trustworthy reading, and smooths the warning over a short time window
//  so a single dark frame does not flicker it on. Pure value types; no UIKit.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

// MARK: - LightLevel

/// Whether the scene is bright enough for a color reading. Advice only: the
/// shutter is never disabled by it.
nonisolated enum LightLevel: Equatable, Sendable {
    case ok
    case tooDark
}

// MARK: - LightMeter

nonisolated enum LightMeter {

    /// EV100 below which the scene is flagged as too dark (≈160 lux). Tune on device.
    static let tooDarkBelowEV100 = 6.0

    /// EV100 = log2(N² / t) − log2(ISO / 100), for aperture N, exposure time t in
    /// seconds, and ISO. Higher means brighter.
    static func ev100(aperture: Double, exposureDuration: Double, iso: Double) -> Double {
        log2(aperture * aperture / exposureDuration) - log2(iso / 100)
    }

    static func level(forEV100 ev: Double) -> LightLevel {
        ev < tooDarkBelowEV100 ? .tooDark : .ok
    }
}

// MARK: - LightLevelSmoother

/// Averages EV100 readings over a trailing time window before judging the light
/// level. Non-finite readings are skipped; with no finite reading in the window
/// the level is `.ok`, since the warning is advice and should fail open.
nonisolated struct LightLevelSmoother: Sendable {

    let window: TimeInterval
    private var samples: [(ev100: Double, time: TimeInterval)] = []

    init(window: TimeInterval = 1.0) {
        self.window = window
    }

    /// Records one reading taken at `time` and returns the level of the mean EV100
    /// over readings within `window` of `time`. A reading exactly `window` old still counts.
    /// Times must be non-decreasing across calls: readings are pruned against the newest time.
    mutating func add(ev100: Double, at time: TimeInterval) -> LightLevel {
        let cutoff = time - window
        samples.removeAll { $0.time < cutoff }
        if ev100.isFinite {
            samples.append((ev100: ev100, time: time))
        }
        guard !samples.isEmpty else { return .ok }
        let mean = samples.reduce(0) { $0 + $1.ev100 } / Double(samples.count)
        return LightMeter.level(forEV100: mean)
    }
}
