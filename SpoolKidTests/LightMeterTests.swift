//
//  LightMeterTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for the color-capture light meter: EV100 from exposure
//  settings, the too-dark threshold, and the time-window smoother that keeps
//  one dark frame from raising the warning.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

struct LightMeterTests {

    // MARK: - EV100

    @Test func ev100OfSunny16() {
        #expect(abs(LightMeter.ev100(aperture: 16, exposureDuration: 1.0 / 100, iso: 100) - log2(25600)) < 1e-9)
    }

    @Test func dimRoomIsTooDark() {
        #expect(LightMeter.level(forEV100: LightMeter.ev100(aperture: 1.78, exposureDuration: 1.0 / 30, iso: 1000)) == .tooDark)
    }

    @Test func litRoomIsOK() {
        #expect(LightMeter.level(forEV100: LightMeter.ev100(aperture: 1.78, exposureDuration: 1.0 / 60, iso: 100)) == .ok)
    }

    // MARK: - Smoother

    @Test func smootherIgnoresOneDarkFrame() {
        var s = LightLevelSmoother()
        for i in 0..<10 { _ = s.add(ev100: 8, at: Double(i) * 0.1) }
        #expect(s.add(ev100: 2, at: 1.0) == .ok)
    }

    @Test func smootherForgetsOldSamples() {
        var s = LightLevelSmoother()
        _ = s.add(ev100: 12, at: 0)
        for i in 0..<5 { _ = s.add(ev100: 3, at: 2.0 + Double(i) * 0.1) }
        #expect(s.add(ev100: 3, at: 2.5) == .tooDark)
    }

    @Test func smootherPrunesSamplesOlderThanWindow() {
        var s = LightLevelSmoother()
        _ = s.add(ev100: 12, at: 0)
        #expect(s.add(ev100: 3, at: 2.0) == .tooDark)
    }

    // MARK: - Non-finite readings

    @Test func nonFiniteSampleIsSkipped() {
        var nan = LightLevelSmoother()
        _ = nan.add(ev100: 8, at: 0)
        _ = nan.add(ev100: .nan, at: 0.1)
        #expect(nan.add(ev100: 2, at: 0.2) == .tooDark)

        var inf = LightLevelSmoother()
        _ = inf.add(ev100: 8, at: 0)
        _ = inf.add(ev100: .infinity, at: 0.1)
        #expect(inf.add(ev100: 2, at: 0.2) == .tooDark)
    }

    @Test func nonFiniteSampleAfterWindowIsSkipped() {
        var s = LightLevelSmoother()
        _ = s.add(ev100: 2, at: 0)
        _ = s.add(ev100: .nan, at: 2.0)
        #expect(s.add(ev100: 3, at: 2.5) == .tooDark)
    }

    @Test func allNonFiniteWindowFailsOpen() {
        var s = LightLevelSmoother()
        #expect(s.add(ev100: .nan, at: 0) == .ok)
        #expect(s.add(ev100: .infinity, at: 0.5) == .ok)
    }
}
