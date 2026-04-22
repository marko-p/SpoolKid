//
//  SpoolFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Spool in Spoolman.
//  Features:
//  - Filament selection (via `FilamentSelectionView`).
//  - Weight management (Initial, Empty, Remaining/Used).
//  - "Measured Weight" mode: Calculates remaining filament by subtracting empty spool weight from total measured weight.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolmanService
    let baseUrl: String
    var spoolToEdit: SpoolmanSpool?
    
    @AppStorage("remember_spool_data") private var rememberSpoolData = false
    @AppStorage("last_spool_price") private var lastSpoolPrice: String = ""
    @AppStorage("last_spool_initial_weight") private var lastSpoolInitialWeight: String = "1000"
    @AppStorage("last_spool_empty_weight") private var lastSpoolEmptyWeight: String = "0"
    @AppStorage("last_spool_filament_id") private var lastSpoolFilamentId: Int = -1
    @AppStorage("write_spool_id") private var configWriteSpoolId: Bool = true
    @AppStorage("snapmaker_u1_compat") private var snapmakerU1Compat: Bool = false
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue

    @StateObject private var nfcManager = NFCManager()
    @StateObject private var recentTagManager = RecentTagManager()
    @State private var writeToNfc = false
    
    // Snapmaker U1 compatibility state
    @State private var showCompatPicker = false
    @State private var incompatibleMaterial = ""
    @State private var pendingTagData: FilamentTagData? = nil

    @State private var filamentId: Int?
    @State private var price: String = ""
    @State private var initialWeight: String = "1000"
    @State private var spoolWeight: String = ""
    @State private var isSaved: Bool = false
    @State private var savedSpool: SpoolmanSpool? = nil
    @State private var hasInitialized = false
    @State private var validationError: String? = nil
    
    enum WeightMode: String, CaseIterable {
        case remaining = "Remaining"
        case used = "Used"
        case measured = "Measured"
    }
    
    @State private var weightMode: WeightMode = .remaining
    @State private var weightInput: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Filament") {
                    NavigationLink {
                        FilamentSelectionView(selectedFilamentID: $filamentId, baseUrl: baseUrl, spoolManService: service)
                    } label: {
                        HStack {
                            Text("Filament")
                            Spacer()
                            if let id = filamentId, let filament = service.filaments.first(where: { $0.id == id }) {
                                VStack(alignment: .trailing) {
                                    Text(filament.name ?? "Unknown")
                                    if let vendor = filament.vendor {
                                        Text(vendor.name)
                                            .font(.caption)
                                    }
                                }
                                .foregroundColor(.secondary)
                            } else {
                                Text("Select Filament")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("Properties") {
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Initial Weight (g)")
                        Spacer()
                        TextField("1000", text: $initialWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Empty Spool Weight (g)")
                        Spacer()
                        TextField("0", text: $spoolWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
                
                Section("Weight Status") {
                    Picker("Input Mode", selection: $weightMode) {
                        ForEach(WeightMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    HStack {
                        Text("\(weightMode.rawValue) Weight (g)")
                        Spacer()
                        TextField("0", text: $weightInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    if weightMode == .measured {
                        let wInputVal = weightInput.replacingOccurrences(of: ",", with: ".")
                        let spoolWVal = spoolWeight.replacingOccurrences(of: ",", with: ".")
                        
                        if let measured = Double(wInputVal), let empty = Double(spoolWVal) {
                            HStack {
                                Text("Calculated Remaining:")
                                Spacer()
                                Text(String(format: "%.1f g", measured - empty))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if spoolToEdit == nil {
                    Section {
                        Button(action: {
                            saveSpool(writeAfter: true)
                        }) {
                            Label("Save and Write NFC Tag", systemImage: "wave.3.right")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                        .writeTagButtonStyle()
                        .disabled(filamentId == nil || isSaved)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                
                if let spool = savedSpool, writeToNfc {
                    Section {
                        Button(action: {
                            writeTag(for: spool)
                        }) {
                            Label("Write to NFC Tag", systemImage: "wave.3.right")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                        .writeTagButtonStyle()
                        .disabled(nfcManager.isScanning)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .hideKeyboardOnTap()
            .navigationTitle(spoolToEdit == nil ? "Add Spool" : "Edit Spool")
            .onChange(of: nfcManager.isScanning) { _, _ in
                // Removed auto-dismiss logic to allow retrying
            }
            .alert(isPresented: Binding<Bool>(
                get: { !nfcManager.alertMessage.isEmpty },
                set: { _ in nfcManager.alertMessage = "" }
            )) {
                Alert(title: Text("NFC Error"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
            }
            .alert("Invalid Input", isPresented: Binding<Bool>(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } }
            )) {
                Button("OK", role: .cancel) { validationError = nil }
            } message: {
                if let msg = validationError { Text(msg) }
            }
            .sheet(isPresented: $showCompatPicker) {
                SnapmakerCompatPickerView(
                    incompatibleMaterial: incompatibleMaterial,
                    compatibleMaterials: AppConfig.snapmakerU1Materials,
                    onSelect: { selectedMaterial in
                        if var data = pendingTagData {
                            data.material = selectedMaterial
                            nfcManager.writeTag(data: data)
                        }
                        showCompatPicker = false
                    },
                    onCancel: {
                        pendingTagData = nil
                        showCompatPicker = false
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaved ? "Saved" : "Save") {
                        saveSpool(writeAfter: false)
                    }
                    .disabled(filamentId == nil || isSaved)
                }
            }
            .onAppear {
                if !hasInitialized {
                    hasInitialized = true
                    Task { await service.fetchFilaments(baseUrl: baseUrl) }
                    
                    if let spool = spoolToEdit {
                        filamentId = spool.filament.id
                        if let p = spool.price { price = String(p) }
                        if let iw = spool.initialWeight { initialWeight = String(iw) }
                        if let sw = spool.spoolWeight { spoolWeight = String(sw) }
                        
                        // Default to remaining weight for edit
                        if let rw = spool.remainingWeight {
                            weightMode = .remaining
                            weightInput = String(rw)
                        }
                    } else if rememberSpoolData {
                        if !lastSpoolPrice.isEmpty { price = lastSpoolPrice }
                        if !lastSpoolInitialWeight.isEmpty { initialWeight = lastSpoolInitialWeight }
                        if !lastSpoolEmptyWeight.isEmpty { spoolWeight = lastSpoolEmptyWeight }
                        if lastSpoolFilamentId != -1 { filamentId = lastSpoolFilamentId }
                    }
                }
            }
            .onChange(of: nfcManager.lastWriteSucceeded) { _, succeeded in
                if succeeded, var data = nfcManager.tagDataToWrite {
                    // Restore name for Recent Tags display (may have been stripped for NFC format)
                    if data.name == nil {
                        data.name = savedSpool?.filament.name
                    }
                    recentTagManager.addTag(data)
                }
            }
        }
    }
    
    private func writeTag(for spool: SpoolmanSpool) {
        var data = FilamentTagData.from(spool: spool, writeSpoolId: configWriteSpoolId)
        let currentFormat = TagFormat(rawValue: nfcTagFormat) ?? .openSpool
        let isU1CompatActive = snapmakerU1Compat && currentFormat == .openSpool
        
        // Adjust name/subtype based on format and compat mode
        if isU1CompatActive {
            data.name = nil // U1 compat: keep subtype (derived from spool), omit name
        } else if currentFormat == .openSpool {
            data.subtype = nil // Non-U1 OpenSpool: keep name, omit subtype
        }
        // Other formats: keep both name and subtype as-is
        
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
        
        nfcManager.writeTag(data: data)
    }
    
    private func saveSpool(writeAfter: Bool) {
        Task {
            // Helper to parse doubles with comma or dot
            func parseDouble(_ str: String) -> Double? {
                let cleaned = str.replacingOccurrences(of: ",", with: ".")
                return Double(cleaned)
            }
            
            let p = parseDouble(price)
            let initW = parseDouble(initialWeight)
            let spoolW = parseDouble(spoolWeight)
            let wInput = parseDouble(weightInput)
            
            // Validate: reject negative values
            if let p = p, p < 0 {
                validationError = "Price cannot be negative."
                return
            }
            if let initW = initW, initW < 0 {
                validationError = "Initial weight cannot be negative."
                return
            }
            if let spoolW = spoolW, spoolW < 0 {
                validationError = "Empty spool weight cannot be negative."
                return
            }
            if let wInput = wInput, wInput < 0 {
                validationError = "\(weightMode.rawValue) weight cannot be negative."
                return
            }
            
            var remW: Double? = nil
            var usedW: Double? = nil
            
            if let val = wInput {
                switch weightMode {
                case .remaining:
                    remW = val
                case .used:
                    usedW = val
                case .measured:
                    if let sW = spoolW {
                        remW = val - sW
                    } else {
                        // Fallback if no spool weight, assume measured is remaining (unlikely but safe)
                        remW = val
                    }
                }
            }
            
            if rememberSpoolData {
                lastSpoolPrice = price
                lastSpoolInitialWeight = initialWeight
                lastSpoolEmptyWeight = spoolWeight
                if let fId = filamentId {
                    lastSpoolFilamentId = fId
                }
            }

            if let spool = spoolToEdit {
                await service.updateSpool(
                    id: spool.id,
                    filamentId: filamentId,
                    remainingWeight: remW,
                    initialWeight: initW,
                    spoolWeight: spoolW,
                    usedWeight: usedW,
                    price: p,
                    baseUrl: baseUrl
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isSaved = true
                dismiss()
            } else {
                if let fId = filamentId {
                    let newSpool = await service.addSpool(
                        filamentId: fId,
                        remainingWeight: remW,
                        initialWeight: initW,
                        spoolWeight: spoolW,
                        usedWeight: usedW,
                        price: p,
                        baseUrl: baseUrl
                    )
                    
                    if let spool = newSpool {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        isSaved = true
                        savedSpool = spool
                        writeToNfc = writeAfter
                        
                        if writeAfter {
                            writeTag(for: spool)
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
