//
//  WriteOtherSideButton.swift
//  SpoolKid
//
//  Purpose: After a toolhead wrote a filament tag, write the same data to the
//  spool's other side with the iPhone.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct WriteOtherSideButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Write Other Side with iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
        }
        .frame(minHeight: 44)
    }
}
