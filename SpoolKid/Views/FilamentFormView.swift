//
//  FilamentFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Filament in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentFormView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.serverLink) private var serverLink
    /// Set after a create that may have saved: Save waits for "Save Again".
    @State private var holdsResave = false
    @ObservedObject var store: SpoolDataStore
    var filamentToEdit: Filament?
    var initialData: FilamentTagData? = nil
    /// Update Library from Tag: replaces the edited filament's material and
    /// colors once loaded; Save writes them like any edit.
    var correction: FilamentCorrection? = nil
    var onSaveFilament: ((Filament) -> Void)? = nil
    /// The filament page embeds this form in place of its read view, so
    /// finishing there returns to the read page rather than popping it. When
    /// set, Cancel and a successful Save call it instead of `dismiss()`. Delete
    /// still dismisses: a deleted filament has no page to return to.
    var onFinish: (() -> Void)? = nil

    @AppStorage(AppConfig.lastFilamentMaterialKey) private var lastFilamentMaterial: String = ""
    @AppStorage(AppConfig.lastFilamentVendorIdKey) private var lastFilamentVendorId: Int = -1
    @AppStorage(AppConfig.lastFilamentColorHexKey) private var lastFilamentColorHex: String = AppConfig.Defaults.colorHex
    @AppStorage(AppConfig.lastFilamentDensityKey) private var lastFilamentDensity: Double = AppConfig.Defaults.density
    @AppStorage(AppConfig.lastFilamentDiameterKey) private var lastFilamentDiameter: Double = AppConfig.Defaults.diameter
    @AppStorage(AppConfig.lastFilamentExtruderTempKey) private var lastFilamentExtruderTemp: Int = AppConfig.Defaults.extruderTemp
    @AppStorage(AppConfig.lastFilamentBedTempKey) private var lastFilamentBedTemp: Int = AppConfig.Defaults.bedTemp

    @State private var name: String = ""
    @State private var material: String = ""
    @State private var vendorId: Int?
    /// A manufacturer picked from the catalogue or typed, not in the backend
    /// yet: Save creates it first (owner, 2026-10-12). Cancel leaves nothing
    /// behind. Never set together with `vendorId`.
    @State private var pendingVendorName: String?
    /// `.onAppear` fires again when the manufacturer picker pops; the fields
    /// load once, or the pick and every edit would be overwritten.
    @State private var didLoadFields = false
    @State private var colors = FilamentColors(hexes: [AppConfig.Defaults.colorHex])
    @State private var density: String = String(AppConfig.Defaults.density)
    @State private var diameter: String = String(AppConfig.Defaults.diameter)
    @State private var extruderTemp: String = String(AppConfig.Defaults.extruderTemp)
    @State private var bedTemp: String = String(AppConfig.Defaults.bedTemp)
    @State private var price: String = ""
    @State private var weight: String = ""
    @State private var spoolWeight: String = ""
    @State private var articleNumber: String = ""
    @State private var comment: String = ""
    @State private var externalId: String = ""
    @State private var transmissionDistance: String = ""

    /// What `.onAppear` loaded into each CLEARABLE box, so a save can tell a
    /// field the user emptied from one they never touched. Empty (and `nil`)
    /// when creating, which makes every stated field a `.set` and every blank
    /// one an `.ignore` — the create case falls out of the same rule.
    ///
    /// The twelve set-only fields need no snapshot: they cannot be cleared, so
    /// re-stating one is harmless.
    @State private var loadedVendorId: Int?
    @State private var loadedPrice: String = ""
    @State private var loadedWeight: String = ""
    @State private var loadedSpoolWeight: String = ""
    @State private var loadedArticleNumber: String = ""
    @State private var loadedComment: String = ""
    @State private var loadedExtruderTemp: String = ""
    @State private var loadedBedTemp: String = ""
    /// The colors as loaded; `nil` when creating.
    @State private var loadedColors: FilamentColors?
    @State private var loadedExternalId: String = ""
    @State private var loadedTransmissionDistance: String = ""

    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete = true
    @State private var userModifiedTemps: Bool = false
    @State private var userModifiedDensity: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?
    @State private var quotaError: QuotaError?
    @State private var showCustomizeFields = false
    @State private var showTD1SRead = false
    @State private var fieldVisibilityRefreshToken = 0

    var materials: [String] { AppConfig.materials }

    var extruderTempBinding: Binding<String> {
        Binding(
            get: { self.extruderTemp },
            set: {
                self.extruderTemp = $0
                self.userModifiedTemps = true
            }
        )
    }

    var bedTempBinding: Binding<String> {
        Binding(
            get: { self.bedTemp },
            set: {
                self.bedTemp = $0
                self.userModifiedTemps = true
            }
        )
    }

    var densityBinding: Binding<String> {
        Binding(
            get: { self.density },
            set: {
                self.density = $0
                self.userModifiedDensity = true
            }
        )
    }

    /// What the root banner calls this filament. A caveat the user cannot
    /// trace back to a row is barely a caveat — the owner's device pass
    /// reported exactly that (finding 4.2.1).
    ///
    /// Reads the form's own fields rather than `filamentToEdit`, so a rename
    /// saved alongside a refused colour names what the user just typed.
    private var recordLabel: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return filamentToEdit.map { "Filament #\($0.id)" } ?? "New filament"
        }
        return filamentToEdit == nil ? "New filament · \(typed)" : "Filament · \(typed)"
    }

    static func visibleFieldIDs(for capabilities: BackendCapabilities) -> Set<String> {
        FieldVisibilityStore(support: capabilities.fieldSupport).visibleFieldIDs(for: .filament)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct InitialFieldValues {
        let name: String
        let material: String
        let colors: FilamentColors
        let density: String
        let extruderTemp: String
        let bedTemp: String
        let transmissionDistance: String
    }

    static func initialFieldValues(from tagData: FilamentTagData) -> InitialFieldValues {
        InitialFieldValues(
            name: tagData.name ?? "",
            material: tagData.material,
            colors: tagData.colors,
            density: FilamentTagData.statedMeasurement(tagData.density).map { String($0) }
                ?? seededDensity(forMaterial: tagData.material),
            extruderTemp: tagData.statedExtruderTemp.map { String($0) } ?? "",
            bedTemp: tagData.statedBedTemp.map { String($0) } ?? "",
            transmissionDistance: tagData.transmissionDistance
                .flatMap { TransmissionDistance.isValid($0) ? String(TransmissionDistance.rounded($0)) : nil } ?? ""
        )
    }

    /// An empty box is valid (no TD); anything else must read as a TD in range.
    static func isValidTransmissionDistanceText(_ text: String) -> Bool {
        let trimmed = normalized(text)
        return trimmed.isEmpty || TransmissionDistance.decode(trimmed) != nil
    }

    /// Seeds the manufacturer for a create-from-scan form: the defined
    /// manufacturer matching the scanned brand, or — when none does — the
    /// brand as a pending name that Save creates (owner, 2026-10-12; before,
    /// it was created on appear and outlived a cancelled form). A choice the
    /// user already made is never overwritten.
    @State private var isSeedingVendor = false
    private func seedScannedVendor() async {
        // onAppear and the vendors-count onChange can both call this; the
        // flag keeps the two from interleaving.
        guard filamentToEdit == nil, let tagData = initialData, !isSeedingVendor else { return }
        isSeedingVendor = true
        defer { isSeedingVendor = false }
        let brand = tagData.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { return }
        if store.vendors.isEmpty {
            await store.fetchVendors()
        }
        guard vendorId == nil, pendingVendorName == nil else { return }
        if let match = ManufacturerName.vendor(named: brand, in: store.vendors) {
            vendorId = match.id
        } else {
            pendingVendorName = brand
        }
    }

    /// The picker's checkmark: the defined manufacturer, else the pending name.
    private var manufacturerChoice: ManufacturerChoice {
        if let vendorId {
            let name = store.vendors.first(where: { $0.id == vendorId })?.name ?? ""
            return .existing(id: vendorId, name: name)
        }
        // Spelled out: `?? .none` would read as Optional.none.
        if let pendingVendorName { return .new(name: pendingVendorName) }
        return .none
    }

    /// What the Manufacturer row shows.
    private var manufacturerDisplayName: String {
        if let vendorId {
            return store.vendors.first(where: { $0.id == vendorId })?.name
                ?? filamentToEdit?.vendor?.name
                ?? "Choose"
        }
        return pendingVendorName ?? "Choose"
    }

    static func filamentPayload(
        name: String,
        vendorId: Int?,
        material: String,
        colors: FilamentColors,
        density: String,
        diameter: String,
        extruderTemp: String,
        bedTemp: String,
        price: String,
        weight: String,
        spoolWeight: String,
        articleNumber: String,
        comment: String,
        externalId: String,
        transmissionDistance: String = "",
        loadedTransmissionDistance: String = "",
        // What `.onAppear` loaded into each CLEARABLE box. All empty (and
        // `nil`) when creating, which makes the create case fall out of the
        // same rule: nothing was loaded, so a stated box is a `.set` and a
        // blank one an `.ignore`. Replaced a `clearWhenEmpty` flag, which
        // could say "this is an edit" but not "this field is untouched".
        loadedVendorId: Int? = nil,
        loadedPrice: String = "",
        loadedWeight: String = "",
        loadedSpoolWeight: String = "",
        loadedArticleNumber: String = "",
        loadedComment: String = "",
        loadedExtruderTemp: String = "",
        loadedBedTemp: String = "",
        loadedExternalId: String = "",
        loadedColors: FilamentColors? = nil
    ) -> FilamentDraft {
        /// A box still holding what was loaded says NOTHING; an emptied box
        /// CLEARS. Same rule as `SpoolFormView.textPatch`, and note that the
        /// filament form reads an emptied weight as a clear where the spool
        /// form reads it as "don't touch" — this form offers clearing, that
        /// one does not.
        func text(_ value: String, _ loaded: String) -> SpoolmanPatchValue<String> {
            let normalizedValue = Self.normalized(value)
            guard normalizedValue != Self.normalized(loaded) else { return .ignore }
            return normalizedValue.isEmpty ? .setNil : .set(normalizedValue)
        }

        // A box holding something that is not a number answers `.ignore` —
        // the same silent drop a `nil` from `parseDouble` has always been.
        func double(_ value: String, _ loaded: String) -> SpoolmanPatchValue<Double> {
            let normalizedValue = Self.normalized(value).replacingOccurrences(of: ",", with: ".")
            guard normalizedValue != Self.normalized(loaded).replacingOccurrences(of: ",", with: ".")
            else { return .ignore }
            guard !normalizedValue.isEmpty else { return .setNil }
            return Double(normalizedValue).map { .set($0) } ?? .ignore
        }

        func int(_ value: String, _ loaded: String) -> SpoolmanPatchValue<Int> {
            let normalizedValue = Self.normalized(value)
            guard normalizedValue != Self.normalized(loaded) else { return .ignore }
            guard !normalizedValue.isEmpty else { return .setNil }
            return Int(normalizedValue).map { .set($0) } ?? .ignore
        }

        func parseDouble(_ value: String) -> Double? {
            let normalizedValue = Self.normalized(value).replacingOccurrences(of: ",", with: ".")
            guard !normalizedValue.isEmpty else { return nil }
            return Double(normalizedValue)
        }

        let vendor: SpoolmanPatchValue<Int> = if vendorId == loadedVendorId { .ignore
        } else { vendorId.map { .set($0) } ?? .setNil }

        let colorFields = colors.draftFields(loaded: loadedColors)

        // Entry keeps one decimal (`TransmissionDistance.rounded`).
        let td: SpoolmanPatchValue<Double> = switch double(transmissionDistance, loadedTransmissionDistance) {
        case .set(let value): .set(TransmissionDistance.rounded(value))
        case let other: other
        }

        return FilamentDraft(
            name: Self.normalized(name).isEmpty ? nil : Self.normalized(name),
            vendorId: vendor,
            material: Self.normalized(material).isEmpty ? nil : Self.normalized(material),
            price: double(price, loadedPrice),
            density: parseDouble(density),
            diameter: parseDouble(diameter),
            weight: double(weight, loadedWeight),
            spoolWeight: double(spoolWeight, loadedSpoolWeight),
            articleNumber: text(articleNumber, loadedArticleNumber),
            comment: text(comment, loadedComment),
            extruderTemp: int(extruderTemp, loadedExtruderTemp),
            bedTemp: int(bedTemp, loadedBedTemp),
            colorHex: colorFields.colorHex,
            multiColorHexes: colorFields.multiColorHexes,
            multiColorDirection: colorFields.multiColorDirection,
            externalId: text(externalId, loadedExternalId),
            transmissionDistance: td
        )
    }

    /// A field's `FieldCatalog` label — the same on every backend. `vendor_id`
    /// used to be overridden per backend (FilaMan's UI said Manufacturer where
    /// Spoolman said Vendor), but every backend's base label says Manufacturer
    /// now, and the override mechanism is gone. Initial Weight used to need an
    /// override too, for FilaMan's gross-vs-net difference (F31), but that
    /// field is NET on all three backends now — `FilaManRepository.netInitialWeight`
    /// converts on read and `spoolWeightKeys` converts back on write — so the
    /// value is normalized instead of the label being swapped.
    private func label(_ fieldID: String, in entity: LibraryEntity, default fallback: String) -> String {
        FieldCatalog.fields(for: entity).first(where: { $0.id == fieldID })?.label ?? fallback
    }

    var body: some View {
        let _ = fieldVisibilityRefreshToken
        let visibleFieldIDs = Self.visibleFieldIDs(for: store.capabilities)
        let hasAdvancedFields = [
            "price",
            "weight",
            "spool_weight",
            "article_number",
            "comment",
            "external_id"
        ].contains { visibleFieldIDs.contains($0) }

        Form {
            ServerDownFormNote()
            if let correction {
                Section {
                    Text("Material and colors are from the tag. Check them, then save.")
                    if let note = correction.note {
                        Label(note, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            if holdsResave {
                Section {
                    Text(SaveNote.unsureCreate)
                    Button("Save Again") { holdsResave = false }
                }
            }
            Section("Basic Info") {
                TextField("Name", text: $name)

                HStack {
                    Text("Material")
                        .frame(width: 80, alignment: .leading)
                    TextField("Type", text: $material)
                    Menu {
                        ForEach(materials, id: \.self) { mat in
                            Button(mat) {
                                material = mat
                                updateTempsForMaterial(mat)
                                updateDensityForMaterial(mat)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundColor(.accentColor)
                    }
                }

                // No "None": a filament's manufacturer must be one of the
                // defined manufacturers — on every backend (owner,
                // 2026-09-15). A new one is held pending and created by
                // saveFilament() before the filament (owner, 2026-10-12).
                NavigationLink {
                    ManufacturerPickerView(current: manufacturerChoice) { choice in
                        switch choice {
                        case .existing(let id, _):
                            vendorId = id
                            pendingVendorName = nil
                        case .new(let name):
                            vendorId = nil
                            pendingVendorName = name
                        case .none:
                            break
                        }
                    }
                } label: {
                    LabeledContent(
                        label("vendor_id", in: .filament, default: "Manufacturer"),
                        value: manufacturerDisplayName
                    )
                }
                .accessibilityIdentifier("filamentForm.manufacturer")
                if pendingVendorName != nil {
                    Text("Added to your manufacturers when you save.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Color") {
                FilamentColorEditor(
                    colors: $colors,
                    transmissionDistance: visibleFieldIDs.contains("td") ? $transmissionDistance : nil
                )

                if visibleFieldIDs.contains("td") {
                    HStack {
                        Text("TD (HueForge)")
                        Spacer()
                        TextField("mm", text: $transmissionDistance)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Button {
                            showTD1SRead = true
                        } label: {
                            Image(systemName: "eyedropper")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Read TD from TD1S")
                        .accessibilityIdentifier("filamentForm.td1sRead")
                    }
                }
            }

            Section("Physical Properties") {
                HStack {
                    Text("Density (g/cm3)")
                    Spacer()
                    TextField("\(AppConfig.Defaults.density)", text: densityBinding)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }

                HStack {
                    Text("Diameter (mm)")
                    Spacer()
                    TextField("\(AppConfig.Defaults.diameter)", text: $diameter)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }

            if visibleFieldIDs.contains("settings_extruder_temp") || visibleFieldIDs.contains("settings_bed_temp") {
                Section("Temperatures") {
                    if visibleFieldIDs.contains("settings_extruder_temp") {
                        HStack {
                            Text("Extruder Temp")
                            Spacer()
                            TextField("C", text: extruderTempBinding)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }

                    if visibleFieldIDs.contains("settings_bed_temp") {
                        HStack {
                            Text("Bed Temp")
                            Spacer()
                            TextField("C", text: bedTempBinding)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }
            }

            if hasAdvancedFields {
                Section("Advanced") {
                    if visibleFieldIDs.contains("price") {
                        HStack {
                            Text("Price")
                            Spacer()
                            TextField("0.00", text: $price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    if visibleFieldIDs.contains("weight") {
                        HStack {
                            Text("Net Weight")
                            Spacer()
                            TextField("0", text: $weight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    if visibleFieldIDs.contains("spool_weight") {
                        HStack {
                            Text("Default Spool Weight")
                            Spacer()
                            TextField("0", text: $spoolWeight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    if visibleFieldIDs.contains("article_number") {
                        TextField("Article Number", text: $articleNumber)
                            .textInputAutocapitalization(.never)
                    }

                    if visibleFieldIDs.contains("comment") {
                        TextField("Comment", text: $comment, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    if visibleFieldIDs.contains("external_id") {
                        TextField("External ID", text: $externalId)
                            .textInputAutocapitalization(.never)
                    }
                }
            }

            if let existing = filamentToEdit {
                // Spec 4: only an existing filament can hold links; a new one
                // gets its tags once saved.
                FilamentTagsSection(store: store, filamentId: existing.id)

                let displayName = existing.name ?? existing.material ?? "this filament"
                Section {
                    CascadeDeleteButton(
                        record: .filament(id: existing.id, name: displayName),
                        store: store,
                        confirmBeforeDelete: confirmBeforeDelete,
                        onDeleted: { dismiss() }
                    )
                }
            }
        }
        .keyboardDoneBar()
        .selectsTextOnFocus()
        .navigationTitle(filamentToEdit == nil ? "Add Filament" : "Edit Filament")
        .alert(
            "Could Not Save Filament",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .alert(
            "Limit Reached",
            isPresented: Binding(
                get: { quotaError != nil },
                set: { if !$0 { quotaError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                quotaError = nil
            }
        } message: {
            if let quotaError { Text(quotaError.errorDescription ?? "") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCustomizeFields = true
                } label: {
                    Label("Customize Fields", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { finish() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveFilament() }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || !colors.isValid
                           || !Self.isValidTransmissionDistanceText(transmissionDistance) || holdsResave)
                .needsServer()
            }
        }
        .sheet(isPresented: $showTD1SRead) {
            TD1SReadView(target: .transmissionDistance) { reading in
                if let td = reading.transmissionDistance {
                    transmissionDistance = String(TransmissionDistance.rounded(td))
                }
            }
        }
        .sheet(isPresented: $showCustomizeFields, onDismiss: { fieldVisibilityRefreshToken += 1 }) {
            NavigationStack {
                Form {
                    Section("Optional Fields") {
                        FieldVisibilityEditor(entity: .filament, capabilities: store.capabilities)
                    }
                }
                .navigationTitle("Customize Fields")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showCustomizeFields = false }
                    }
                }
            }
        }
        .onAppear {
            if store.vendors.isEmpty {
                Task { await store.fetchVendors() }
            }

            guard !didLoadFields else { return }
            didLoadFields = true

            if let filament = filamentToEdit {
                name = filament.name ?? ""
                material = filament.material ?? ""
                vendorId = filament.vendor?.id
                // A filament with no color at all starts on the default hex,
                // as the single-color form always did.
                colors = filament.colors.orDefault(AppConfig.Defaults.colorHex)

                density = filament.density.map { String($0) } ?? density
                diameter = filament.diameter.map { String($0) } ?? diameter
                extruderTemp = filament.settingsExtruderTemp.map { String($0) } ?? extruderTemp
                bedTemp = filament.settingsBedTemp.map { String($0) } ?? bedTemp

                price = filament.price.map { String($0) } ?? ""
                weight = filament.weight.map { String($0) } ?? ""
                spoolWeight = filament.spoolWeight.map { String($0) } ?? ""
                articleNumber = filament.articleNumber ?? ""
                comment = filament.comment ?? ""
                externalId = filament.externalId ?? ""
                transmissionDistance = filament.transmissionDistance
                    .map { String(TransmissionDistance.rounded($0)) } ?? ""

                loadedVendorId = vendorId
                loadedPrice = price
                loadedWeight = weight
                loadedSpoolWeight = spoolWeight
                loadedArticleNumber = articleNumber
                loadedComment = comment
                loadedExtruderTemp = extruderTemp
                loadedBedTemp = bedTemp
                loadedColors = filament.colors
                loadedExternalId = externalId
                loadedTransmissionDistance = transmissionDistance
                if let correction {
                    material = correction.material
                    colors = FilamentColors(hexes: correction.colorHexes, pattern: filament.colors.pattern)
                }
            } else if let tagData = initialData {
                let values = Self.initialFieldValues(from: tagData)
                name = values.name
                material = values.material
                colors = values.colors
                density = values.density
                extruderTemp = values.extruderTemp
                bedTemp = values.bedTemp
                transmissionDistance = values.transmissionDistance
                // The scanned manufacturer is selected, or held pending when
                // it is not among the defined ones — vendors may still be
                // loading; the onChange below seeds once they arrive.
                Task { await seedScannedVendor() }
            } else {
                if !lastFilamentMaterial.isEmpty { material = lastFilamentMaterial }
                if lastFilamentVendorId != -1 { vendorId = lastFilamentVendorId }

                colors = FilamentColors(hexes: [lastFilamentColorHex])

                density = String(lastFilamentDensity)
                diameter = String(lastFilamentDiameter)
                extruderTemp = String(lastFilamentExtruderTemp)
                bedTemp = String(lastFilamentBedTemp)
            }
        }
        // Vendors may arrive after onAppear's fetch; seed the scanned brand
        // once they do. A user's explicit pick is never overwritten
        // (`seedScannedVendor` only fills an empty selection).
        .onChange(of: store.vendors.count) { _, _ in
            // A name picked or seeded while the list was empty may now match
            // a defined manufacturer: it becomes that one.
            if let pending = pendingVendorName,
               let match = ManufacturerName.vendor(named: pending, in: store.vendors) {
                vendorId = match.id
                pendingVendorName = nil
            }
            Task { await seedScannedVendor() }
        }
    }

    private func saveFilament() async {
        isSaving = true
        defer { isSaving = false }

        // The picker offers no "None": a filament's manufacturer must be one
        // of the defined manufacturers, on every backend. This also means a
        // legacy vendorless filament must be assigned one before it can be
        // saved here. A pending one is created first; if that fails, nothing
        // is saved.
        let vendorId: Int
        if let picked = self.vendorId {
            vendorId = picked
        } else if let pending = pendingVendorName {
            if store.vendors.isEmpty {
                await store.fetchVendors()
            }
            guard let vendor = await ManufacturerName.resolve(pending, in: store.vendors, create: { name in
                await store.addVendor(name: name)
            }) else {
                if let quota = store.lastQuotaError {
                    quotaError = quota
                } else {
                    saveErrorMessage = "\(pending) could not be added as a manufacturer."
                        + (store.errorMessage.map { " \($0)" } ?? "")
                }
                return
            }
            // Kept selected: a retry after a failed filament save reuses it.
            self.vendorId = vendor.id
            pendingVendorName = nil
            vendorId = vendor.id
        } else {
            saveErrorMessage = "A filament needs a manufacturer. Pick one from the list."
            return
        }

        let draft = Self.filamentPayload(
            name: name,
            vendorId: vendorId,
            material: material,
            colors: colors,
            density: density,
            diameter: diameter,
            extruderTemp: extruderTemp,
            bedTemp: bedTemp,
            price: price,
            weight: weight,
            spoolWeight: spoolWeight,
            articleNumber: articleNumber,
            comment: comment,
            externalId: externalId,
            transmissionDistance: transmissionDistance,
            loadedTransmissionDistance: loadedTransmissionDistance,
            loadedVendorId: loadedVendorId,
            loadedPrice: loadedPrice,
            loadedWeight: loadedWeight,
            loadedSpoolWeight: loadedSpoolWeight,
            loadedArticleNumber: loadedArticleNumber,
            loadedComment: loadedComment,
            loadedExtruderTemp: loadedExtruderTemp,
            loadedBedTemp: loadedBedTemp,
            loadedExternalId: loadedExternalId,
            loadedColors: loadedColors
        )

        var didSave = false
        var createdFilament: Filament? = nil
        let written = await serverLink.outcome {
            if let filament = filamentToEdit {
                didSave = await store.updateFilament(id: filament.id, draft: draft)
            } else {
                createdFilament = await store.addFilament(draft: draft)
                didSave = createdFilament != nil
            }
            return didSave
        }
        if filamentToEdit == nil, createdFilament == nil, let quota = store.lastQuotaError {
            quotaError = quota
            return
        }

        // A `true` with a message means the filament was written but something
        // it carried was not — its colour, or a multi-colour direction the
        // backend cannot store. Reading the message only on the failure branch
        // is what made that dismiss in silence (plan defect I1).
        let outcome = SaveOutcome.classify(
            didSave: didSave,
            message: store.errorMessage,
            failureFallback: "The filament could not be saved."
        )
        if let caveat = outcome.caveat { store.postSaveNotice(caveat, record: recordLabel) }

        if outcome.didWrite {
            if let created = createdFilament {
                onSaveFilament?(created)
            }
            lastFilamentMaterial = material.trimmingCharacters(in: .whitespacesAndNewlines)
            lastFilamentVendorId = vendorId
            if let primary = colors.primaryHex { lastFilamentColorHex = primary }
            if let densityValue = draft.density {
                lastFilamentDensity = densityValue
            }
            if let diameterValue = draft.diameter {
                lastFilamentDiameter = diameterValue
            }
            if let extruderValue = draft.extruderTemp.valueOnCreate {
                lastFilamentExtruderTemp = extruderValue
            }
            if let bedValue = draft.bedTemp.valueOnCreate {
                lastFilamentBedTemp = bedValue
            }

            finish()
        } else {
            saveErrorMessage = outcome.failure.map { SaveNote.failure(written, otherwise: $0) }
            holdsResave = SaveNote.holdsResave(after: written, isCreate: filamentToEdit == nil)
        }
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private func updateTempsForMaterial(_ mat: String) {
        if !userModifiedTemps, let defaults = AppConfig.materialPresets[mat] {
            extruderTemp = String(defaults.extruder)
            bedTemp = String(defaults.bed)
        }
    }

    private func updateDensityForMaterial(_ mat: String) {
        if !userModifiedDensity {
            density = Self.seededDensity(forMaterial: mat)
        }
    }

    /// The density a material pick, or a scan whose tag states none, seeds:
    /// the material's typical one from the TigerTag registry, else PLA's.
    static func seededDensity(forMaterial material: String) -> String {
        String(TigerTagRegistry.materialDensity(for: material) ?? AppConfig.Defaults.density)
    }
}
