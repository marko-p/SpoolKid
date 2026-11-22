//
//  ColorCaptureCameraTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for the camera's pure pixel work: the box downscale of a BGRA
//  pixel buffer averages in linear light and flags boxes that contain clipped
//  bytes. Uses a synthetic CVPixelBuffer; no camera is involved.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CoreVideo
import Testing
@testable import SpoolKid

struct ColorCaptureCameraTests {

    /// A 4 × 8 BGRA buffer (two stacked 4 × 4 boxes) filled with grey 128, with `edit` applied to the bytes.
    private func buffer(edit: (UnsafeMutablePointer<UInt8>, Int) -> Void) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 8, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<8 {
            for x in 0..<4 {
                let p = base + y * stride + x * 4
                p[0] = 128; p[1] = 128; p[2] = 128; p[3] = 255
            }
        }
        edit(base, stride)
        return pixelBuffer
    }

    @Test func boxesAverageInLinearLightAndFlagClippedBytes() {
        // Second box: one red byte at 255 among 128s.
        let pixelBuffer = buffer { base, stride in
            (base + 4 * stride + 2 * 4)[2] = 255
        }
        let grid = ColorCaptureCamera.grid(from: pixelBuffer)!
        #expect(grid.width == 1 && grid.height == 2)

        let linear128 = ColorMatching.linearized(128.0 / 255)
        #expect(abs(linear128 - 0.2158) < 0.001)
        #expect(abs(grid.pixels[0].r - linear128) < 1e-9)
        #expect(abs(grid.pixels[0].g - linear128) < 1e-9)
        #expect(abs(grid.pixels[0].b - linear128) < 1e-9)

        #expect(grid.pixels[1].maxChannel == 1.0)
        #expect(abs(grid.pixels[1].g - linear128) < 1e-9)
    }

    @Test func linearAveragingDiffersFromGammaAveraging() {
        // Half the box black, half white (254 stays below the clipped level): the linear
        // mean is far darker than the linearized sRGB mean of the bytes.
        let pixelBuffer = buffer { base, stride in
            for y in 0..<4 {
                for x in 0..<4 {
                    let value: UInt8 = (x < 2) ? 0 : 250
                    let p = base + y * stride + x * 4
                    p[0] = value; p[1] = value; p[2] = value
                }
            }
        }
        let grid = ColorCaptureCamera.grid(from: pixelBuffer)!
        let expected = (0 + ColorMatching.linearized(250.0 / 255)) / 2
        #expect(abs(grid.pixels[0].g - expected) < 1e-9)
    }
}
