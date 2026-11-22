//
//  PhotoSourceSheet.swift
//  SpoolKid
//
//  Purpose: One place to pick the photo Color Matching reads: the system
//  photo grid, with Take Photo (only with a camera) in the sheet's bar. The
//  system picker needs no Photos permission, so the camera is a button rather
//  than a grid tile (owner, 2026-11-18).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import PhotosUI
import SwiftUI

struct PhotoSourceSheet: View {
    let onCamera: () -> Void
    let onPhoto: (PhotosPickerItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?

    var body: some View {
        // Take Photo sits in the navigation bar: the inline grid is drawn by
        // the system and lays itself over anything stacked or inset above it.
        NavigationStack {
            PhotosPicker(selection: $item, matching: .images) {
                Label("Choose a Photo", systemImage: "photo")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .navigationTitle("Match a Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if CameraCaptureView.isAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onCamera) {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .accessibilityIdentifier("photoSource.camera")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: item) { _, item in
            if let item { onPhoto(item) }
        }
    }
}
