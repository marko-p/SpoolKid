//
//  PrinterSettingsView.swift
//  SpoolKid
//
//  Purpose: The printer's name and address. Also what the tab shows before a
//  printer is set up.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct PrinterSettingsView: View {
    @EnvironmentObject private var printer: PrinterService
    @AppStorage(AppConfig.printerAddressKey) private var address = ""
    /// Until one is typed, the printer is called what it is (owner, 2026-11-09).
    @AppStorage(AppConfig.printerNameKey) private var name = PrinterProfile.snapmakerU1.name
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $name)
                ServerAddressField(placeholder: "http://192.168.1.50", text: $draft)
                Button("Connect") {
                    address = draft
                    Task { await printer.connect() }
                }
                .disabled(!ServerAddress.isUsable(draft))
            } footer: {
                Text("SpoolKid shows what is in each toolhead and can put a Library spool into one. It works over your local network, with no pairing.")
            }

            if let row = printer.tagPlugin.settingsRow(connection: printer.connection) {
                Section { Text(row) }
            }

            if printer.isSignedIn {
                Button("Sign Out", role: .destructive) { Task { await printer.signOut() } }
            }

            if case .offline(let reason) = printer.connection {
                Text(reason).font(.body).foregroundStyle(.red)
            }

            if PrinterService.isConfigured(address: address) {
                Section {
                    Button("Remove Printer", role: .destructive) {
                        printer.remove()
                        draft = ""
                    }
                } footer: {
                    Text("Removing the printer hides the Printer tab until you connect one again.")
                }
            }
        }
        .navigationTitle("Printer")
        .onAppear { draft = address }
    }
}
