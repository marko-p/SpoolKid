//
//  ColorCaptureModelTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for the color-capture state machine: the first-run guide, the
//  persisted circle radius, shutter → lock → half-second average → review, the
//  capture timeout, retake, circle movement, card detection and removal, and the
//  light level. A fake frame source stands in for the camera, and the capture
//  timeout is recorded and fired by the test, never slept.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import SpoolKid

// MARK: - Test doubles

/// Records the camera calls the model makes and delivers frames on demand.
@MainActor
final class FakeFrameSource: ColorCaptureFrameSource {
    var onFrame: ((ColorCaptureFrame) -> Void)?
    let previewSession: AVCaptureSession? = nil
    var wantsFullFrames = false
    var detectsCards = true

    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var lockCallCount = 0
    private(set) var unlockCalled = false
    private var lockCompletion: (@MainActor (TimeInterval) -> Void)?

    func start() {
        startCalled = true
    }

    func stop() {
        stopCalled = true
    }

    func lockExposureAndWhiteBalance(completion: @escaping @MainActor (TimeInterval) -> Void) {
        lockCallCount += 1
        lockCompletion = completion
    }

    func unlockExposureAndWhiteBalance() {
        unlockCalled = true
    }

    /// Completes the pending lock, as the camera does with the first frame after it takes effect.
    func completeLock(at timestamp: TimeInterval) {
        lockCompletion?(timestamp)
    }

    func send(_ frame: ColorCaptureFrame) {
        onFrame?(frame)
    }
}

/// Holds the timeouts the model schedules, so a test fires them itself.
@MainActor
final class TimeoutRecorder {
    private(set) var delays: [TimeInterval] = []
    private var actions: [@MainActor () -> Void] = []

    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        delays.append(delay)
        actions.append(action)
    }

    /// Runs the timeout scheduled by the shutter at `index` (0-based).
    func fire(_ index: Int) {
        actions[index]()
    }
}

// MARK: - Tests

@MainActor
struct ColorCaptureModelTests {

    private struct Rig {
        let model: ColorCaptureModel
        let source: FakeFrameSource
        let timeouts: TimeoutRecorder
        let defaults: UserDefaults
        let suiteName: String

        /// Deletes the suite this rig's defaults live in. Call with `defer` in each test.
        func removeDefaults() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// A model on its own defaults suite. Pass `suiteName` to reopen the same suite.
    private func makeRig(suiteName: String = "ColorCaptureModelTests-\(UUID().uuidString)") -> Rig {
        let defaults = UserDefaults(suiteName: suiteName)!
        let source = FakeFrameSource()
        let timeouts = TimeoutRecorder()
        let model = ColorCaptureModel(
            source: source,
            defaults: defaults,
            scheduleTimeout: { delay, action in timeouts.schedule(delay, action) })
        return Rig(model: model, source: source, timeouts: timeouts,
                   defaults: defaults, suiteName: suiteName)
    }

    private func uniformGrid(_ hex: String) -> PixelGrid {
        let color = LinearRGB(hex: hex)!
        return PixelGrid(width: 16, height: 16, pixels: Array(repeating: color, count: 16 * 16))
    }

    private func frame(_ grid: PixelGrid, at timestamp: TimeInterval, ev100: Double = 10,
                       candidates: [Quad]? = nil, image: CGImage? = nil) -> ColorCaptureFrame {
        ColorCaptureFrame(grid: grid, ev100: ev100, cardCandidates: candidates,
                          timestamp: timestamp, image: image)
    }

    /// Sends `count` frames of `grid` at 30 fps, starting at `start`.
    private func stream(_ grid: PixelGrid, from start: TimeInterval, count: Int,
                        to source: FakeFrameSource, ev100: Double = 10,
                        candidates: [Quad]? = nil) {
        for k in 0..<count {
            source.send(frame(grid, at: start + Double(k) / 30, ev100: ev100, candidates: candidates))
        }
    }

    /// A rig in review: shutter, lock at t = 10, then a full half second of `hex`.
    private func reviewRig(hex: String = "D9622B") -> Rig {
        let rig = makeRig()
        rig.model.onAppear()
        rig.model.shutter()
        rig.source.completeLock(at: 10)
        stream(uniformGrid(hex), from: 10, count: 16, to: rig.source)
        return rig
    }

    /// 120×160 scene: the cast background with a three-band grey card, darkest band first.
    /// Copied from `ColorCaptureReadingTests`.
    private static func cardScene() -> PixelGrid {
        let width = 120, height = 160
        func casted(_ c: LinearRGB) -> LinearRGB {
            LinearRGB(r: min(c.r * 1.2, 1), g: c.g, b: min(c.b * 0.8, 1))
        }
        let background = casted(LinearRGB(hex: "D9622B")!)
        let bands = [0.02, 0.12, 0.60].map { casted(LinearRGB(r: $0, g: $0, b: $0)) }
        var pixels: [LinearRGB] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let nx = (CGFloat(x) + 0.5) / CGFloat(width)
                let ny = (CGFloat(y) + 0.5) / CGFloat(height)
                var color = background
                if nx >= cardRect.minX, nx < cardRect.maxX, ny >= cardRect.minY, ny < cardRect.maxY {
                    let t = (nx - cardRect.minX) / cardRect.width
                    color = bands[min(Int(t * 3), 2)]
                }
                pixels.append(color)
            }
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }

    private static let cardRect = CGRect(x: 0.05, y: 0.70, width: 0.40, height: 0.10)

    private static func quad(_ r: CGRect) -> Quad {
        Quad(topLeft: CGPoint(x: r.minX, y: r.minY),
             topRight: CGPoint(x: r.maxX, y: r.minY),
             bottomRight: CGPoint(x: r.maxX, y: r.maxY),
             bottomLeft: CGPoint(x: r.minX, y: r.maxY))
    }

    /// A 1×1 image, standing in for the review photo.
    private static func sampleImage() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    // MARK: Guide and settings

    @Test func guideShowsOnlyFirstTime() {
        let first = makeRig()
        defer { first.removeDefaults() }
        #expect(first.model.showsGuide)
        first.model.dismissGuide()
        #expect(!first.model.showsGuide)

        let second = makeRig(suiteName: first.suiteName)
        #expect(!second.model.showsGuide)
    }

    @Test func circleRadiusPersistsAndClamps() {
        let first = makeRig()
        defer { first.removeDefaults() }
        #expect(first.model.circleRadius == 0.12)
        first.model.circleRadius = 0.5
        #expect(first.model.circleRadius == 0.30)

        let second = makeRig(suiteName: first.suiteName)
        #expect(second.model.circleRadius == 0.30)
    }

    @Test func firstFrameSetsImageSize() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.source.send(frame(uniformGrid("D9622B"), at: 0))
        #expect(rig.model.imageSize == CGSize(width: 16, height: 16))
    }

    @Test func framesBeforeAppearAreIgnored() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.source.send(frame(uniformGrid("D9622B"), at: 0))
        #expect(rig.model.imageSize == nil)
        #expect(rig.model.phase == .live)
    }

    // MARK: Capture

    @Test func shutterIgnoredWhenNotRunning() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.shutter()
        #expect(rig.model.phase == .live)

        rig.model.onAppear()
        rig.model.onDisappear()
        rig.model.shutter()
        #expect(rig.model.phase == .live)
        #expect(rig.source.lockCallCount == 0)
        #expect(rig.timeouts.delays.isEmpty)
    }

    @Test func shutterLocksAndAveragesHalfSecond() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        #expect(rig.model.phase == .capturing)
        #expect(rig.source.lockCallCount == 1)
        #expect(rig.source.wantsFullFrames)

        let grid = uniformGrid("D9622B")
        rig.source.completeLock(at: 10)
        stream(grid, from: 10, count: 15, to: rig.source)
        // Frames 10.0 through 10.467 span less than half a second.
        #expect(rig.model.phase == .capturing)
        // 10.5 completes the half second.
        rig.source.send(frame(grid, at: 10.5))
        #expect(rig.model.phase == .review)
        #expect(rig.model.reading?.rawHex == "D9622B")
        #expect(!rig.source.wantsFullFrames)
        #expect(!rig.source.unlockCalled)
    }

    @Test func framesBeforeLockAreIgnored() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()

        // Before the lock is known, nothing is collected.
        stream(uniformGrid("000000"), from: 9, count: 30, to: rig.source)
        rig.source.completeLock(at: 10)
        // A frame older than the lock timestamp is still before the lock took effect.
        rig.source.send(frame(uniformGrid("000000"), at: 9.99))
        stream(uniformGrid("D9622B"), from: 10, count: 16, to: rig.source)

        #expect(rig.model.phase == .review)
        #expect(rig.model.reading?.rawHex == "D9622B")
    }

    @Test func captureTimesOutWithoutFrames() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.source.completeLock(at: 10)
        #expect(rig.timeouts.delays == [2.0])

        rig.timeouts.fire(0)
        #expect(rig.model.phase == .live)
        #expect(rig.source.unlockCalled)
        #expect(!rig.source.wantsFullFrames)
        #expect(rig.model.reading == nil)
    }

    @Test func captureTimeoutFinishesWithCollectedFrames() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.source.completeLock(at: 10)
        stream(uniformGrid("D9622B"), from: 10, count: 2, to: rig.source)
        #expect(rig.model.phase == .capturing)

        rig.timeouts.fire(0)
        #expect(rig.model.phase == .review)
        #expect(rig.model.reading?.rawHex == "D9622B")
    }

    @Test func staleTimeoutIgnoredAfterNewShutter() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.source.completeLock(at: 10)
        stream(uniformGrid("D9622B"), from: 10, count: 16, to: rig.source)
        #expect(rig.model.phase == .review)
        rig.model.retake()

        rig.model.shutter()
        #expect(rig.source.lockCallCount == 2)
        // The first shutter's timeout must not end the second capture.
        rig.timeouts.fire(0)
        #expect(rig.model.phase == .capturing)
    }

    @Test func shutterIgnoredWhileCapturing() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.model.shutter()
        #expect(rig.source.lockCallCount == 1)
        #expect(rig.timeouts.delays.count == 1)
    }

    @Test func captureKeepsLastImage() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.source.completeLock(at: 10)
        let grid = uniformGrid("D9622B")
        rig.source.send(frame(grid, at: 10, image: Self.sampleImage()))
        // Later frames without an image must not clear the kept one.
        for k in 1...15 {
            rig.source.send(frame(grid, at: 10 + Double(k) / 30))
        }
        #expect(rig.model.phase == .review)
        #expect(rig.model.frozenImage != nil)
    }

    @Test func reviewIgnoresFrames() {
        let rig = reviewRig()
        defer { rig.removeDefaults() }
        stream(uniformGrid("000000"), from: 20, count: 30, to: rig.source)
        #expect(rig.model.phase == .review)
        #expect(rig.model.reading?.rawHex == "D9622B")
    }

    @Test func disappearStopsCameraAndDropsCapture() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        rig.model.shutter()
        rig.model.onDisappear()

        #expect(rig.source.stopCalled)
        #expect(!rig.source.wantsFullFrames)
        #expect(rig.model.phase == .live)
        // A lock that completes after leaving the screen does nothing.
        rig.source.completeLock(at: 10)
        stream(uniformGrid("D9622B"), from: 10, count: 16, to: rig.source)
        #expect(rig.model.phase == .live)
    }

    // MARK: Review

    @Test func retakeReturnsToLiveAndUnlocks() {
        let rig = reviewRig()
        defer { rig.removeDefaults() }
        rig.model.setUserCard(Self.quad(Self.cardRect))
        rig.model.retake()

        #expect(rig.model.phase == .live)
        #expect(rig.source.unlockCalled)
        #expect(rig.model.userCard == nil)
        #expect(!rig.model.cardRemoved)
        #expect(rig.model.reading == nil)
        #expect(rig.model.frozenImage == nil)
    }

    @Test func circleCenterIsClamped() {
        let rig = reviewRig()
        defer { rig.removeDefaults() }
        rig.model.moveCircle(to: CGPoint(x: 1.4, y: -0.2))
        #expect(rig.model.circleCenter == CGPoint(x: 1, y: 0))
    }

    @Test func removeCardClearsCorrection() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let scene = Self.cardScene()
        let card = Self.quad(Self.cardRect)

        rig.source.send(frame(scene, at: 0, candidates: [card]))
        #expect(rig.model.detectedCard == card)

        rig.model.shutter()
        rig.source.completeLock(at: 1)
        stream(scene, from: 1, count: 16, to: rig.source)
        #expect(rig.model.phase == .review)
        #expect(rig.model.reading?.correctedHex != nil)

        rig.model.removeCard()
        #expect(rig.model.reading?.correctedHex == nil)
        #expect(rig.model.reading?.rawHex != nil)
    }

    @Test func cardChangesIgnoredWhileCapturing() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let card = Self.quad(Self.cardRect)
        let other = Self.quad(CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))

        // In live, a user card is set and removed as usual.
        rig.model.setUserCard(card)
        #expect(rig.model.userCard == card)

        rig.model.shutter()
        rig.model.setUserCard(other)
        rig.model.removeCard()
        #expect(rig.model.userCard == card)
        #expect(!rig.model.cardRemoved)
    }

    // MARK: Card detection and light

    @Test func cardHoldsForOneSecondWithoutAcceptance() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let scene = Self.cardScene()
        let card = Self.quad(Self.cardRect)

        rig.source.send(frame(scene, at: 0, candidates: [card]))
        rig.source.send(frame(scene, at: 0.5, candidates: []))
        #expect(rig.model.detectedCard == card)

        rig.source.send(frame(scene, at: 1.2, candidates: []))
        #expect(rig.model.detectedCard == nil)
    }

    @Test func cardHoldKeptAcrossNilCandidateFrames() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let scene = Self.cardScene()
        let card = Self.quad(Self.cardRect)

        rig.source.send(frame(scene, at: 0, candidates: [card]))
        // Detection did not run on these frames; they fall well inside the hold.
        stream(scene, from: 0.2, count: 20, to: rig.source)
        #expect(rig.model.detectedCard == card)
    }

    @Test func cardHoldExpiresOnNilCandidateFrames() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let scene = Self.cardScene()
        let card = Self.quad(Self.cardRect)

        rig.source.send(frame(scene, at: 0, candidates: [card]))
        // Only nil-candidate frames follow, past the one-second hold.
        stream(scene, from: 0.1, count: 40, to: rig.source)
        #expect(rig.model.detectedCard == nil)
    }

    @Test func removeCardInLiveHidesActiveCard() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let card = Self.quad(Self.cardRect)
        rig.source.send(frame(Self.cardScene(), at: 0, candidates: [card]))
        #expect(rig.model.activeCard == card)
        #expect(rig.model.suggestedCard == nil)

        rig.model.removeCard()
        #expect(rig.model.activeCard == nil)
        #expect(rig.model.suggestedCard == card)
    }

    @Test func draggingSuggestionRestoresCard() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let card = Self.quad(Self.cardRect)
        rig.source.send(frame(Self.cardScene(), at: 0, candidates: [card]))
        rig.model.removeCard()

        let moved = card.translated(by: CGVector(dx: 0.02, dy: 0))
        rig.model.setUserCard(moved)
        #expect(rig.model.activeCard == moved)
        #expect(rig.model.suggestedCard == nil)
    }

    @Test func validCandidateCoveringTheCircleIsNotDetected() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let card = Self.quad(Self.cardRect)
        // At the default radius the card is clear of the circle and is accepted.
        rig.source.send(frame(Self.cardScene(), at: 0, candidates: [card]))
        #expect(rig.model.detectedCard == card)
        rig.model.circleRadius = 0.30
        rig.source.send(frame(Self.cardScene(), at: 2, candidates: [card]))
        // The large circle reaches the valid card: it is skipped, and the hold has expired.
        #expect(rig.model.detectedCard == nil)
    }

    @Test func cardDetectionRunsOnlyInLive() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        #expect(rig.source.detectsCards)
        rig.model.onAppear()
        #expect(rig.source.detectsCards)

        rig.model.shutter()
        #expect(!rig.source.detectsCards)
        rig.source.completeLock(at: 10)
        stream(uniformGrid("D9622B"), from: 10, count: 16, to: rig.source)
        #expect(rig.model.phase == .review)
        #expect(!rig.source.detectsCards)

        rig.model.retake()
        #expect(rig.source.detectsCards)
    }

    @Test func lightLevelFollowsFrames() {
        let rig = makeRig()
        defer { rig.removeDefaults() }
        rig.model.onAppear()
        let grid = uniformGrid("D9622B")

        stream(grid, from: 0, count: 31, to: rig.source, ev100: 3)
        #expect(rig.model.lightLevel == .tooDark)

        stream(grid, from: 31.0 / 30.0, count: 62, to: rig.source, ev100: 9)
        #expect(rig.model.lightLevel == .ok)
    }
}
