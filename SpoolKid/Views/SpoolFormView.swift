//
//  SpoolFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Spool in Spoolman.
//  Features:
//  - Filament selection (via `FilamentSelectionView`).
//  - Weight management (Initial, Empty, Remaining/Used).
//  - "Measured Weight" mode: Calculates remaining filament by subtracting empty spool weight from total measured weight.
//  - Tag UID slot management (lot_nr): scan or clear up to two tag UIDs per spool.
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
    var initialFilamentId: Int? = nil
    var initialLotNr: String? = nil
    var onSaveSpool: ((SpoolmanSpool) -> Void)? = nil

    @AppStorage("remember_spool_data") private var rememberSpoolData = false
    @AppStorage("last_spool_price") private var lastSpoolPrice: String = ""
    @AppStorage("last_spool_initial_weight") private var lastSpoolInitialWeight: String = "1000"
    @AppStorage("last_spool_empty_weight") private var lastSpoolEmptyWeight: String = "0"
    @AppStorage("last_spool_filament_id") private var lastSpoolFilamentId: Int = -1
    @AppStorage("write_spool_id") private var configWriteSpoolId: Bool = true
    @AppStorage("snapmaker_u1_compat") private var snapmakerU1Compat: Bool = false
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.spoolmanPersistCardUIDKey) private var persistCardUID: Bool = false

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

    // Tag UID slots (lot_nr)
    @State private var uidSlot1: String = ""
    @State private var uidSlot2: String = ""
    @State private var scanningSlot: Int? = nil   // 1 or 2 while scanning for a slot

    enum WeightMode: String, CaseIterable {
        case remaining = "Remaining"
        case used = "Used"
        case measured = "Measured"
    }

    @State private var weightMode: WeightMode = .remaining
    @State private var weightInput: String = ""

    // MARK: - Form sections

    @ViewBuilder
    private var filamentSection: some View {
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
                                Text(vendor.name).font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                    } else {
                        Text("Select Filament").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var propertiesSection: some View {
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
    }

    @ViewBuilder
    private var weightStatusSection: some View {
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
    }

    @ViewBuilder
    private var tagUIDSection: some View {
        Section {
            uidSlotRow(slot: 1, uid: $uidSlot1)
            uidSlotRow(slot: 2, uid: $uidSlot2)
        } header: {
            Text("Tag UID Slots")
        } footer: {
            if persistCardUID {
                Text("Scan each physical tag to link it to this spool. Used for automatic identification on next scan.")
            } else {
                Text("Disabled because \"Save Tag ID to Spoolman Lot nr.\" is turned off in Settings.")
            }
        }
        .disabled(!persistCardUID)
        .opacity(persistCardUID ? 1.0 : 0.55)
    }

    @ViewBuilder
    private var actionSections: some View {
        if Self.shouldShowSaveAndWriteButton(
            isEditingExistingSpool: spoolToEdit != nil,
            isSaved: isSaved
        ) {
            Section {
                Button(action: { saveSpool(writeAfter: true) }) {
                    Label("Save and Write NFC Tag", systemImage: "wave.3.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .writeTagButtonStyle()
                .disabled(filamentId == nil)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        if let spool = savedSpool, writeToNfc {
            Section {
                Button(action: { writeTag(for: spool) }) {
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

    var body: some View {
        NavigationStack {
            Form {
                filamentSection
                propertiesSection
                weightStatusSection
                tagUIDSection
                actionSections
            }
            .hideKeyboardOnTap()
            .navigationTitle(spoolToEdit == nil ? "Add Spool" : "Edit Spool")
            .onChange(of: nfcManager.isScanning) { _, isScanning in
                // Removed auto-dismiss logic to allow retrying.
                // Capture slot scan result when scanning completes.
                if persistCardUID, !isScanning, let result = nfcManager.scanResult, let slot = scanningSlot {
                    let uid = result.cardUID ?? ""
                    if !uid.isEmpty {
                        if slot == 1 { uidSlot1 = uid } else { uidSlot2 = uid }
                    }
                    scanningSlot = nil
                    nfcManager.scanResult = nil
                }
            }
            .onChange(of: persistCardUID) { _, isEnabled in
                if !isEnabled {
                    scanningSlot = nil
                }
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

                        // Populate UID slots from lot_nr
                        let slots = SpoolMappingService.cardUIDs(in: spool.lotNr)
                        uidSlot1 = slots.indices.contains(0) ? slots[0] : ""
                        uidSlot2 = slots.indices.contains(1) ? slots[1] : ""
                    } else if rememberSpoolData {
                        if let initialFilamentId {
                            filamentId = initialFilamentId
                        }
                        if let initialLotNr {
                            let slots = SpoolMappingService.cardUIDs(in: initialLotNr)
                            uidSlot1 = slots.indices.contains(0) ? slots[0] : ""
                            uidSlot2 = slots.indices.contains(1) ? slots[1] : ""
                        }
                        if !lastSpoolPrice.isEmpty { price = lastSpoolPrice }
                        if !lastSpoolInitialWeight.isEmpty { initialWeight = lastSpoolInitialWeight }
                        if !lastSpoolEmptyWeight.isEmpty { spoolWeight = lastSpoolEmptyWeight }
                        if filamentId == nil, lastSpoolFilamentId != -1 { filamentId = lastSpoolFilamentId }
                    } else {
                        if let initialFilamentId {
                            filamentId = initialFilamentId
                        }
                        if let initialLotNr {
                            let slots = SpoolMappingService.cardUIDs(in: initialLotNr)
                            uidSlot1 = slots.indices.contains(0) ? slots[0] : ""
                            uidSlot2 = slots.indices.contains(1) ? slots[1] : ""
                        }
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

    // MARK: - NFC write

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

    // MARK: - Save

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
                    lotNr: lotNrForCurrentSave(),
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
                        lotNr: lotNrForCurrentSave(),
                        baseUrl: baseUrl
                    )

                    if let spool = newSpool {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        isSaved = true
                        savedSpool = spool
                        onSaveSpool?(spool)
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

    // MARK: - Tag UID helpers

    private func lotNrForCurrentSave() -> String? {
        Self.lotNrForSave(
            persistCardUID: persistCardUID,
            existingLotNr: spoolToEdit?.lotNr,
            slot1: uidSlot1,
            slot2: uidSlot2
        )
    }

    static func lotNrForSave(
        persistCardUID: Bool,
        existingLotNr: String?,
        slot1: String,
        slot2: String
    ) -> String? {
        guard persistCardUID else { return existingLotNr }

        let s1 = slot1.trimmingCharacters(in: .whitespaces)
        let s2 = slot2.trimmingCharacters(in: .whitespaces)
        var uids: [String] = []
        if !s1.isEmpty { uids.append(s1) }
        if !s2.isEmpty { uids.append(s2) }
        guard !uids.isEmpty else { return nil }
        return SpoolMappingService.lotNumber(for: uids)
    }

    static func shouldShowSaveAndWriteButton(
        isEditingExistingSpool: Bool,
        isSaved: Bool
    ) -> Bool {
        !isEditingExistingSpool && !isSaved
    }

    @ViewBuilder
    private func uidSlotRow(slot: Int, uid: Binding<String>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slot)")
                    .font(.subheadline)
                if uid.wrappedValue.isEmpty {
                    Text("Not assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(uid.wrappedValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !uid.wrappedValue.isEmpty {
                Button(role: .destructive) {
                    uid.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                scanningSlot = slot
                nfcManager.startScanning()
            } label: {
                Image(systemName: scanningSlot == slot ? "antenna.radiowaves.left.and.right" : "wave.3.right")
                    .foregroundStyle(scanningSlot == slot ? .orange : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(nfcManager.isScanning)
        }
    }
}
