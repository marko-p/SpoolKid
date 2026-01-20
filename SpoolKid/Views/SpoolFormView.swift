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

import SwiftUI

struct SpoolFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolManService
    let baseUrl: String
    var spoolToEdit: SpoolManSpool?
    
    @AppStorage("remember_spool_data") private var rememberSpoolData = false
    @AppStorage("last_spool_price") private var lastSpoolPrice: String = ""
    @AppStorage("last_spool_initial_weight") private var lastSpoolInitialWeight: String = "1000"
    @AppStorage("last_spool_empty_weight") private var lastSpoolEmptyWeight: String = "0"
    @AppStorage("last_spool_filament_id") private var lastSpoolFilamentId: Int = -1
    @AppStorage("write_spool_id") private var configWriteSpoolId: Bool = true

    @StateObject private var nfcManager = NFCManager()
    @State private var writeToNfc = false
    @State private var isWritingNfcAndWaiting = false

    @State private var filamentId: Int?
    @State private var price: String = ""
    @State private var initialWeight: String = "1000"
    @State private var spoolWeight: String = ""
    @State private var isSaved: Bool = false
    @State private var savedSpool: SpoolManSpool? = nil
    @State private var hasInitialized = false
    
    enum WeightMode: String, CaseIterable {
        case remaining = "Remaining"
        case used = "Used"
        case measured = "Measured"
    }
    
    @State private var weightMode: WeightMode = .remaining
    @State private var weightInput: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Filament")) {
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
                
                Section(header: Text("Properties")) {
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
                
                Section(header: Text("Weight Status")) {
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
                            HStack {
                                Image(systemName: "wave.3.right")
                                Text("Save and write NFC")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(filamentId == nil || isSaved)
                    } footer: {
                        Text("Saves to SpoolMan and initiates NFC writing.")
                    }
                }
                
                if let spool = savedSpool, writeToNfc {
                    Section {
                        Button(action: {
                            writeTag(for: spool)
                        }) {
                            HStack {
                                Image(systemName: "wave.3.right")
                                Text("Write NFC Tag Again")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(nfcManager.isScanning)
                    }
                }
            }
            .navigationTitle(spoolToEdit == nil ? "Add Spool" : "Edit Spool")
            .onChange(of: nfcManager.isScanning) { isScanning in
                // Removed auto-dismiss logic to allow retrying
            }
            .alert(isPresented: Binding<Bool>(
                get: { !nfcManager.alertMessage.isEmpty },
                set: { _ in nfcManager.alertMessage = "" }
            )) {
                Alert(title: Text("NFC"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
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
                    if service.filaments.isEmpty {
                        Task { await service.fetchFilaments(baseUrl: baseUrl) }
                    }
                    
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
        }
    }
    
    private func writeTag(for spool: SpoolManSpool) {
        // Prepare data
        var minNozzle = 190
        var maxNozzle = 220
        if let t = spool.filament.settingsExtruderTemp {
            minNozzle = t
            maxNozzle = t + 10
        }
        
        var minBed = 50
        var maxBed = 60
        if let t = spool.filament.settingsBedTemp {
            minBed = t
            maxBed = t + 5
        }
        
        let data = FilamentTagData(
            name: spool.filament.name,
            material: spool.filament.material ?? "PLA",
            brand: spool.filament.vendor?.name ?? "Generic",
            colorHex: spool.filament.colorHex ?? "000000",
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: configWriteSpoolId ? spool.id : nil
        )
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
