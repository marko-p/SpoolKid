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
    
    @State private var selectedSpoolId: Int?
    
    // Delight state
    @State private var showSuccessBanner = false
    @State private var successBannerScale: CGFloat = 0.85
    @State private var colorSwatchScale: CGFloat = 1.0
    
    // Snapmaker U1 compatibility state
    @State private var showCompatPicker = false
    @State private var incompatibleMaterial = ""
    @State private var pendingTagData: FilamentTagData? = nil
    
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
                
                // Filament Name — hidden when U1 compat is active (replaced by Variant)
                if visibleFieldIDs.contains("name") && !isU1CompatActive {
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
            isU1CompatActive ? "" : name
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

        return WriteTagFormAssembler.buildTagData(
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
