//
//  WriteTagButtonStyle.swift
//  SpoolKid
//
//  Purpose: Conditional button styling for the "Write to NFC Tag" button.
//  Uses liquid glass on iOS 26+, borderedProminent on iOS 18-25.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

extension View {
    /// Applies the appropriate button style for the "Write to NFC Tag" button.
    /// On iOS 26+, uses the glass effect for liquid glass appearance.
    /// On earlier versions, uses a borderedProminent style with tint.
    @ViewBuilder
    func writeTagButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.borderedProminent)
                .glassEffect(.regular.interactive())
        } else {
            self
                .buttonStyle(.borderedProminent)
        }
    }
}
