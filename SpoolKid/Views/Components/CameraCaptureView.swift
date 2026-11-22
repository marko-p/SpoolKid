//
//  CameraCaptureView.swift
//  SpoolKid
//
//  Purpose: Take one photo and hand back JPEG data. Deliberately the plain
//  system camera rather than anything built on `UnifiedSmartScannerView` —
//  that one runs live OCR and arbitration, and none of it applies to
//  photographing a scale's display as evidence.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {

    /// Nil when the user cancelled.
    let onCapture: (Data?) -> Void

    /// The Simulator has no camera, and asking for one there raises an
    /// exception rather than failing softly. Every caller is a diagnostic
    /// screen a developer will open on a Mac at some point.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Long enough to read a display at a glance, small enough that a capture
    /// with half a dozen photos still shares over a chat app.
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.75

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    /// Downscales the long edge and re-encodes. A full-resolution capture is
    /// several megabytes and nothing in a diagnostic bundle needs it — the
    /// photo exists so a person can read four digits off a display.
    static func encode(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: jpegQuality) }
        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Scale 1: the default format uses the screen's scale, which would
        // turn a 1600 px target into 4800 px on a 3x phone.
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: jpegQuality)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data?) -> Void

        init(onCapture: @escaping (Data?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            onCapture(image.flatMap { CameraCaptureView.encode($0) })
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
