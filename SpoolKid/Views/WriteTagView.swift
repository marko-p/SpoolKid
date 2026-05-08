//
//  WriteTagView.swift
//  SpoolKid
//
//  Purpose: The UI for creating and writing new NFC tags.
//  Features:
//  - Form to input filament details (Material, Color, Temps, etc.).
//  - Integration with `NFCManager` to trigger the write operation.
//  - Option to link a Spoolman ID (controlled by settings).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct WriteTagView: View {
    @StateObject private var nfcManager = NFCManager()
    @StateObject private var spoolManService = SpoolmanService()
    @StateObject private var recentTagManager = RecentTagManager()
    
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("write_spool_id") private var writeSpoolId: Bool = true
    @AppStorage("snapmaker_u1_compat") private var snapmakerU1Compat: Bool = false
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @State private var selectedFormatOverride: TagFormat = .openSpool
    private let nfcVisibilityStore = NFCFieldVisibilityStore()
    
    // Form Fields
    @State private var name: String = ""
    @State private var material: String = AppConfig.Defaults.material
    @State private var subtype: String = "Basic"
    @State private var brand: String = AppConfig.Defaults.brand
    @State private var color: Color = Color(hex: AppConfig.Defaults.colorHex) ?? .black
    @State private var colorHex: String = AppConfig.Defaults.colorHex
    @State private var minNozzleTemp: Int = AppConfig.Defaults.minNozzleTemp
    @State private var maxNozzleTemp: Int = AppConfig.Defaults.maxNozzleTemp
    @State private var minBedTemp: Int = AppConfig.Defaults.minBedTemp
    @State private var maxBedTemp: Int = AppConfig.Defaults.maxBedTemp
    @State private var spoolmanId: Int? = nil
    @State private var spoolmanIdInput: String = ""
    @State private var densityInput: String = ""
    @State private var transmissionDistanceInput: String = ""
    @State private var gtinInput: String = ""
    @State private var includeManufacturedDate: Bool = false
    @State private var manufacturedDate: Date = Date()
    @State private var countryOfOriginInput: String = ""
    @State private var preheatTempInput: String = ""
    @State private var dryingTempInput: String = ""
    @State private var dryingTimeInput: String = ""
    @State private var nominalWeightInput: String = ""
    @State private var actualWeightInput: String = ""
    @State private var emptyContainerWeightInput: String = ""
    @State private var selectedOpenPrintTagMaterialTypeID: Int?
    @State private var selectedMaterialTagIDs: Set<Int> = []
    @State private var selectedCertificationIDs: Set<Int> = []
    @State private var tagURLInput: String = ""
    
    @State private var selectedSpoolId: Int?
    
    // Delight state
    @State private var showSuccessBanner = false
    @State private var successBannerScale: CGFloat = 0.85
    @State private var colorSwatchScale: CGFloat = 1.0
    
    // Snapmaker U1 compatibility state
    @State private var showCompatPicker = false
    @State private var incompatibleMaterial = ""
    @State private var pendingTagData: FilamentTagData? = nil
    @State private var expandMaterialTags: Bool = false
    @State private var expandCertifications: Bool = false
    
    var initialData: FilamentTagData?
    
    let brands = AppConfig.brands
    
    /// Derived property: is Snapmaker U1 compat active for the current format?
    private var isU1CompatActive: Bool {
        snapmakerU1Compat && selectedFormatOverride == .openSpool
    }

    private var visibleFieldDefinitions: [NFCFieldDefinition] {
        WriteTagFormAssembler.visibleFields(format: selectedFormatOverride, visibilityStore: nfcVisibilityStore)
    }

    private var visibleFieldIDs: Set<String> {
        Set(visibleFieldDefinitions.map(\.id))
    }
    
    /// When Snapmaker U1 compat is enabled (and format is OpenSpool), show only U1-compatible materials.
    private var availableMaterials: [String] {
        isU1CompatActive ? AppConfig.snapmakerU1Materials : AppConfig.materials
    }
    
    var body: some View {
        Form {
            Section("Tag Format") {
                Picker("Format", selection: $selectedFormatOverride) {
                    ForEach(TagFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            }

            Section("Filament Details") {
                // Material Type
                if visibleFieldIDs.contains("material") {
                    if selectedFormatOverride == .openPrintTag {
                        Picker("Material", selection: Binding<Int>(
                            get: {
                                selectedOpenPrintTagMaterialTypeID
                                ?? AppConfig.openPrintTagMaterialTypeID(for: material)
                                ?? 0
                            },
                            set: { newID in
                                selectedOpenPrintTagMaterialTypeID = newID
                                if let mapped = AppConfig.openPrintTagMaterialTypes[newID] {
                                    material = mapped
                                }
                            }
                        )) {
                            ForEach(AppConfig.openPrintTagMaterialTypes.keys.sorted(), id: \.self) { key in
                                Text(AppConfig.openPrintTagMaterialTypes[key] ?? "\(key)").tag(key)
                            }
                        }
                    } else {
                        HStack {
                            Text("Material")
                                .frame(width: 80, alignment: .leading)
                            TextField("Type", text: $material)
                            Menu {
                                ForEach(availableMaterials, id: \.self) { mat in
                                    Button(mat) {
                                        material = mat
                                    }
                                }
                            } label: {
                            Image(systemName: "chevron.down.circle")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                
                // Color
                if visibleFieldIDs.contains("color_hex") {
                    HStack {
                        Text("Color")
                            .frame(width: 80, alignment: .leading)
                        
                        TextField("Hex", text: $colorHex)
                            .onChange(of: colorHex) { _, newValue in
                                if let newColor = Color(hex: newValue) {
                                    color = newColor
                                    bounceColorSwatch()
                                }
                            }
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)
                        
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                            .scaleEffect(colorSwatchScale)
                        
                        ColorPicker("", selection: $color)
                            .labelsHidden()
                            .onChange(of: color) { _, newColor in
                                if let hex = newColor.toHex() {
                                    colorHex = hex
                                }
                                bounceColorSwatch()
                            }
                    }
                }
                
                // Brand Name
                if visibleFieldIDs.contains("brand") {
                    HStack {
                        Text("Brand")
                            .frame(width: 80, alignment: .leading)
                        TextField("Brand Name", text: $brand)
                        Menu {
                            ForEach(brands, id: \.self) { b in
                                Button(b) {
                                    brand = b
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                if visibleFieldIDs.contains("subtype") {
                    HStack {
                        Text("Subtype")
                            .frame(width: 80, alignment: .leading)
                        TextField("Subtype", text: $subtype)
                        Menu {
                            ForEach(SubtypeOptionService.presetOptions, id: \.self) { option in
                                Button(option) {
                                    subtype = option
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                if WriteTagFormAssembler.shouldShowNameField(
                    format: selectedFormatOverride,
                    visibleFieldIDs: visibleFieldIDs,
                    isU1CompatActive: isU1CompatActive
                ) {
                    HStack {
                        Text("Name")
                            .frame(width: 80, alignment: .leading)
                        TextField("Filament Name", text: $name)
                    }
                }
            }
            
            if visibleFieldIDs.contains("temp_range") {
                Section("Printing Parameters") {
                    HStack {
                        Text("Min Nozzle")
                        Spacer()
                        TextField("°C", value: $minNozzleTemp, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: $minNozzleTemp, in: 0...400)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Max Nozzle")
                        Spacer()
                        TextField("°C", value: $maxNozzleTemp, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: $maxNozzleTemp, in: 0...400)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Min Bed")
                        Spacer()
                        TextField("°C", value: $minBedTemp, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: $minBedTemp, in: 0...150)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Max Bed")
                        Spacer()
                        TextField("°C", value: $maxBedTemp, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: $maxBedTemp, in: 0...150)
                            .labelsHidden()
                    }
                }
            }

            if selectedFormatOverride == .openPrintTag {
                Section("OpenPrintTag Optional") {
                    if visibleFieldIDs.contains("density") {
                        HStack {
                            Text("Density")
                                .frame(width: 100, alignment: .leading)
                            TextField("g/cm3", text: $densityInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("transmission_distance") {
                        HStack {
                            Text("Trans. Dist")
                                .frame(width: 100, alignment: .leading)
                            TextField("HueForge TD", text: $transmissionDistanceInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("gtin") {
                        HStack {
                            Text("GTIN")
                                .frame(width: 100, alignment: .leading)
                            TextField("8/12/13/14 digits", text: $gtinInput)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("manufactured_date") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Include Mfg Date", isOn: $includeManufacturedDate)

                            if includeManufacturedDate {
                                DatePicker(
                                    "Mfg Date",
                                    selection: $manufacturedDate,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                            }
                        }
                    }

                    if visibleFieldIDs.contains("country_of_origin") {
                        HStack {
                            Text("Origin")
                                .frame(width: 100, alignment: .leading)
                            TextField("ISO-2", text: $countryOfOriginInput)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("preheat_temperature") {
                        HStack {
                            Text("Preheat")
                                .frame(width: 100, alignment: .leading)
                            TextField("°C", text: $preheatTempInput)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("drying_temperature") {
                        HStack {
                            Text("Drying Temp")
                                .frame(width: 100, alignment: .leading)
                            TextField("°C", text: $dryingTempInput)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("drying_time") {
                        HStack {
                            Text("Drying Time")
                                .frame(width: 100, alignment: .leading)
                            TextField("minutes", text: $dryingTimeInput)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("nominal_netto_full_weight") {
                        HStack {
                            Text("Nominal W")
                                .frame(width: 100, alignment: .leading)
                            TextField("grams", text: $nominalWeightInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("actual_netto_full_weight") {
                        HStack {
                            Text("Actual W")
                                .frame(width: 100, alignment: .leading)
                            TextField("grams", text: $actualWeightInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("empty_container_weight") {
                        HStack {
                            Text("Container W")
                                .frame(width: 100, alignment: .leading)
                            TextField("grams", text: $emptyContainerWeightInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if visibleFieldIDs.contains("material_tags") {
                        DisclosureGroup(isExpanded: $expandMaterialTags) {
                            Text("Selected: \(selectedMaterialTagIDs.count)/16")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(AppConfig.openPrintTagMaterialTagGroups, id: \.title) { group in
                                DisclosureGroup(group.title) {
                                    ForEach(group.ids, id: \.self) { tagID in
                                        if let tagLabel = AppConfig.openPrintTagMaterialTags[tagID] {
                                            Toggle(
                                                tagLabel,
                                                isOn: Binding(
                                                    get: { selectedMaterialTagIDs.contains(tagID) },
                                                    set: { isSelected in
                                                        if isSelected {
                                                            if selectedMaterialTagIDs.count < 16 {
                                                                selectedMaterialTagIDs.insert(tagID)
                                                            }
                                                        } else {
                                                            selectedMaterialTagIDs.remove(tagID)
                                                        }
                                                    }
                                                )
                                            )
                                            .disabled(!selectedMaterialTagIDs.contains(tagID) && selectedMaterialTagIDs.count >= 16)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Material Tags")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(selectedMaterialTagIDs.count)/16")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if visibleFieldIDs.contains("certifications") {
                        DisclosureGroup(isExpanded: $expandCertifications) {
                            if AppConfig.openPrintTagCertificationGroups.isEmpty {
                                ForEach(AppConfig.openPrintTagCertifications.keys.sorted(), id: \.self) { certID in
                                    if let certLabel = AppConfig.openPrintTagCertifications[certID] {
                                        Toggle(
                                            certLabel,
                                            isOn: Binding(
                                                get: { selectedCertificationIDs.contains(certID) },
                                                set: { isSelected in
                                                    if isSelected {
                                                        selectedCertificationIDs.insert(certID)
                                                    } else {
                                                        selectedCertificationIDs.remove(certID)
                                                    }
                                                }
                                            )
                                        )
                                    }
                                }
                            } else {
                                ForEach(AppConfig.openPrintTagCertificationGroups, id: \.title) { group in
                                    DisclosureGroup(group.title) {
                                        ForEach(group.ids, id: \.self) { certID in
                                            if let certLabel = AppConfig.openPrintTagCertifications[certID] {
                                                Toggle(
                                                    certLabel,
                                                    isOn: Binding(
                                                        get: { selectedCertificationIDs.contains(certID) },
                                                        set: { isSelected in
                                                            if isSelected {
                                                                selectedCertificationIDs.insert(certID)
                                                            } else {
                                                                selectedCertificationIDs.remove(certID)
                                                            }
                                                        }
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Certifications")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(selectedCertificationIDs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if visibleFieldIDs.contains("tag_url") {
                        HStack {
                            Text("Tag URL")
                                .frame(width: 100, alignment: .leading)
                            TextField("https://...", text: $tagURLInput)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                }
            }
            
            if visibleFieldIDs.contains("spool_id") {
                Section("Linked Data") {
                HStack {
                    Text("Spoolman ID")
                        .frame(width: 100, alignment: .leading)
                    TextField("Optional", text: $spoolmanIdInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: spoolmanIdInput) { _, newValue in
                            updateSpoolmanId(from: newValue)
                        }

                    if !spoolmanIdInput.isEmpty {
                        Button {
                            spoolmanIdInput = ""
                            spoolmanId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !writeSpoolId {
                    Text("'Write Spool ID to Tag' is disabled in Settings. This value will be ignored when writing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            }

        }
        .safeAreaInset(edge: .bottom) {
            Button(action: writeTag) {
                Label("Write to NFC Tag", systemImage: "badge.plus.radiowaves.right")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .writeTagButtonStyle()
            .disabled(nfcManager.isScanning)
            .padding()
        }
        .overlay(alignment: .bottom) {
            if showSuccessBanner {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.statusSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tag Written")
                            .font(.headline)
                        Text("\(brand) \(material) — \(colorHex)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                        .scaleEffect(colorSwatchScale)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(color: Color(.label).opacity(0.12), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .scaleEffect(successBannerScale)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .hideKeyboardOnTap()
        .navigationTitle("Create Tag")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    var data = buildTagData()
                    // Restore name for display if stripped by format logic
                    if data.name == nil && !name.isEmpty {
                        data.name = name
                    }
                    recentTagManager.addTag(data)
                    triggerWriteSuccess()
                } label: {
                    Text("Add")
                }
            }
        }
        .onAppear {
            selectedFormatOverride = WriteTagFormAssembler.initialOverride(defaultRawValue: nfcTagFormat)
            if let data = initialData {
                populateFromData(data)
            }
        }
        .onChange(of: selectedFormatOverride) { _, newValue in
            guard newValue == .openPrintTag else { return }
            applyOpenPrintTagAutoInference()
        }
        .alert(isPresented: Binding<Bool>(
            get: { !nfcManager.alertMessage.isEmpty },
            set: { _ in nfcManager.alertMessage = "" }
        )) {
            Alert(title: Text("NFC Error"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showCompatPicker) {
            SnapmakerCompatPickerView(
                incompatibleMaterial: incompatibleMaterial,
                compatibleMaterials: AppConfig.snapmakerU1Materials,
                onSelect: { selectedMaterial in
                    if var data = pendingTagData {
                        data.material = selectedMaterial
                        nfcManager.writeTag(data: data, format: selectedFormatOverride)
                    }
                    showCompatPicker = false
                },
                onCancel: {
                    pendingTagData = nil
                    showCompatPicker = false
                }
            )
        }
        .onChange(of: nfcManager.lastWriteSucceeded) { _, succeeded in
            if succeeded, var data = nfcManager.tagDataToWrite {
                // Restore name for Recent Tags display (may have been stripped for NFC format)
                if data.name == nil && !name.isEmpty {
                    data.name = name
                }
                recentTagManager.addTag(data)
                triggerWriteSuccess()
            }
        }
    }
    
    private func populateFromData(_ data: FilamentTagData) {
        self.name = data.name ?? ""
        self.material = data.material
        if let subtype = data.subtype, !subtype.isEmpty {
            self.subtype = subtype
        } else if let name = data.name {
            self.subtype = deriveSubtype(from: name)
        } else {
            self.subtype = ""
        }
        self.brand = data.brand
        self.color = data.color
        self.colorHex = data.colorHex
        self.minNozzleTemp = data.minNozzleTemp
        self.maxNozzleTemp = data.maxNozzleTemp
        self.minBedTemp = data.minBedTemp
        self.maxBedTemp = data.maxBedTemp
        self.spoolmanId = data.spoolmanId
        self.spoolmanIdInput = data.spoolmanId.map(String.init) ?? ""
        self.densityInput = data.density.map { String($0) } ?? ""
        self.transmissionDistanceInput = data.transmissionDistance.map { String($0) } ?? ""
        self.gtinInput = data.gtin ?? ""
        if let unix = data.manufacturedDateUnix,
           let parsedDate = WriteTagFormAssembler.date(fromUnixSeconds: unix) {
            self.includeManufacturedDate = true
            self.manufacturedDate = parsedDate
        } else {
            self.includeManufacturedDate = false
            self.manufacturedDate = Date()
        }
        self.countryOfOriginInput = data.countryOfOrigin ?? ""
        self.preheatTempInput = data.preheatTemp.map(String.init) ?? ""
        self.dryingTempInput = data.dryingTemp.map(String.init) ?? ""
        self.dryingTimeInput = data.dryingTime.map(String.init) ?? ""
        self.nominalWeightInput = data.nominalNetWeight.map { String($0) } ?? ""
        self.actualWeightInput = data.actualNetWeight.map { String($0) } ?? ""
        self.emptyContainerWeightInput = data.emptyContainerWeight.map { String($0) } ?? ""
        self.selectedOpenPrintTagMaterialTypeID = data.openPrintTagMaterialTypeID
        if selectedFormatOverride == .openPrintTag {
            if let mappedID = data.openPrintTagMaterialTypeID,
               let mappedMaterial = AppConfig.openPrintTagMaterialTypes[mappedID] {
                self.material = mappedMaterial
            } else if let mappedID = AppConfig.openPrintTagMaterialTypeID(for: self.material),
                      let mappedMaterial = AppConfig.openPrintTagMaterialTypes[mappedID] {
                self.selectedOpenPrintTagMaterialTypeID = mappedID
                self.material = mappedMaterial
            }
        }
        self.selectedMaterialTagIDs = Set((data.materialTags ?? []).filter { AppConfig.openPrintTagMaterialTags[$0] != nil }.prefix(16))
        self.selectedCertificationIDs = Set((data.certifications ?? []).filter { AppConfig.openPrintTagCertifications[$0] != nil })
        self.tagURLInput = data.tagURL ?? ""

        if selectedFormatOverride == .openPrintTag {
            applyOpenPrintTagAutoInference()
        }
    }

    private func applyOpenPrintTagAutoInference() {
        if let inferredDensity = initialData?.density, parseOptionalDouble(densityInput) == nil {
            densityInput = String(inferredDensity)
        }

        let existing = Array(selectedMaterialTagIDs).sorted()
        let merged = OpenPrintTagInference.mergedMaterialTags(
            existing: existing,
            name: name,
            material: material,
            subtype: subtype
        )
        selectedMaterialTagIDs = Set(merged)
    }

    private func updateSpoolmanId(from rawValue: String) {
        let digitsOnly = rawValue.filter { $0.isNumber }
        if digitsOnly != rawValue {
            spoolmanIdInput = digitsOnly
        }
        spoolmanId = Int(digitsOnly)
    }
    
    private func deriveSubtype(from name: String) -> String {
        let lowercaseName = name.lowercased()
        
        let subtypeMappings: [(keywords: [String], subtype: String)] = [
            (["matte"], "Matte"),
            (["silk"], "Silk"),
            (["glossy", "gloss"], "Glossy"),
            (["translucent", "translucentpetg"], "Translucent"),
            (["transparent", "clear"], "Transparent"),
            (["glitter"], "Glitter"),
            (["glow"], "Glow"),
            (["carbon", "cf", "cf15", "cf10"], "Carbon Fiber"),
            (["wood"], "Wood"),
            (["support", "pva"], "Support"),
            (["basic"], "Basic"),
            (["hf", "high speed", "hs", "hyperspeed"], "HF"),
            (["rapid"], "Rapid"),
            (["tpu", "flex", "flexible", "soft"], "Flexible"),
            (["semi flexible", "semi-flexible", "fpe"], "Semi Flexible")
        ]
        
        for mapping in subtypeMappings {
            for keyword in mapping.keywords {
                if lowercaseName.contains(keyword) {
                    return mapping.subtype
                }
            }
        }
        
        return "Basic"
    }
    
    private func buildTagData() -> FilamentTagData {
        let resolvedName: String = if visibleFieldIDs.contains("name") {
            name
        } else {
            ""
        }

        let resolvedSubtype: String = if visibleFieldIDs.contains("subtype") {
            SubtypeOptionService.resolve(userInput: subtype)
        } else {
            ""
        }

        let resolvedSpoolmanID: Int? = if visibleFieldIDs.contains("spool_id") {
            spoolmanId
        } else {
            nil
        }

        var data = WriteTagFormAssembler.buildTagData(
            format: selectedFormatOverride,
            name: resolvedName,
            material: material,
            subtype: resolvedSubtype,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            spoolmanId: resolvedSpoolmanID,
            writeSpoolID: writeSpoolId
        )

        if selectedFormatOverride == .openPrintTag {
            data.density = visibleFieldIDs.contains("density") ? parseOptionalDouble(densityInput) : nil
            data.openPrintTagMaterialTypeID = AppConfig.openPrintTagMaterialTypeID(for: material)
            data.transmissionDistance = visibleFieldIDs.contains("transmission_distance") ? parseOptionalDouble(transmissionDistanceInput) : nil
            data.gtin = visibleFieldIDs.contains("gtin") ? parseOptionalString(gtinInput) : nil
            data.manufacturedDateUnix = visibleFieldIDs.contains("manufactured_date") && includeManufacturedDate
                ? WriteTagFormAssembler.unixSeconds(from: manufacturedDate)
                : nil
            data.countryOfOrigin = visibleFieldIDs.contains("country_of_origin") ? parseOptionalString(countryOfOriginInput)?.uppercased() : nil
            data.preheatTemp = visibleFieldIDs.contains("preheat_temperature") ? parseOptionalInt(preheatTempInput) : nil
            data.dryingTemp = visibleFieldIDs.contains("drying_temperature") ? parseOptionalInt(dryingTempInput) : nil
            data.dryingTime = visibleFieldIDs.contains("drying_time") ? parseOptionalInt(dryingTimeInput) : nil
            data.nominalNetWeight = visibleFieldIDs.contains("nominal_netto_full_weight") ? parseOptionalDouble(nominalWeightInput) : nil
            data.actualNetWeight = visibleFieldIDs.contains("actual_netto_full_weight") ? parseOptionalDouble(actualWeightInput) : nil
            data.emptyContainerWeight = visibleFieldIDs.contains("empty_container_weight") ? parseOptionalDouble(emptyContainerWeightInput) : nil
            data.materialTags = visibleFieldIDs.contains("material_tags")
                ? (selectedMaterialTagIDs.isEmpty ? nil : Array(selectedMaterialTagIDs).sorted().prefix(16).map { $0 })
                : nil
            data.certifications = visibleFieldIDs.contains("certifications")
                ? (selectedCertificationIDs.isEmpty ? nil : Array(selectedCertificationIDs).sorted())
                : nil
            data.tagURL = visibleFieldIDs.contains("tag_url") ? parseOptionalURLString(tagURLInput) : nil
        }

        return data
    }

    private func parseOptionalString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseOptionalInt(_ value: String) -> Int? {
        guard let trimmed = parseOptionalString(value) else { return nil }
        return Int(trimmed)
    }

    private func parseOptionalDouble(_ value: String) -> Double? {
        guard let trimmed = parseOptionalString(value) else { return nil }
        return Double(trimmed)
    }

    private func parseOptionalURLString(_ value: String) -> String? {
        guard let trimmed = parseOptionalString(value) else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return trimmed
    }

    private func writeTag() {
        var data = buildTagData()
        
        // Validate data before attempting write
        if let error = data.validate() {
            nfcManager.alertMessage = error.localizedDescription
            return
        }
        
        // Snapmaker U1 compat only applies to OpenSpool format
        if isU1CompatActive {
            if let resolved = AppConfig.resolveSnapmakerU1Material(data.material) {
                data.material = resolved
            } else {
                incompatibleMaterial = data.material
                pendingTagData = data
                showCompatPicker = true
                return
            }
        }
        
        nfcManager.writeTag(data: data, format: selectedFormatOverride)
    }
    
    private func triggerWriteSuccess() {
        // Haptic: success notification
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Animate banner in with spring
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showSuccessBanner = true
            successBannerScale = 1.0
        }
        
        // Spool color swatch pulse
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.15)) {
            colorSwatchScale = 1.25
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.35)) {
            colorSwatchScale = 1.0
        }
        
        // Auto-dismiss after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeIn(duration: 0.25)) {
                showSuccessBanner = false
                successBannerScale = 0.85
            }
        }
    }
    
    private func bounceColorSwatch() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
            colorSwatchScale = 1.3
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.18)) {
            colorSwatchScale = 1.0
        }
    }
}
