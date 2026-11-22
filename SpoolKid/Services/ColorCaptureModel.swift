//
//  ColorCaptureModel.swift
//  SpoolKid
//
//  Purpose: Capture state for camera color capture. Runs the live preview,
//  detects a reference card, judges the light level, and on shutter locks
//  exposure and white balance, averages half a second of frames into a frozen
//  grid, and reads the sample circle from it. Holds the review state until the
//  user retakes or leaves the screen.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import Combine
import CoreGraphics
import Foundation

// MARK: - ColorCaptureModel

@MainActor
final class ColorCaptureModel: ObservableObject {

    enum Phase: Equatable {
        case live
        case capturing
        case review
    }

    static let radiusRange: ClosedRange<Double> = 0.04...0.30
    private static let defaultCircleRadius = 0.12
    /// Frames are averaged over at least this many seconds after the lock takes effect.
    private static let captureSpan: TimeInterval = 0.5
    /// A shutter that has not produced a finished capture by then is abandoned or finished early.
    private static let captureTimeout: TimeInterval = 2.0
    /// A detected card is kept this long after its last acceptance, in frame time.
    private static let cardHoldDuration: TimeInterval = 1.0

    @Published private(set) var phase: Phase = .live {
        didSet { source.detectsCards = phase == .live }
    }
    /// Sample circle radius as a fraction of the view width. Persisted on set.
    @Published var circleRadius: Double {
        didSet {
            let clamped = Self.clampedRadius(circleRadius)
            if clamped != circleRadius {
                circleRadius = clamped
            }
            defaults.set(circleRadius, forKey: AppConfig.colorCaptureCircleRadiusKey)
            refreshReading()
        }
    }
    @Published private(set) var lightLevel: LightLevel = .ok
    /// The card found on the latest live frames; kept briefly when a frame finds none.
    @Published private(set) var detectedCard: Quad?
    @Published private(set) var userCard: Quad?
    @Published private(set) var cardRemoved = false
    @Published var showsGuide: Bool
    @Published private(set) var frozenImage: CGImage?
    @Published private(set) var reading: ColorCaptureReading?
    /// Normalized sample circle center; (0.5, 0.5) from every shutter.
    @Published private(set) var circleCenter = CGPoint(x: 0.5, y: 0.5)
    /// Size of the frames, set from the first frame.
    @Published private(set) var imageSize: CGSize?

    /// Set by the view from its size and the image size. Maps the circle radius
    /// from view points to image pixels.
    var mapping: AspectFillMapping? {
        didSet {
            if oldValue != mapping { refreshReading() }
        }
    }

    /// The camera's session, for the live preview layer.
    var previewSession: AVCaptureSession? { source.previewSession }

    /// The card in effect: the user's card, else the detected one, unless removed.
    var activeCard: Quad? {
        cardRemoved ? nil : (userCard ?? detectedCard)
    }

    /// While the card is removed, the detected card as a dimmed suggestion. Moving it
    /// with `setUserCard` brings the card back.
    var suggestedCard: Quad? {
        cardRemoved ? detectedCard : nil
    }

    private let source: ColorCaptureFrameSource
    private let defaults: UserDefaults
    private let scheduleTimeout: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private var isRunning = false
    private var smoother = LightLevelSmoother()
    /// Advanced at every shutter, abandon and disappearance, so stale callbacks are ignored.
    private var captureGeneration = 0
    private var lockTimestamp: TimeInterval?
    private var collectedGrids: [PixelGrid] = []
    private var collectedImage: CGImage?
    private var collectionStart: TimeInterval?
    private var lastCardAcceptance: TimeInterval?
    private var frozenGrid: PixelGrid?

    init(
        source: ColorCaptureFrameSource,
        defaults: UserDefaults = .standard,
        scheduleTimeout: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                action()
            }
        }
    ) {
        self.source = source
        self.defaults = defaults
        self.scheduleTimeout = scheduleTimeout
        self.showsGuide = !defaults.bool(forKey: AppConfig.colorCaptureGuideSeenKey)
        let stored = defaults.object(forKey: AppConfig.colorCaptureCircleRadiusKey) as? Double
        self.circleRadius = Self.clampedRadius(stored ?? Self.defaultCircleRadius)
        source.detectsCards = true
        source.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !isRunning else { return }
        isRunning = true
        source.start()
    }

    /// Stops the camera, which also unlocks exposure. A capture in progress is dropped;
    /// a review is kept, so the user can still retake it after coming back.
    func onDisappear() {
        guard isRunning else { return }
        isRunning = false
        captureGeneration += 1
        if phase == .capturing {
            resetCollection()
            phase = .live
        }
        source.wantsFullFrames = false
        source.stop()
    }

    func dismissGuide() {
        defaults.set(true, forKey: AppConfig.colorCaptureGuideSeenKey)
        showsGuide = false
    }

    // MARK: - Actions

    /// Starts a capture from live preview. Ignored outside `.live`, and while the camera is stopped.
    func shutter() {
        guard isRunning, phase == .live else { return }
        captureGeneration += 1
        let generation = captureGeneration
        circleCenter = CGPoint(x: 0.5, y: 0.5)
        phase = .capturing
        source.wantsFullFrames = true
        source.lockExposureAndWhiteBalance { [weak self] timestamp in
            self?.lockCompleted(at: timestamp, generation: generation)
        }
        scheduleTimeout(Self.captureTimeout) { [weak self] in
            self?.captureTimedOut(generation: generation)
        }
    }

    /// Discards the review and returns to live preview, unlocking exposure and white balance.
    /// Also clears the user's card and card removal.
    func retake() {
        guard phase == .review else { return }
        source.unlockExposureAndWhiteBalance()
        userCard = nil
        cardRemoved = false
        frozenGrid = nil
        frozenImage = nil
        reading = nil
        phase = .live
    }

    /// Moves the sample circle in review, clamped to the image.
    func moveCircle(to point: CGPoint) {
        guard phase == .review else { return }
        circleCenter = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        refreshReading()
    }

    /// Sets the user's card. Ignored while capturing, so the card in effect at shutter stays.
    func setUserCard(_ card: Quad) {
        guard phase != .capturing else { return }
        userCard = card
        cardRemoved = false
        refreshReading()
    }

    /// Removes the card from the reading. Ignored while capturing.
    func removeCard() {
        guard phase != .capturing else { return }
        userCard = nil
        cardRemoved = true
        refreshReading()
    }

    // MARK: - Frames

    private func handle(_ frame: ColorCaptureFrame) {
        guard isRunning else { return }
        if imageSize == nil {
            imageSize = CGSize(width: frame.grid.width, height: frame.grid.height)
        }
        switch phase {
        case .review:
            return
        case .live:
            ingestLight(frame)
            detectCard(in: frame)
        case .capturing:
            ingestLight(frame)
            collect(frame)
        }
    }

    private func ingestLight(_ frame: ColorCaptureFrame) {
        lightLevel = smoother.add(ev100: frame.ev100, at: frame.timestamp)
    }

    /// Accepts the first candidate that reads as a card. On every live frame without an
    /// accepted card, keeps the previous card for `cardHoldDuration` after its last
    /// acceptance, then clears it. Frames with nil candidates (detection did not run)
    /// count toward the hold: they do not extend it.
    /// A candidate that covers the live sample circle is skipped: it might be the filament.
    /// `detectedCard` is published only when it changes.
    private func detectCard(in frame: ColorCaptureFrame) {
        let aspect = Double(frame.grid.height) / Double(max(frame.grid.width, 1))
        let radius = sampleRadiusFraction
        let live = CGPoint(x: 0.5, y: 0.5)
        if let candidates = frame.cardCandidates,
           let card = candidates.first(where: {
               !ColorCaptureReading.quad($0, overlapsCircleAt: live, radiusFraction: radius, imageAspect: aspect)
                   && ColorCaptureReading.cardPatches(in: frame.grid, quad: $0) != nil
           }) {
            if detectedCard != card { detectedCard = card }
            lastCardAcceptance = frame.timestamp
            return
        }
        if let accepted = lastCardAcceptance, frame.timestamp - accepted < Self.cardHoldDuration {
            return
        }
        if detectedCard != nil { detectedCard = nil }
        lastCardAcceptance = nil
    }

    /// Collects frames from the lock onward. Frames before the lock took effect carry
    /// the old exposure and are not used.
    private func collect(_ frame: ColorCaptureFrame) {
        guard let lockTimestamp, frame.timestamp >= lockTimestamp else { return }
        if collectionStart == nil {
            collectionStart = frame.timestamp
        }
        collectedGrids.append(frame.grid)
        if let image = frame.image {
            collectedImage = image
        }
        if let start = collectionStart, frame.timestamp - start >= Self.captureSpan {
            finishCapture()
        }
    }

    private func lockCompleted(at timestamp: TimeInterval, generation: Int) {
        guard generation == captureGeneration, phase == .capturing, lockTimestamp == nil else { return }
        lockTimestamp = timestamp
    }

    private func captureTimedOut(generation: Int) {
        guard generation == captureGeneration, phase == .capturing else { return }
        if collectedGrids.isEmpty {
            abandonCapture()
        } else {
            finishCapture()
        }
    }

    // MARK: - Capture end

    private func finishCapture() {
        guard let averaged = PixelGrid.average(collectedGrids) else {
            abandonCapture()
            return
        }
        frozenGrid = averaged
        frozenImage = collectedImage
        resetCollection()
        source.wantsFullFrames = false
        phase = .review
        refreshReading()
    }

    /// Nothing was collected: unlock and return to live preview.
    private func abandonCapture() {
        resetCollection()
        source.wantsFullFrames = false
        source.unlockExposureAndWhiteBalance()
        phase = .live
    }

    private func resetCollection() {
        lockTimestamp = nil
        collectedGrids = []
        collectedImage = nil
        collectionStart = nil
    }

    // MARK: - Reading

    /// Recomputes the reading from the frozen grid. Only in review.
    private func refreshReading() {
        guard phase == .review, let frozenGrid else { return }
        reading = ColorCaptureReading.make(
            grid: frozenGrid,
            circleCenter: circleCenter,
            radiusFraction: sampleRadiusFraction,
            card: activeCard)
    }

    private static func clampedRadius(_ value: Double) -> Double {
        min(max(value, radiusRange.lowerBound), radiusRange.upperBound)
    }

    /// The circle radius as a fraction of the image width. Without a usable mapping,
    /// the stored fraction is used as is.
    private var sampleRadiusFraction: Double {
        guard let mapping, mapping.viewSize.width > 0, mapping.viewSize.height > 0 else {
            return circleRadius
        }
        return mapping.imageWidthFraction(fromViewLength: CGFloat(circleRadius) * mapping.viewSize.width)
    }
}
