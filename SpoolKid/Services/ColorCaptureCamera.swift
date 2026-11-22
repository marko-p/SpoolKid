//
//  ColorCaptureCamera.swift
//  SpoolKid
//
//  Purpose: Frame source for camera color capture. Runs an AVCaptureSession
//  with fixed, color-faithful settings (sRGB, whole-frame metering), turns each
//  sampled frame into a linear-light pixel grid, an EV100 light reading and
//  optional reference-card candidates (Vision), and can lock exposure and white
//  balance for the capture. Delivers finished frames on the main actor.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import CoreImage
import Foundation
import os
import Vision

nonisolated private let logger = Logger(subsystem: "com.spoolkid", category: "ColorCaptureCamera")

// MARK: - ColorCaptureFrame

/// One processed camera frame. `cardCandidates` is nil when card detection did
/// not run on this frame; `image` is set only while full frames are wanted
/// (the review photo).
nonisolated struct ColorCaptureFrame: Sendable {
    let grid: PixelGrid
    let ev100: Double
    let cardCandidates: [Quad]?
    let timestamp: TimeInterval
    let image: CGImage?
}

// MARK: - ColorCaptureFrameSource

@MainActor
protocol ColorCaptureFrameSource: AnyObject {
    var onFrame: ((ColorCaptureFrame) -> Void)? { get set }
    var previewSession: AVCaptureSession? { get }
    /// While true, every frame is processed and carries its `image`.
    var wantsFullFrames: Bool { get set }
    /// Whether to run rectangle detection on processed frames. The model sets it only in live preview.
    var detectsCards: Bool { get set }
    func start()
    func stop()
    /// Locks exposure and white balance at their current values. `completion`
    /// receives the timestamp of the first frame delivered after the lock took effect.
    func lockExposureAndWhiteBalance(completion: @escaping @MainActor (TimeInterval) -> Void)
    func unlockExposureAndWhiteBalance()
}

// MARK: - CaptureState

/// State shared between the main actor, the session queue and the video-data
/// queue. Every access goes through one unfair lock.
nonisolated private final class CaptureState: Sendable {

    typealias LockCompletion = @MainActor @Sendable (TimeInterval) -> Void

    private enum LockPhase {
        case idle
        /// Lock requested; the white-balance lock has not reported back yet.
        case applying(LockCompletion)
        /// The lock took effect; the next frame carries the completion.
        case armed(LockCompletion)
    }

    private struct Values {
        var frameCounter = 0
        var wantsFullFrames = false
        var detectsCards = true
        var lockPhase = LockPhase.idle
    }

    struct FrameDecision {
        let process: Bool
        let full: Bool
        let detectsCards: Bool
        let completion: LockCompletion?
    }

    private let values = OSAllocatedUnfairLock(initialState: Values())

    func setWantsFullFrames(_ wants: Bool) {
        values.withLock { $0.wantsFullFrames = wants }
    }

    func setDetectsCards(_ detects: Bool) {
        values.withLock { $0.detectsCards = detects }
    }

    func requestLock(_ completion: @escaping LockCompletion) {
        values.withLock { $0.lockPhase = .applying(completion) }
    }

    /// The lock took effect (or could not be applied): the next frame answers the request.
    func armLock() {
        values.withLock { values in
            if case .applying(let completion) = values.lockPhase {
                values.lockPhase = .armed(completion)
            }
        }
    }

    func cancelLock() {
        values.withLock { $0.lockPhase = .idle }
    }

    /// Counts a frame and decides whether to process it. A frame that answers a
    /// lock request is always processed.
    func nextFrame(every interval: Int) -> FrameDecision {
        values.withLock { values in
            values.frameCounter &+= 1
            var completion: LockCompletion?
            if case .armed(let pending) = values.lockPhase {
                completion = pending
                values.lockPhase = .idle
            }
            let full = values.wantsFullFrames
            let process = full || completion != nil || values.frameCounter % interval == 0
            return FrameDecision(process: process, full: full, detectsCards: values.detectsCards, completion: completion)
        }
    }
}

// MARK: - ColorCaptureCamera

final class ColorCaptureCamera: NSObject, ColorCaptureFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Live preview frames are processed every this many frames.
    nonisolated private static let liveFrameInterval = 6
    /// Box size of the downscale: 4 × 4 source pixels per grid pixel.
    nonisolated private static let boxSize = 4

    /// Whether the device has a back camera. Read once.
    static let isAvailable: Bool =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil

    var onFrame: ((ColorCaptureFrame) -> Void)?

    var previewSession: AVCaptureSession? { session }

    var wantsFullFrames = false {
        didSet { state.setWantsFullFrames(wantsFullFrames) }
    }

    var detectsCards = true {
        didSet { state.setDetectsCards(detectsCards) }
    }

    nonisolated private let session = AVCaptureSession()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    nonisolated private let state = CaptureState()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.spoolkid.colorcapture.session")
    nonisolated private let videoQueue = DispatchQueue(label: "com.spoolkid.colorcapture.video")
    nonisolated private static let ciContext = CIContext()

    // Confined to `sessionQueue`.
    nonisolated(unsafe) private var isSessionConfigured = false
    nonisolated(unsafe) private var isSessionRunning = false

    // MARK: Control

    func start() {
        sessionQueue.async { [self] in
            configureSessionOnSessionQueue()
            guard isSessionConfigured, !isSessionRunning else { return }
            session.startRunning()
            isSessionRunning = true
        }
    }

    func stop() {
        state.cancelLock()
        sessionQueue.async { [self] in
            restoreAutoModesOnSessionQueue()
            guard isSessionRunning else { return }
            session.stopRunning()
            isSessionRunning = false
        }
    }

    func lockExposureAndWhiteBalance(completion: @escaping @MainActor (TimeInterval) -> Void) {
        state.requestLock(completion)
        sessionQueue.async { [self] in
            guard let device else {
                state.armLock()
                return
            }
            do {
                try device.lockForConfiguration()
            } catch {
                logger.error("Cannot lock the camera for configuration: \(error.localizedDescription)")
                state.armLock()
                return
            }
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                // The "current" sentinel locks at the live gains without reading them back.
                device.setWhiteBalanceModeLocked(with: AVCaptureDevice.currentWhiteBalanceGains) { [state] _ in
                    state.armLock()
                }
            } else {
                state.armLock()
            }
            device.unlockForConfiguration()
        }
    }

    func unlockExposureAndWhiteBalance() {
        state.cancelLock()
        sessionQueue.async { [self] in
            restoreAutoModesOnSessionQueue()
        }
    }

    // MARK: Session configuration (sessionQueue)

    nonisolated private func configureSessionOnSessionQueue() {
        guard !isSessionConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            logger.error("Unable to access the camera input.")
            return
        }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.addInput(input)

        do {
            try device.lockForConfiguration()
            if device.activeFormat.supportedColorSpaces.contains(.sRGB) {
                device.activeColorSpace = .sRGB
            }
            // Video HDR tone-maps the frame; the colors must stay as the sensor read them.
            device.automaticallyAdjustsVideoHDREnabled = false
            if device.activeFormat.isVideoHDRSupported {
                device.isVideoHDREnabled = false
            }
            // Whole-frame metering: exposurePointOfInterest is deliberately never set.
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("Cannot configure the camera: \(error.localizedDescription)")
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            logger.error("Unable to add the video output.")
            return
        }
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        isSessionConfigured = true
    }

    nonisolated private func restoreAutoModesOnSessionQueue() {
        guard let device else { return }
        let exposureLocked = device.exposureMode == .locked
        let whiteBalanceLocked = device.whiteBalanceMode == .locked
        guard exposureLocked || whiteBalanceLocked else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            logger.error("Cannot unlock exposure and white balance: \(error.localizedDescription)")
            return
        }
        if exposureLocked, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if whiteBalanceLocked, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()
    }

    // MARK: Frames (videoQueue)

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let decision = state.nextFrame(every: Self.liveFrameInterval)
        guard decision.process else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        var frame: ColorCaptureFrame?
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let grid = Self.grid(from: pixelBuffer) {
            frame = ColorCaptureFrame(
                grid: grid,
                ev100: readEV100(),
                cardCandidates: decision.detectsCards ? Self.cardCandidates(in: pixelBuffer) : nil,
                timestamp: timestamp,
                image: decision.full ? Self.image(from: pixelBuffer) : nil)
        }
        let completion = decision.completion
        let ready = frame
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                completion?(timestamp)
                if let ready { self?.onFrame?(ready) }
            }
        }
    }

    nonisolated private func readEV100() -> Double {
        guard let device else { return .nan }
        return LightMeter.ev100(
            aperture: Double(device.lensAperture),
            exposureDuration: CMTimeGetSeconds(device.exposureDuration),
            iso: Double(device.iso))
    }

    // MARK: Pixel work (pure)

    /// Source bytes at or above this value count as clipped (blown highlight).
    nonisolated private static let clippedByte: UInt8 = 251
    /// sRGB byte → linear value, for averaging in linear light.
    nonisolated private static let linearTable: [Double] = (0..<256).map { ColorMatching.linearized(Double($0) / 255) }

    /// 4 × 4 box average of a BGRA buffer, upright. A portrait buffer (720 × 1280)
    /// gives 180 × 320; a landscape buffer is rotated a quarter turn clockwise while
    /// downscaling so the grid is still portrait-upright. Each box averages the
    /// linearized bytes, not the sRGB ones. A channel with any byte at or above
    /// `clippedByte` in the box is set to 1.0, so the sampler and the card analysis
    /// see the box as clipped.
    nonisolated static func grid(from pixelBuffer: CVPixelBuffer) -> PixelGrid? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let landscape = sourceWidth > sourceHeight
        let box = boxSize
        let outWidth = (landscape ? sourceHeight : sourceWidth) / box
        let outHeight = (landscape ? sourceWidth : sourceHeight) / box
        guard outWidth > 0, outHeight > 0 else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let table = linearTable
        let scale = 1.0 / Double(box * box)
        var pixels: [LinearRGB] = []
        pixels.reserveCapacity(outWidth * outHeight)

        for oy in 0..<outHeight {
            for ox in 0..<outWidth {
                var sumR = 0.0, sumG = 0.0, sumB = 0.0
                var maxR: UInt8 = 0, maxG: UInt8 = 0, maxB: UInt8 = 0
                for dy in 0..<box {
                    for dx in 0..<box {
                        let upX = ox * box + dx
                        let upY = oy * box + dy
                        // Upright (X, Y) reads source (Y, height - 1 - X) when rotating.
                        let sx = landscape ? upY : upX
                        let sy = landscape ? sourceHeight - 1 - upX : upY
                        let p = bytes + sy * stride + sx * 4
                        sumB += table[Int(p[0])]
                        sumG += table[Int(p[1])]
                        sumR += table[Int(p[2])]
                        maxB = max(maxB, p[0])
                        maxG = max(maxG, p[1])
                        maxR = max(maxR, p[2])
                    }
                }
                pixels.append(LinearRGB(
                    r: maxR >= clippedByte ? 1.0 : sumR * scale,
                    g: maxG >= clippedByte ? 1.0 : sumG * scale,
                    b: maxB >= clippedByte ? 1.0 : sumB * scale))
            }
        }
        return PixelGrid(width: outWidth, height: outHeight, pixels: pixels)
    }

    /// Rectangle candidates (top-left normalized) in the upright frame, or nil
    /// when the request failed.
    nonisolated private static func cardCandidates(in pixelBuffer: CVPixelBuffer) -> [Quad]? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.1
        request.maximumObservations = 4
        request.quadratureTolerance = 20

        let landscape = CVPixelBufferGetWidth(pixelBuffer) > CVPixelBufferGetHeight(pixelBuffer)
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: landscape ? .right : .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("Rectangle detection failed: \(error.localizedDescription)")
            return nil
        }
        return (request.results ?? []).map { observation in
            func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
            return Quad(topLeft: flip(observation.topLeft), topRight: flip(observation.topRight),
                        bottomRight: flip(observation.bottomRight), bottomLeft: flip(observation.bottomLeft))
        }
    }

    /// The upright frame as a CGImage (the review photo).
    nonisolated private static func image(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let landscape = CVPixelBufferGetWidth(pixelBuffer) > CVPixelBufferGetHeight(pixelBuffer)
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if landscape { image = image.oriented(.right) }
        return ciContext.createCGImage(image, from: image.extent)
    }
}
