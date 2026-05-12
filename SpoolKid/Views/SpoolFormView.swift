//
//  SpoolFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Spool in Spoolman.
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

    @State private var showCompatPicker = false
    @State private var incompatibleMaterial = ""
    @State private var pendingTagData: FilamentTagData? = nil

    @State private var filamentId: Int?
    @State private var price: String = ""
    @State private var initialWeight: String = "1000"
    @State private var spoolWeight: String = ""
    @State private var location: String = ""
    @State private var clearLocationWhenEmpty: Bool = true
    @State private var comment: String = ""
    @State private var archived: Bool = false
    @State private var firstUsedISO8601: String = ""
    @State private var lastUsedISO8601: String = ""
    @State private var extraJSON: String = ""

    @State private var isSaved: Bool = false
    @State private var isSaving: Bool = false
    @State private var savedSpool: SpoolmanSpool? = nil
    @State private var hasInitialized = false
    @State private var validationError: String? = nil
    @State private var saveErrorMessage: String?

    @State private var uidSlot1: String = ""
    @State private var uidSlot2: String = ""
    @State private var scanningSlot: Int? = nil

    enum WeightMode: String, CaseIterable {
        case remaining = "Remaining"
        case used = "Used"
        case measured = "Measured"
    }

    @State private var weightMode: WeightMode = .remaining
    @State private var weightInput: String = ""

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func visibleFieldIDs(store: SpoolmanFieldVisibilityStore = .init()) -> Set<String> {
        store.visibleFieldIDs(for: .spool)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func locationPatch(for location: String, clearLocationWhenEmpty: Bool) -> SpoolmanPatchValue<String> {
        let normalizedLocation = normalized(location)
        if normalizedLocation.isEmpty {
            return clearLocationWhenEmpty ? .setNil : .ignore
        }
        return .set(normalizedLocation)
    }

    static func spoolPayload(
        filamentId: Int?,
        price: String,
        initialWeight: String,
        spoolWeight: String,
        remainingWeight: String,
        usedWeight: String,
        location: String,
        clearLocationWhenEmpty: Bool,
        lotNr: String,
        comment: String,
        archived: Bool,
        firstUsedISO8601: String,
        lastUsedISO8601: String,
        extraJSON: String
    ) -> [String: Any] {
        func parseDouble(_ value: String) -> Double? {
            let normalizedValue = normalized(value).replacingOccurrences(of: ",", with: ".")
            guard !normalizedValue.isEmpty else { return nil }
            return Double(normalizedValue)
        }

        let normalizedExtraJSON = normalized(extraJSON)
        let extra: [String: String]? = if normalizedExtraJSON.isEmpty {
            nil
        } else {
            (try? JSONSerialization.jsonObject(with: Data(normalizedExtraJSON.utf8))) as? [String: String]
        }

        return SpoolmanPayloadBuilder.spoolPayload(
            filamentId: filamentId,
            firstUsed: normalized(firstUsedISO8601).isEmpty ? nil : normalized(firstUsedISO8601),
            lastUsed: normalized(lastUsedISO8601).isEmpty ? nil : normalized(lastUsedISO8601),
            price: parseDouble(price),
            initialWeight: parseDouble(initialWeight),
            spoolWeight: parseDouble(spoolWeight),
            remainingWeight: parseDouble(remainingWeight),
            usedWeight: parseDouble(usedWeight),
            location: locationPatch(for: location, clearLocationWhenEmpty: clearLocationWhenEmpty),
            lotNr: normalized(lotNr).isEmpty ? nil : normalized(lotNr),
            comment: normalized(comment).isEmpty ? nil : normalized(comment),
            archived: archived,
            extra: extra
        )
    }

    static func clearFieldKeysForUpdate(
        comment: String,
        firstUsedISO8601: String,
        lastUsedISO8601: String,
        extraJSON: String,
        lotNr: String
    ) -> Set<String> {
        var keys: Set<String> = []

        if normalized(comment).isEmpty {
            keys.insert("comment")
        }

        if normalized(firstUsedISO8601).isEmpty {
            keys.insert("first_used")
        }

        if normalized(lastUsedISO8601).isEmpty {
            keys.insert("last_used")
        }

        if normalized(extraJSON).isEmpty {
            keys.insert("extra")
        }

        if normalized(lotNr).isEmpty {
            keys.insert("lot_nr")
        }

        return keys
    }

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
    private var locationSection: some View {
        Section("Location") {
            Picker("Location", selection: $location) {
                Text("None").tag("")
                ForEach(service.locations, id: \.self) { item in
                    Text(item).tag(item)
                }
            }

            Toggle("Clear location when empty", isOn: $clearLocationWhenEmpty)
        }
    }

    @ViewBuilder
    private func advancedSection(visibleFieldIDs: Set<String>) -> some View {
        Section("Advanced") {
            if visibleFieldIDs.contains("comment") {
                TextField("Comment", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
            }

            if visibleFieldIDs.contains("archived") {
                Toggle("Archived", isOn: $archived)
            }

            if visibleFieldIDs.contains("first_used") {
                TextField("First Used (ISO8601)", text: $firstUsedISO8601)
                    .textInputAutocapitalization(.never)
            }

            if visibleFieldIDs.contains("last_used") {
                TextField("Last Used (ISO8601)", text: $lastUsedISO8601)
                    .textInputAutocapitalization(.never)
            }

            if visibleFieldIDs.contains("extra") {
                TextField("Extra JSON", text: $extraJSON, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
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
        let visibleFieldIDs = Self.visibleFieldIDs()

        Form {
            filamentSection
                propertiesSection
                weightStatusSection

                if visibleFieldIDs.contains("location") {
                    locationSection
                }

                if visibleFieldIDs.contains("comment")
                    || visibleFieldIDs.contains("archived")
                    || visibleFieldIDs.contains("first_used")
                    || visibleFieldIDs.contains("last_used")
                    || visibleFieldIDs.contains("extra") {
                    advancedSection(visibleFieldIDs: visibleFieldIDs)
                }

                tagUIDSection
                actionSections
            }
            .hideKeyboardOnTap()
            .navigationTitle(spoolToEdit == nil ? "Add Spool" : "Edit Spool")
            .onChange(of: nfcManager.isScanning) { _, isScanning in
                if persistCardUID, !isScanning, let result = nfcManager.scanResult, let slot = scanningSlot {
                    let uid = result.cardUID ?? ""
                    if !uid.isEmpty {
                        if slot == 1 {
                            uidSlot1 = uid
                        } else {
                            uidSlot2 = uid
                        }
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
            .alert(
                "Could Not Save Spool",
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
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaved ? "Saved" : "Save") {
                        saveSpool(writeAfter: false)
                    }
                    .disabled(filamentId == nil || isSaved || isSaving)
                }
            }
            .onAppear {
                if !hasInitialized {
                    hasInitialized = true
                    Task {
                        await service.fetchFilaments(baseUrl: baseUrl)
                        await service.fetchLocations(baseUrl: baseUrl)
                    }

                    if let spool = spoolToEdit {
                        filamentId = spool.filament.id
                        if let p = spool.price { price = String(p) }
                        if let iw = spool.initialWeight { initialWeight = String(iw) }
                        if let sw = spool.spoolWeight { spoolWeight = String(sw) }

                        if let rw = spool.remainingWeight {
                            weightMode = .remaining
                            weightInput = String(rw)
                        }

                        location = spool.location ?? ""
                        comment = spool.comment ?? ""
                        archived = spool.archived ?? false
                        firstUsedISO8601 = spool.firstUsed.map { Self.dateFormatter.string(from: $0) } ?? ""
                        lastUsedISO8601 = spool.lastUsed.map { Self.dateFormatter.string(from: $0) } ?? ""

                        if let extra = spool.extra,
                           let data = try? JSONSerialization.data(withJSONObject: extra, options: [.sortedKeys]),
                           let string = String(data: data, encoding: .utf8) {
                            extraJSON = string
                        } else {
                            extraJSON = ""
                        }

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
                    if data.name == nil {
                        data.name = savedSpool?.filament.name
                    }
                    recentTagManager.addTag(data)
                }
            }
    }

    private func writeTag(for spool: SpoolmanSpool) {
        var data = FilamentTagData.from(spool: spool, writeSpoolId: configWriteSpoolId)
        let currentFormat = TagFormat(rawValue: nfcTagFormat) ?? .openSpool
        let isU1CompatActive = snapmakerU1Compat && currentFormat == .openSpool

        if isU1CompatActive {
            data.name = nil
        } else if currentFormat == .openSpool {
            data.subtype = nil
        }

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
            if isSaving {
                return
            }
            isSaving = true
            defer { isSaving = false }

            func parseDouble(_ str: String) -> Double? {
                let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                return Double(cleaned)
            }

            let p = parseDouble(price)
            let initW = parseDouble(initialWeight)
            let spoolW = parseDouble(spoolWeight)
            let wInput = parseDouble(weightInput)

            if let p, p < 0 {
                validationError = "Price cannot be negative."
                return
            }
            if let initW, initW < 0 {
                validationError = "Initial weight cannot be negative."
                return
            }
            if let spoolW, spoolW < 0 {
                validationError = "Empty spool weight cannot be negative."
                return
            }
            if let wInput, wInput < 0 {
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
                        if let remW, remW < 0 {
                            validationError = "Measured weight cannot be lower than empty spool weight."
                            return
                        }
                    } else {
                        remW = val
                    }
                }
            }

            let payload = Self.spoolPayload(
                filamentId: filamentId,
                price: price,
                initialWeight: initialWeight,
                spoolWeight: spoolWeight,
                remainingWeight: remW.map { String($0) } ?? "",
                usedWeight: usedW.map { String($0) } ?? "",
                location: location,
                clearLocationWhenEmpty: clearLocationWhenEmpty,
                lotNr: lotNrForCurrentSave() ?? "",
                comment: comment,
                archived: archived,
                firstUsedISO8601: firstUsedISO8601,
                lastUsedISO8601: lastUsedISO8601,
                extraJSON: extraJSON
            )

            let locationPatchForAdd: SpoolmanPatchValue<String> = {
                let normalizedLocation = Self.normalized(location)
                if normalizedLocation.isEmpty {
                    return .ignore
                }
                return .set(normalizedLocation)
            }()

            let locationPatchForUpdate = Self.locationPatch(for: location, clearLocationWhenEmpty: clearLocationWhenEmpty)
            let clearFieldKeys = Self.clearFieldKeysForUpdate(
                comment: comment,
                firstUsedISO8601: firstUsedISO8601,
                lastUsedISO8601: lastUsedISO8601,
                extraJSON: extraJSON,
                lotNr: lotNrForCurrentSave() ?? ""
            )

            if let spool = spoolToEdit {
                let didSave = await service.updateSpool(
                    id: spool.id,
                    filamentId: filamentId,
                    remainingWeight: payload["remaining_weight"] as? Double,
                    initialWeight: payload["initial_weight"] as? Double,
                    spoolWeight: payload["spool_weight"] as? Double,
                    usedWeight: payload["used_weight"] as? Double,
                    price: payload["price"] as? Double,
                    location: locationPatchForUpdate,
                    lotNr: payload["lot_nr"] as? String,
                    comment: payload["comment"] as? String,
                    archived: payload["archived"] as? Bool,
                    firstUsed: payload["first_used"] as? String,
                    lastUsed: payload["last_used"] as? String,
                    extra: payload["extra"] as? [String: String],
                    clearFieldKeys: clearFieldKeys,
                    baseUrl: baseUrl
                )

                if didSave {
                    if rememberSpoolData {
                        lastSpoolPrice = price
                        lastSpoolInitialWeight = initialWeight
                        lastSpoolEmptyWeight = spoolWeight
                        if let fId = filamentId {
                            lastSpoolFilamentId = fId
                        }
                    }

                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSaved = true
                    dismiss()
                } else {
                    saveErrorMessage = service.errorMessage ?? "The spool could not be saved."
                }
            } else if let fId = filamentId {
                let newSpool = await service.addSpool(
                    filamentId: fId,
                    remainingWeight: payload["remaining_weight"] as? Double,
                    initialWeight: payload["initial_weight"] as? Double,
                    spoolWeight: payload["spool_weight"] as? Double,
                    usedWeight: payload["used_weight"] as? Double,
                    price: payload["price"] as? Double,
                    location: locationPatchForAdd,
                    lotNr: payload["lot_nr"] as? String,
                    comment: payload["comment"] as? String,
                    archived: payload["archived"] as? Bool,
                    firstUsed: payload["first_used"] as? String,
                    lastUsed: payload["last_used"] as? String,
                    extra: payload["extra"] as? [String: String],
                    baseUrl: baseUrl
                )

                if let spool = newSpool {
                    if rememberSpoolData {
                        lastSpoolPrice = price
                        lastSpoolInitialWeight = initialWeight
                        lastSpoolEmptyWeight = spoolWeight
                        lastSpoolFilamentId = fId
                    }

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
                } else {
                    saveErrorMessage = service.errorMessage ?? "The spool could not be saved."
                }
            }
        }
    }

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
