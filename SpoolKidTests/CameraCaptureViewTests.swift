//
//  CameraCaptureViewTests.swift
//  SpoolKidTests
//
//  Purpose: `CameraCaptureView.encode` stores photos at the pixel size it
//  promises, not at the screen's scale multiple of it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import UIKit
@testable import SpoolKid

struct CameraCaptureViewTests {
    /// A solid image of exactly `width` x `height` pixels (scale 1), so the
    /// test does not depend on the device's screen scale.
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func aLargeCaptureIsStoredAtTheMaxDimensionInPixels() throws {
        let max = CameraCaptureView.maxDimension
        let data = try #require(CameraCaptureView.encode(image(width: 4000, height: 3000)))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(CGFloat(decoded.width) == max)
        #expect(CGFloat(decoded.height) == max * 3000 / 4000)
    }

    @Test func aSmallImageKeepsItsPixelSize() throws {
        let data = try #require(CameraCaptureView.encode(image(width: 1200, height: 800)))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(decoded.width == 1200)
        #expect(decoded.height == 800)
    }
}
