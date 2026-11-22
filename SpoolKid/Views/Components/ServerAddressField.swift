//
//  ServerAddressField.swift
//  SpoolKid
//
//  Purpose: The server address field shared by SpoolmanConnectionForm and
//  FilaManConnectionForm: the typed address plus one line saying what to fix,
//  or the address SpoolKid will connect to when that differs from what was
//  typed. The rule lives in ServerAddress; this view only renders it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ServerAddressField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server URL")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The binding is written only by typing: the field never rewrites
            // what the person typed.
            TextField(placeholder, text: $text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("serverAddressField")
            switch ServerAddress.hint(for: text) {
            case .problem(let message):
                Text(message)
                    .font(.body)
                    .foregroundColor(.statusError)
                    .accessibilityIdentifier("serverAddressProblem")
            case .connectsTo(let address):
                Text("Connects to \(address)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("serverAddressConnectsTo")
            case nil:
                EmptyView()
            }
        }
    }
}
