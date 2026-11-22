//
//  EmptySpoolEditorView.swift
//  SpoolKid
//
//  Purpose: Add or edit one empty spool — photo, manufacturer, name, weight, and the defaults (all spools, its brand's).
//  Presented in its own NavigationStack sheet by `EmptySpoolListView`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import PhotosUI
import UIKit

struct EmptySpoolEditorView: View {
    /// Nil adds a new entry.
    let editing: EmptySpoolRecord?

    @EnvironmentObject private var library: EmptySpoolLibrary
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var manufacturer = ""
    @State private var name = ""
    @State private var weightText = ""
    @State private var photo: Data?
    @State private var isDefault = false
    @State private var isManufacturerDefault = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingSaveFailure = false
    @State private var showingPhotoFailure = false
    /// True while a picked photo is being fetched; Save waits for it, so a
    /// photo-only edit cannot be saved with the old photo and closed.
    @State private var isLoadingPhoto = false
    /// Bumped per pick; only the latest pick's result may land.
    @State private var photoLoadGeneration = 0
    @State private var didLoad = false

    private var canSave: Bool {
        EmptySpoolLibrary.isValid(name: name, weight: SpoolWeightMath.parseWeight(weightText))
    }

    private var trimmedManufacturer: String {
        manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Under the default switches, so "all spools" is not read as overriding a brand's own.
    static let brandDefaultFooter = "A brand's own default wins over the one for all spools."

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    EmptySpoolThumbnail(photo: photo, size: 160)
                        .opacity(isLoadingPhoto ? 0.3 : 1)
                        .overlay {
                            if isLoadingPhoto { ProgressView() }
                        }
                    Spacer()
                }
                if CameraCaptureView.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    // A Photos result still loading would land on top of it.
                    .disabled(isLoadingPhoto)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                if photo != nil {
                    Button(role: .destructive) {
                        photo = nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                    .disabled(isLoadingPhoto)
                }
            } header: {
                Text("Photo")
            }

            Section {
                NavigationLink {
                    ManufacturerPickerView(
                        current: ManufacturerChoice.named(manufacturer, in: store.vendors),
                        allowsNone: true
                    ) { choice in
                        manufacturer = choice.name ?? ""
                    }
                } label: {
                    LabeledContent("Manufacturer", value: manufacturer.isEmpty ? "None" : manufacturer)
                }
                .accessibilityIdentifier("emptySpoolEditor.manufacturer")
                TextField("Name", text: $name)
                    .accessibilityIdentifier("emptySpoolEditor.name")
                HStack {
                    Text("Weight (g)")
                    Spacer()
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .accessibilityIdentifier("emptySpoolEditor.weight")
                }
                // Weigh the bare spool on a paired scale and take the number.
                ScaleWeightRow { grams in
                    weightText = String(grams)
                }
                Toggle("Default for all spools", isOn: $isDefault)
                if !trimmedManufacturer.isEmpty {
                    Toggle("Default for \(trimmedManufacturer) spools", isOn: $isManufacturerDefault)
                        .accessibilityIdentifier("emptySpoolEditor.brandDefault")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SpoolFormView.spoolWeightCaption)
                    Text(Self.brandDefaultFooter)
                }
                .font(.subheadline)
            }
        }
        .keyboardDoneBar()
        .selectsTextOnFocus()
        .navigationTitle(editing == nil ? "New Empty Spool" : "Edit Empty Spool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave || isLoadingPhoto)
                    .accessibilityIdentifier("emptySpoolEditor.save")
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { data in
                showingCamera = false
                // A cancelled camera keeps the photo the entry already had.
                if let data { photo = data }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .alert("Could not save the empty spool.", isPresented: $showingSaveFailure) {
            Button("OK", role: .cancel) {}
        }
        .alert("Could not load the photo.", isPresented: $showingPhotoFailure) {
            Button("OK", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let editing else { return }
        manufacturer = editing.manufacturer
        name = editing.name
        weightText = SpoolWeightMath.formatWeight(editing.weight)
        photo = editing.photo
        isDefault = editing.isDefault
        isManufacturerDefault = editing.isManufacturerDefault
    }

    /// Re-encoded through `CameraCaptureView.encode`, the one image path. A
    /// photo that cannot be fetched, read or encoded leaves the current one
    /// in place and says so; a result from an earlier pick is ignored.
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoLoadGeneration += 1
        let generation = photoLoadGeneration
        isLoadingPhoto = true
        Task {
            defer {
                if generation == photoLoadGeneration {
                    isLoadingPhoto = false
                    photoItem = nil
                }
            }
            let data = try? await item.loadTransferable(type: Data.self)
            guard generation == photoLoadGeneration else { return }
            guard let data,
                  let image = UIImage(data: data),
                  let encoded = CameraCaptureView.encode(image) else {
                showingPhotoFailure = true
                return
            }
            photo = encoded
        }
    }

    private func save() {
        guard let weight = SpoolWeightMath.parseWeight(weightText) else { return }
        // The switch is hidden with no manufacturer; a value left on behind it must not save.
        let brandDefault = !trimmedManufacturer.isEmpty && isManufacturerDefault
        let saved: Bool
        if let editing {
            saved = library.update(
                editing.id, manufacturer: manufacturer, name: name, weight: weight, photo: photo,
                isDefault: isDefault, isManufacturerDefault: brandDefault
            )
        } else {
            saved = library.add(
                manufacturer: manufacturer, name: name, weight: weight, photo: photo,
                isDefault: isDefault, isManufacturerDefault: brandDefault
            )
        }
        if saved {
            dismiss()
        } else {
            showingSaveFailure = true
        }
    }
}
