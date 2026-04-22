//
//  HideKeyboardExtension.swift
//  SpoolKid
//
//  Purpose: Provides a reusable view modifier that adds a "Done" button
//  above the keyboard to dismiss it. This is the standard Apple pattern
//  using ToolbarItemGroup(placement: .keyboard) and avoids gesture
//  conflicts with NavigationLink, Button, and other interactive controls.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

extension View {
    /// Adds a "Done" button above the keyboard to dismiss it.
    func hideKeyboardOnTap() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}
