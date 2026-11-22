//
//  PrinterSignInView.swift
//  SpoolKid
//
//  Purpose: Signs in to a printer whose Moonraker asks for it: a Moonraker
//  user, or an API key. The password is sent once and never stored.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct PrinterSignInView: View {
    private enum Method: Hashable { case password, apiKey }

    @EnvironmentObject private var printer: PrinterService
    @State private var method = Method.password
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var working = false
    @State private var problem: String?

    private var canSubmit: Bool {
        !working && (method == .password ? !username.isEmpty && !password.isEmpty : !apiKey.isEmpty)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sign In With", selection: $method) {
                    Text("Password").tag(Method.password)
                    Text("API Key").tag(Method.apiKey)
                }
                .pickerStyle(.segmented)
                if method == .password {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } else {
                    SecureField("API Key", text: $apiKey)
                }
                Button("Sign In") { submit() }
                    .disabled(!canSubmit)
            } header: {
                Text("This Printer Asks for a Sign-In")
            } footer: {
                Text("Use a Moonraker user, or an API key from its settings. This is not your Snapmaker account.")
            }
            if let problem {
                Text(problem).font(.body).foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        working = true
        problem = nil
        Task {
            problem = method == .password
                ? await printer.signIn(username: username, password: password)
                : await printer.signIn(apiKey: apiKey)
            password = ""
            working = false
        }
    }
}
