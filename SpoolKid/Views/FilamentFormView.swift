//
//  FilamentFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Filament in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolmanService
    let baseUrl: String
    var filamentToEdit: SpoolmanFilament?

    @AppStorage("remember_filament_data") private var rememberFilamentData = false
    @AppStorage("last_filament_material") private var lastFilamentMaterial: String = ""
    @AppStorage("last_filament_vendor_id") private var lastFilamentVendorId: Int = -1
    @AppStorage("last_filament_color_hex") private var lastFilamentColorHex: String = AppConfig.Defaults.colorHex
    @AppStorage("last_filament_density") private var lastFilamentDensity: Double = AppConfig.Defaults.density
    @AppStorage("last_filament_diameter") private var lastFilamentDiameter: Double = AppConfig.Defaults.diameter
    @AppStorage("last_filament_extruder_temp") private var lastFilamentExtruderTemp: Int = AppConfig.Defaults.extruderTemp
    @AppStorage("last_filament_bed_temp") private var lastFilamentBedTemp: Int = AppConfig.Defaults.bedTemp

    @State private var name: String = ""
    @State private var material: String = ""
    @State private var vendorId: Int?
    @State private var colorHex: String = AppConfig.Defaults.colorHex
    @State private var color: Color = Color(hex: AppConfig.Defaults.colorHex) ?? .black
    @State private var density: String = String(AppConfig.Defaults.density)
    @State private var diameter: String = String(AppConfig.Defaults.diameter)
    @State private var extruderTemp: String = String(AppConfig.Defaults.extruderTemp)
    @State private var bedTemp: String = String(AppConfig.Defaults.bedTemp)
    @State private var price: String = ""
    @State private var weight: String = ""
    @State private var spoolWeight: String = ""
    @State private var articleNumber: String = ""
    @State private var comment: String = ""
    @State private var multiColorHexes: String = ""
    @State private var multiColorDirection: String = ""
    @State private var externalId: String = ""
    @State private var extraJSON: String = ""

    @State private var userModifiedTemps: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?

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

    static func visibleFieldIDs(store: SpoolmanFieldVisibilityStore = .init()) -> Set<String> {
        store.visibleFieldIDs(for: .filament)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extraJSONValidationError(_ extraJSON: String) -> String? {
        let normalizedExtraJSON = normalized(extraJSON)
        guard !normalizedExtraJSON.isEmpty else {
            return nil
        }

        guard let data = normalizedExtraJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let extra = object as? [String: String] else {
            return "Extra JSON must be a valid JSON object with string values."
        }

        if extra.isEmpty {
            return nil
        }

        return nil
    }

    static func filamentPayload(
        name: String,
        vendorId: Int?,
        material: String,
        colorHex: String,
        density: String,
        diameter: String,
        extruderTemp: String,
        bedTemp: String,
        price: String,
        weight: String,
        spoolWeight: String,
        articleNumber: String,
        comment: String,
        multiColorHexes: String,
        multiColorDirection: String,
        externalId: String,
        extraJSON: String
    ) -> [String: Any] {
        func parseDouble(_ value: String) -> Double? {
            let normalizedValue = Self.normalized(value).replacingOccurrences(of: ",", with: ".")
            guard !normalizedValue.isEmpty else { return nil }
            return Double(normalizedValue)
        }

        func parseInt(_ value: String) -> Int? {
            let normalizedValue = Self.normalized(value)
            guard !normalizedValue.isEmpty else { return nil }
            return Int(normalizedValue)
        }

        let normalizedExtraJSON = Self.normalized(extraJSON)
        let extra: [String: String]? = if normalizedExtraJSON.isEmpty {
            nil
        } else {
            (try? JSONSerialization.jsonObject(with: Data(normalizedExtraJSON.utf8))) as? [String: String]
        }

        return SpoolmanPayloadBuilder.filamentPayload(
            name: Self.normalized(name).isEmpty ? nil : Self.normalized(name),
            vendorId: vendorId,
            material: Self.normalized(material).isEmpty ? nil : Self.normalized(material),
            price: parseDouble(price),
            density: parseDouble(density),
            diameter: parseDouble(diameter),
            weight: parseDouble(weight),
            spoolWeight: parseDouble(spoolWeight),
            articleNumber: Self.normalized(articleNumber).isEmpty ? nil : Self.normalized(articleNumber),
            comment: Self.normalized(comment).isEmpty ? nil : Self.normalized(comment),
            extruderTemp: parseInt(extruderTemp),
            bedTemp: parseInt(bedTemp),
            colorHex: Self.normalized(colorHex).isEmpty ? nil : Self.normalized(colorHex),
            multiColorHexes: Self.normalized(multiColorHexes).isEmpty ? nil : Self.normalized(multiColorHexes),
            multiColorDirection: Self.normalized(multiColorDirection).isEmpty ? nil : Self.normalized(multiColorDirection),
            externalId: Self.normalized(externalId).isEmpty ? nil : Self.normalized(externalId),
            extra: extra
        )
    }

    static func filamentUpdateClearFieldKeys(
        vendorId: Int?,
        price: String,
        weight: String,
        spoolWeight: String,
        articleNumber: String,
        comment: String,
        multiColorHexes: String,
        multiColorDirection: String,
        externalId: String,
        extraJSON: String,
        extruderTemp: String? = nil,
        bedTemp: String? = nil
    ) -> Set<String> {
        var keys: Set<String> = []

        if vendorId == nil {
            keys.insert("vendor_id")
        }

        if normalized(price).isEmpty {
            keys.insert("price")
        }

        if normalized(weight).isEmpty {
            keys.insert("weight")
        }

        if normalized(spoolWeight).isEmpty {
            keys.insert("spool_weight")
        }

        if normalized(articleNumber).isEmpty {
            keys.insert("article_number")
        }

        if normalized(comment).isEmpty {
            keys.insert("comment")
        }

        if normalized(multiColorHexes).isEmpty {
            keys.insert("multi_color_hexes")
        }

        if normalized(multiColorDirection).isEmpty {
            keys.insert("multi_color_direction")
        }

        if normalized(externalId).isEmpty {
            keys.insert("external_id")
        }

        if normalized(extraJSON).isEmpty {
            keys.insert("extra")
        }

        if let extruderTemp, normalized(extruderTemp).isEmpty {
            keys.insert("settings_extruder_temp")
        }

        if let bedTemp, normalized(bedTemp).isEmpty {
            keys.insert("settings_bed_temp")
        }

        return keys
    }

    var body: some View {
        let visibleFieldIDs = Self.visibleFieldIDs()
        let hasAdvancedFields = [
            "price",
            "weight",
            "spool_weight",
            "article_number",
            "comment",
            "multi_color_hexes",
            "multi_color_direction",
            "external_id",
            "extra"
        ].contains { visibleFieldIDs.contains($0) }

        NavigationStack {
            Form {
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
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.accentColor)
                        }
                    }

                    Picker("Vendor", selection: $vendorId) {
                        Text("None").tag(Optional<Int>.none)
                        ForEach(service.vendors) { vendor in
                            Text(vendor.name).tag(Optional(vendor.id))
                        }
                    }
                }

                Section("Color") {
                    HStack {
                        Text("Color")
                            .frame(width: 80, alignment: .leading)

                        TextField("Hex", text: $colorHex)
                            .onChange(of: colorHex) { _, newValue in
                                if let newColor = Color(hex: newValue) {
                                    color = newColor
                                }
                            }
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)

                        ColorPicker("", selection: $color)
                            .labelsHidden()
                            .onChange(of: color) { _, newColor in
                                if let hex = newColor.toHex() {
                                    colorHex = hex
                                }
                            }
                    }
                }

                Section("Physical Properties") {
                    HStack {
                        Text("Density (g/cm3)")
                        Spacer()
                        TextField("\(AppConfig.Defaults.density)", text: $density)
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

                Section("Temperatures") {
                    HStack {
                        Text("Extruder Temp")
                        Spacer()
                        TextField("C", text: extruderTempBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }

                    HStack {
                        Text("Bed Temp")
                        Spacer()
                        TextField("C", text: bedTempBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
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

                        if visibleFieldIDs.contains("multi_color_hexes") {
                            TextField("Multi-Color Hexes", text: $multiColorHexes)
                                .textInputAutocapitalization(.characters)
                        }

                        if visibleFieldIDs.contains("multi_color_direction") {
                            TextField("Multi-Color Direction", text: $multiColorDirection)
                                .textInputAutocapitalization(.never)
                        }

                        if visibleFieldIDs.contains("external_id") {
                            TextField("External ID", text: $externalId)
                                .textInputAutocapitalization(.never)
                        }

                        if visibleFieldIDs.contains("extra") {
                            TextField("Extra JSON", text: $extraJSON, axis: .vertical)
                                .lineLimit(2...5)
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
            }
            .hideKeyboardOnTap()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveFilament() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if service.vendors.isEmpty {
                    Task { await service.fetchVendors(baseUrl: baseUrl) }
                }

                if let filament = filamentToEdit {
                    name = filament.name ?? ""
                    material = filament.material ?? ""
                    vendorId = filament.vendor?.id
                    colorHex = filament.colorHex ?? AppConfig.Defaults.colorHex
                    if let hex = filament.colorHex {
                        color = Color(hex: hex) ?? .black
                    }

                    density = filament.density.map { String($0) } ?? density
                    diameter = filament.diameter.map { String($0) } ?? diameter
                    extruderTemp = filament.settingsExtruderTemp.map { String($0) } ?? extruderTemp
                    bedTemp = filament.settingsBedTemp.map { String($0) } ?? bedTemp

                    price = filament.price.map { String($0) } ?? ""
                    weight = filament.weight.map { String($0) } ?? ""
                    spoolWeight = filament.spoolWeight.map { String($0) } ?? ""
                    articleNumber = filament.articleNumber ?? ""
                    comment = filament.comment ?? ""
                    multiColorHexes = filament.multiColorHexes ?? ""
                    multiColorDirection = filament.multiColorDirection ?? ""
                    externalId = filament.externalId ?? ""

                    if let extra = filament.extra,
                       let data = try? JSONSerialization.data(withJSONObject: extra, options: [.sortedKeys]),
                       let string = String(data: data, encoding: .utf8) {
                        extraJSON = string
                    } else {
                        extraJSON = ""
                    }
                } else if rememberFilamentData {
                    if !lastFilamentMaterial.isEmpty { material = lastFilamentMaterial }
                    if lastFilamentVendorId != -1 { vendorId = lastFilamentVendorId }

                    colorHex = lastFilamentColorHex
                    if let newColor = Color(hex: colorHex) {
                        color = newColor
                    }

                    density = String(lastFilamentDensity)
                    diameter = String(lastFilamentDiameter)
                    extruderTemp = String(lastFilamentExtruderTemp)
                    bedTemp = String(lastFilamentBedTemp)
                }
            }
        }
    }

    private func saveFilament() async {
        isSaving = true
        defer { isSaving = false }

        if let validationError = Self.extraJSONValidationError(extraJSON) {
            saveErrorMessage = validationError
            return
        }

        let payload = Self.filamentPayload(
            name: name,
            vendorId: vendorId,
            material: material,
            colorHex: colorHex,
            density: density,
            diameter: diameter,
            extruderTemp: extruderTemp,
            bedTemp: bedTemp,
            price: price,
            weight: weight,
            spoolWeight: spoolWeight,
            articleNumber: articleNumber,
            comment: comment,
            multiColorHexes: multiColorHexes,
            multiColorDirection: multiColorDirection,
            externalId: externalId,
            extraJSON: extraJSON
        )

        let clearFieldKeys: Set<String> = if filamentToEdit != nil {
            Self.filamentUpdateClearFieldKeys(
                vendorId: vendorId,
                price: price,
                weight: weight,
                spoolWeight: spoolWeight,
                articleNumber: articleNumber,
                comment: comment,
                multiColorHexes: multiColorHexes,
                multiColorDirection: multiColorDirection,
                externalId: externalId,
                extraJSON: extraJSON,
                extruderTemp: extruderTemp,
                bedTemp: bedTemp
            )
        } else {
            []
        }

        let didSave: Bool
        if let filament = filamentToEdit {
            didSave = await service.updateFilament(
                id: filament.id,
                name: payload["name"] as? String,
                vendorId: payload["vendor_id"] as? Int,
                material: payload["material"] as? String,
                colorHex: payload["color_hex"] as? String,
                density: payload["density"] as? Double,
                diameter: payload["diameter"] as? Double,
                extruderTemp: payload["settings_extruder_temp"] as? Int,
                bedTemp: payload["settings_bed_temp"] as? Int,
                price: payload["price"] as? Double,
                weight: payload["weight"] as? Double,
                spoolWeight: payload["spool_weight"] as? Double,
                articleNumber: payload["article_number"] as? String,
                comment: payload["comment"] as? String,
                multiColorHexes: payload["multi_color_hexes"] as? String,
                multiColorDirection: payload["multi_color_direction"] as? String,
                externalId: payload["external_id"] as? String,
                extra: payload["extra"] as? [String: String],
                clearFieldKeys: clearFieldKeys,
                baseUrl: baseUrl
            )
        } else {
            didSave = await service.addFilament(
                name: payload["name"] as? String,
                vendorId: payload["vendor_id"] as? Int,
                material: payload["material"] as? String,
                colorHex: payload["color_hex"] as? String,
                density: payload["density"] as? Double,
                diameter: payload["diameter"] as? Double,
                extruderTemp: payload["settings_extruder_temp"] as? Int,
                bedTemp: payload["settings_bed_temp"] as? Int,
                price: payload["price"] as? Double,
                weight: payload["weight"] as? Double,
                spoolWeight: payload["spool_weight"] as? Double,
                articleNumber: payload["article_number"] as? String,
                comment: payload["comment"] as? String,
                multiColorHexes: payload["multi_color_hexes"] as? String,
                multiColorDirection: payload["multi_color_direction"] as? String,
                externalId: payload["external_id"] as? String,
                extra: payload["extra"] as? [String: String],
                baseUrl: baseUrl
            ) != nil
        }

        if didSave {
            if rememberFilamentData {
                lastFilamentMaterial = material.trimmingCharacters(in: .whitespacesAndNewlines)
                lastFilamentVendorId = vendorId ?? -1
                lastFilamentColorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
                if let densityValue = payload["density"] as? Double {
                    lastFilamentDensity = densityValue
                }
                if let diameterValue = payload["diameter"] as? Double {
                    lastFilamentDiameter = diameterValue
                }
                if let extruderValue = payload["settings_extruder_temp"] as? Int {
                    lastFilamentExtruderTemp = extruderValue
                }
                if let bedValue = payload["settings_bed_temp"] as? Int {
                    lastFilamentBedTemp = bedValue
                }
            }

            dismiss()
        } else {
            saveErrorMessage = service.errorMessage ?? "The filament could not be saved."
        }
    }

    private func updateTempsForMaterial(_ mat: String) {
        if !userModifiedTemps, let defaults = AppConfig.materialPresets[mat] {
            extruderTemp = String(defaults.extruder)
            bedTemp = String(defaults.bed)
        }
    }
}
