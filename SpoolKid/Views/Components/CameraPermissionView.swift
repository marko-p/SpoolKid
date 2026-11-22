//
//  CameraPermissionView.swift
//  SpoolKid
//
//  Purpose: The screen shown in place of a camera when access is not granted:
//  an icon, a message, the one action that fits the status (Open iOS Settings
//  when denied or restricted, Request Camera Access otherwise) and Cancel.
//  Shared by Smart Scan and camera color capture.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import SwiftUI

struct CameraPermissionView: View {
    let status: AVAuthorizationStatus
    let message: String
    let onRequest: () -> Void
    let onCancel: () -> Void

    init(
        status: AVAuthorizationStatus,
        message: String,
        onRequest: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.status = status
        self.message = message
        self.onRequest = onRequest
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if status == .denied || status == .restricted {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Request Camera Access", action: onRequest)
                    .buttonStyle(.borderedProminent)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
