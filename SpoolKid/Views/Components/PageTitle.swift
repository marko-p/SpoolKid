//
//  PageTitle.swift
//  SpoolKid
//
//  Purpose: The inline title of a read-first record page (the filament and
//  manufacturer pages). Each page applies it to every state but editing: the
//  embedded form names itself ("Edit Filament"), and a title set on the page's
//  outer view would override that.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

extension View {
    func pageTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
