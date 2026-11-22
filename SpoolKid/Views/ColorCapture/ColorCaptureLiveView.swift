//
//  ColorCaptureLiveView.swift
//  SpoolKid
//
//  Purpose: The live half of the color capture screen: the camera preview layer
//  and the bottom controls (shutter, or "Hold still" while a capture runs).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Preview layer

/// The camera preview, aspect-filled so it matches `AspectFillMapping`.
struct ColorCapturePreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Controls

/// The bottom controls of the live and capturing phases.
struct ColorCaptureLiveControls: View {
    @ObservedObject var model: ColorCaptureModel

    var body: some View {
        VStack(spacing: 16) {
            if model.phase == .capturing {
                Text("Hold still")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(.black.opacity(0.6), in: Capsule())
                    .frame(height: 72)
            } else {
                ColorCaptureSizeSlider(model: model)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.horizontal, 24)
                shutterButton
            }
        }
        .padding(.bottom, 16)
    }

    private var shutterButton: some View {
        Button {
            model.shutter()
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4)
                Circle().fill(Color.white).padding(8)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture color")
        .accessibilityIdentifier("colorCapture.shutter")
    }
}
