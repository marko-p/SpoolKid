//
//  ToolheadManualView.swift
//  SpoolKid
//
//  Purpose: Set by Hand: tells a toolhead what is in it without a Library
//  spool. Stays open on anything but a confirmed write. Materials and
//  subtypes are the printer's own lists, nothing else (a toolhead's "PLA+"
//  opens with no material); a manufacturer picked as new is added to the backend
//  before the printer is told (owner, 2026-11-09).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ToolheadManualView: View {
    let toolhead: ToolheadState
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serverLink) private var serverLink
    @State private var material = ""
    @State private var vendor = ""
    /// Set only by picking a new name in the picker, never by the prefill: a
    /// toolhead's own "Snapmaker" is not added to the backend unasked.
    @State private var createsVendor = false
    @State private var subtype = ""
    @State private var colors = FilamentColors(hexes: ["FFFFFF"], pattern: .coextruded)
    @State private var opacity = 100.0
    @State private var working = false
    @State private var problem: String?
    /// `onAppear` fires again when the manufacturer picker pops; prefilling
    /// then would throw away what was just picked.
    @State private var didPrefill = false

    private var assignment: ToolheadAssignment? {
        ToolheadAssignment.byHand(
            material: material, vendor: vendor, subtype: subtype, colorHexes: colors.hexes,
            opacityPercent: opacity, replacing: toolhead
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Material", selection: $material) {
                        if material.isEmpty { Text("Choose").tag("") }
                        ForEach(printer.profile.materials, id: \.self) { Text($0).tag($0) }
                    }
                    NavigationLink {
                        ManufacturerPickerView(current: vendorChoice, allowsNone: true) { choice in
                            vendor = choice.name ?? ""
                            if case .new = choice { createsVendor = true } else { createsVendor = false }
                        }
                    } label: {
                        LabeledContent("Manufacturer", value: vendor.isEmpty ? "Generic" : vendor)
                    }
                    Picker("Subtype", selection: $subtype) {
                        Text("None").tag("")
                        ForEach(subtypeChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: subtypeChoices) { _, choices in
                        if !choices.contains(subtype) { subtype = "" }
                    }
                } footer: {
                    Text("The printer picks its load and unload temperatures from the material. Print temperatures come from the sliced file.")
                }
                Section {
                    FilamentColorEditor(colors: $colors, showsPattern: false)
                }
                Section {
                    LabeledContent("Opacity", value: "\(Int(opacity))%")
                    Slider(value: $opacity, in: 1...100, step: 1)
                        .accessibilityLabel("Opacity")
                }
                Section {
                    Button("Set \(toolhead.name)") { save() }
                        .disabled(assignment == nil || working || printer.activity.blocksWrites || addingVendorIsLocked)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if addingVendorIsLocked {
                            Text("Adding \(vendor) needs \(serverLink.backendName). Pick one of your manufacturers, or try again when it's back.")
                        }
                        if toolhead.spoolID != nil {
                            Text("This drops Spoolman spool #\(toolhead.spoolID ?? 0) from \(toolhead.name), so its usage is no longer tracked.")
                        }
                    }
                }
                if let problem {
                    Text(problem).font(.body).foregroundStyle(.red)
                }
            }
            .navigationTitle("Set by Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: prefill)
        }
    }

    private var subtypeChoices: [String] {
        printer.profile.subtypes(for: material)
    }

    private var vendorChoice: ManufacturerChoice {
        ManufacturerChoice.named(vendor, in: store.vendors)
    }

    /// A new manufacturer is a backend write, so it waits for the server.
    private var addingVendorIsLocked: Bool {
        createsVendor && serverLink.isDown
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        material = printer.profile.material(matching: toolhead.material)
        // "NONE" is the firmware's empty toolhead, not a manufacturer.
        vendor = toolhead.vendor.flatMap { $0.uppercased() == "NONE" ? nil : $0 } ?? ""
        subtype = printer.profile.subtype(matching: toolhead.subtype, material: material)
        if !toolhead.colorHexes.isEmpty {
            colors = FilamentColors(hexes: toolhead.colorHexes, pattern: .coextruded)
        }
        opacity = ToolheadAssignment.opacityPercent(alpha: toolhead.alpha)
    }

    private func save() {
        guard let assignment else { return }
        working = true
        problem = nil
        Task {
            if createsVendor, case .new(let name) = vendorChoice {
                var added: Vendor?
                let outcome = await serverLink.outcome {
                    added = await store.addVendor(name: name)
                    return added != nil
                }
                guard let added else {
                    working = false
                    problem = SaveNote.failure(outcome, otherwise: "Couldn't add \(name) to \(serverLink.backendName.isEmpty ? "your library" : serverLink.backendName).")
                    return
                }
                vendor = added.name
                createsVendor = false
            }
            let outcome = await printer.assign(
                assignment, toolhead: toolhead.index, force: PrinterCommands.needsForce(toolhead)
            )
            working = false
            if outcome == .confirmed { dismiss() } else { problem = outcome.message }
        }
    }
}
