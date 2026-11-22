//
//  MigrationFixView.swift
//  SpoolKid
//
//  Purpose: Supplies the fields the active backend requires on a filament the
//  migration cannot upload — a control per missing requirement, written back to
//  the local row so the plan can be rebuilt against it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// The fix sheet for one blocked filament.
///
/// It renders ONLY the requirements the backend actually named, so it can never
/// overwrite a value the row already had. The manufacturer row can also create
/// one, which is the whole reason the sheet exists: the case that prompted it
/// was a Library with no manufacturers at all, and while a server backend is
/// active the Library tab shows the SERVER's data — the local row is not
/// reachable from any other screen in the app.
struct MigrationFixView: View {
    let label: String
    let requirements: [FilamentCreateRequirement]
    /// Every manufacturer the user could mean — the ones on this iPhone and the
    /// ones already on the server, as one deduped list of names
    /// (`MigrationService.manufacturerOptions`). One list rather than two,
    /// because a manufacturer is one manufacturer wherever it happens to exist,
    /// and a name is what the planner matches on.
    let manufacturers: [String]
    let apply: (MigrationFilamentFix) async -> String?

    let localId: Int
    /// Named in the manufacturer footer, so the sheet can say where the offered
    /// names come from without knowing which backend it is.
    let backendName: String

    @State private var name: String = ""
    @State private var manufacturerName: String?
    @State private var newManufacturerName: String = ""
    @State private var material: String = ""
    @State private var diameter: String = String(AppConfig.Defaults.diameter)
    @State private var density: String = String(AppConfig.Defaults.density)
    @State private var errorMessage: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var needs: Set<FilamentCreateRequirement> { Set(requirements) }

    /// Whether every named requirement now has a value. The Save button is the
    /// only gate: leaving it enabled would just reproduce the refusal that
    /// opened this sheet.
    static func isComplete(
        requirements: [FilamentCreateRequirement],
        name: String,
        manufacturerName: String?,
        newManufacturerName: String,
        material: String,
        diameter: Double?,
        density: Double?
    ) -> Bool {
        func filled(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for requirement in requirements {
            switch requirement {
            case .name where !filled(name): return false
            case .material where !filled(material): return false
            case .diameter where diameter == nil: return false
            case .density where FilamentTagData.statedMeasurement(density) == nil: return false
            case .manufacturer where manufacturerName == nil && !filled(newManufacturerName): return false
            default: continue
            }
        }
        return true
    }

    /// The name the fix will carry: the picked one, or the typed one when the
    /// picker is on "New manufacturer…".
    static func resolvedManufacturer(picked: String?, typed: String) -> String? {
        if let picked { return picked }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canSave: Bool {
        Self.isComplete(
            requirements: requirements,
            name: name,
            manufacturerName: manufacturerName,
            newManufacturerName: newManufacturerName,
            material: material,
            diameter: Double(diameter.replacingOccurrences(of: ",", with: ".")),
            density: Double(density.replacingOccurrences(of: ",", with: "."))
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(label)
                        .font(.headline)
                } footer: {
                    Text("This is missing what the server needs before it can be uploaded. "
                         + "The correction is saved to the item on this iPhone.")
                }

                if needs.contains(.name) {
                    Section("Name") {
                        TextField("Name", text: $name)
                    }
                }

                if needs.contains(.material) {
                    Section("Material") {
                        HStack {
                            TextField("Type", text: $material)
                            Menu {
                                ForEach(AppConfig.materials, id: \.self) { option in
                                    Button(option) { material = option }
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }

                if needs.contains(.density) {
                    Section("Density (g/cm³)") {
                        TextField("\(AppConfig.Defaults.density)", text: $density)
                            .keyboardType(.decimalPad)
                    }
                }

                if needs.contains(.diameter) {
                    Section("Diameter (mm)") {
                        TextField("\(AppConfig.Defaults.diameter)", text: $diameter)
                            .keyboardType(.decimalPad)
                    }
                }

                if needs.contains(.manufacturer) {
                    Section {
                        if !manufacturers.isEmpty {
                            Picker("Manufacturer", selection: $manufacturerName) {
                                ForEach(manufacturers, id: \.self) { option in
                                    Text(option).tag(Optional(option))
                                }
                                Text("New manufacturer…").tag(Optional<String>.none)
                            }
                            .pickerStyle(.navigationLink)
                        }
                        if manufacturerName == nil {
                            TextField("New manufacturer name", text: $newManufacturerName)
                        }
                    } header: {
                        Text("Manufacturer")
                    } footer: {
                        if !manufacturers.isEmpty {
                            Text("Includes the manufacturers already on "
                                 + "\(backendName). Choosing one links to it — "
                                 + "it won't be created twice.")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .keyboardDoneBar()
            .navigationTitle("Fix Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let fix = MigrationFilamentFix(
            localId: localId,
            name: needs.contains(.name) ? name.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            manufacturerName: needs.contains(.manufacturer)
                ? Self.resolvedManufacturer(picked: manufacturerName, typed: newManufacturerName)
                : nil,
            material: needs.contains(.material)
                ? material.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            diameter: needs.contains(.diameter)
                ? Double(diameter.replacingOccurrences(of: ",", with: ".")) : nil,
            density: needs.contains(.density)
                ? Double(density.replacingOccurrences(of: ",", with: ".")) : nil
        )
        Task {
            let failure = await apply(fix)
            isSaving = false
            if let failure {
                errorMessage = failure
            } else {
                dismiss()
            }
        }
    }
}
