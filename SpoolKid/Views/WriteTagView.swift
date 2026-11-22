//
//  WriteTagView.swift
//  SpoolKid
//
//  Purpose: The UI for creating and writing new NFC tags.
//  Features:
//  - Form to input filament details (Material, Color, Temps, etc.).
//  - Integration with `NFCManager` to trigger the write operation.
//  - Option to link the active backend's Spool ID (controlled by settings).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct WriteTagView: View {
    @EnvironmentObject private var supportPrompts: SupportPromptService
    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var printer: PrinterService
    @Environment(\.serverLink) private var serverLink

    @StateObject private var nfcManager = NFCManager()
    @StateObject private var recentTagManager = RecentTagManager()
    
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.recentTagsKeepFormatKey) private var recentTagsKeepFormat: Bool = true
    @State private var selectedFormatOverride: TagFormat = .openSpool
    private let nfcVisibilityStore = NFCFieldVisibilityStore()
    
    // Form Fields
    @State private var name: String = ""
    @State private var material: String = AppConfig.Defaults.material
    @State private var subtype: String = "Basic"
    @State private var brand: String = AppConfig.Defaults.brand
    @State private var showBrandPicker = false
    @State private var colors = FilamentColors(hexes: [AppConfig.Defaults.colorHex])
    @State private var minNozzleTemp: Int = AppConfig.Defaults.minNozzleTemp
    @State private var maxNozzleTemp: Int = AppConfig.Defaults.maxNozzleTemp
    @State private var minBedTemp: Int = AppConfig.Defaults.minBedTemp
    @State private var maxBedTemp: Int = AppConfig.Defaults.maxBedTemp
    @State private var spoolmanId: Int? = nil
    /// Set when `initialData`'s spool ID was cleared because it no longer
    /// names the spool the data was written for.
    @State private var clearedSpoolID: WriteTagFormAssembler.StaleSpoolID?
    /// What the user typed into an ACE tag's SKU field, or nil while they have
    /// not — the field then shows `defaultSKU`, which is also what is written.
    @State private var skuOverride: String? = nil

    /// TigerTag registry resolution (option C): the free-text field stays,
    /// a caption under it says what will be written, and the chevron opens
    /// the searchable registry instead of the free-text menu.
    @State private var registryPickerTarget: RegistryPickerTarget? = nil
    @State private var pickedMaterial: TigerTagRegistry.IDResolution? = nil
    @State private var pickedBrand: TigerTagRegistry.IDResolution? = nil

    /// The Canvas filament an ELEGOO tag will name on page 19. Kept apart from
    /// `material`/`subtype`, so switching formats never rewrites them, and
    /// suggested from them each time ELEGOO is selected.
    @State private var elegooEntry: ElegooCanvasCatalog.Entry? = nil

    private enum RegistryPickerTarget: String, Identifiable {
        case material, brand, canvasFilament
        var id: String { rawValue }
    }

    /// The registry caption under a TigerTag material/brand field. A fallback
    /// warns in orange; exact and aliased stay secondary text.
    @ViewBuilder
    private func tigerRegistryCaption(_ resolution: TigerTagRegistry.IDResolution, undefinedLabel: String) -> some View {
        let text = TigerTagRegistry.caption(for: resolution, undefinedLabel: undefinedLabel)
        Group {
            if resolution.kind == .fallback {
                Text(text).foregroundStyle(.orange)
            } else {
                Text(text).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
    @State private var spoolmanIdInput: String = ""

    // OpenPrintTag rich fields
    @State private var preheatTemp: Int = 0
    @State private var nominalWeight: Int = 0
    @State private var emptyWeight: Int = 0
    /// Grams left on the spool. Blank is a full spool.
    @State private var remainingWeight: Int?
    @State private var densityInput: String = ""
    @State private var diameterInput: String = ""
    @State private var dryingTemp: Int = 0
    @State private var dryingTime: Int = 0
    @State private var gtin: String = ""
    @State private var country: String = ""
    @State private var manufacturedDate: Date = Date()
    @State private var urlRecord: String = ""

    // Delight state
    @State private var showSuccessBanner = false
    @State private var successBannerScale: CGFloat = 0.85
    @State private var colorSwatchScale: CGFloat = 1.0
    @State private var showCustomizeFields = false
    /// Set when the tag was written but the spool mapping did not land cleanly.
    @State private var linkFailure: String?
    @State private var fieldVisibilityRefreshToken = 0
    
    var initialData: FilamentTagData?
    @AppStorage(AppConfig.writeOpacityToTagsKey) private var writesOpacity = true
    /// No rows of their own: they ride along from the data the form opened on.
    @State private var transmissionDistance: Double?
    @State private var carriedAlpha: Int?
    var scannedCardUID: String? = nil
    /// FilaMan's one-tag limit met this write; asked before it starts.
    @State private var replaceRequest: TagReplaceRequest?
    /// The person chose Replace Tag; the link after the write replaces.
    @State private var replacesOnWriteLink = false
    /// The format a Recent Tag was written in; nil from every other entry.
    var initialFormat: TagFormat? = nil
    /// Called with the UID of the tag each successful write landed on, so a
    /// screen that scanned a tag first can tell it was overwritten.
    var onTagWritten: ((String?) -> Void)? = nil
    /// Spec 4: set by a filament form's Write a New Tag. The tag written is
    /// linked to that filament when no spool was chosen.
    var linkFilamentId: Int? = nil
    /// The reader this screen opens on; set only by the toolhead sheet.
    var initialReader: TagReader = .iPhone

    /// Which reader Write Tag uses. Never stored.
    @State private var tagReader: TagReader = .iPhone
    /// The reader the write in flight, or the last write, ran on.
    @State private var run = TagReaderRun()
    /// What the form said when the last write started. The other-side offer
    /// shows only while the form still says it, so it cannot write stale data.
    @State private var writtenSignature: String?
    @State private var didApplyInitialReader = false

    private var visibleFieldDefinitions: [NFCFieldDefinition] {
        WriteTagFormAssembler.visibleFields(format: selectedFormatOverride, visibilityStore: nfcVisibilityStore)
    }

    private var visibleFieldIDs: Set<String> {
        Set(visibleFieldDefinitions.map(\.id))
    }

    /// Why a Prusa printer would not count this OpenPrintTag down, when the
    /// rows it needs are hidden or not stated.
    private var countdownNote: String? {
        guard selectedFormatOverride == .openPrintTag else { return nil }
        let blockers = WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: visibleFieldIDs, nominalWeight: nominalWeight,
            density: densityInput, diameter: diameterInput
        )
        guard !blockers.isEmpty else { return nil }
        return "The printer can't count down this spool without " + ListFormatter.localizedString(byJoining: blockers) + "."
    }

    private var capacityBreakdown: TagCapacityEstimator.Breakdown? {
        guard selectedFormatOverride == .openPrintTag else { return nil }
        // The URL the write will send (the row hidden sends none), so the
        // gauge never counts a record the tag will not get.
        let data = buildTagData()
        return TagCapacityEstimator.breakdown(
            for: data,
            format: .openPrintTag,
            urlString: data.tagURL)
    }

    private var availableMaterials: [String] {
        AppConfig.materials
    }
    
    var body: some View {
        let _ = fieldVisibilityRefreshToken
        Form {
            // First, so it is on screen when the form opens. Typing a new ID
            // retires it — it explains an empty field, not a filled one.
            if let clearedSpoolID, spoolmanId == nil {
                Section {
                    Label(clearedSpoolID.note, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section("Tag Format") {
                // `writable`, not `allCases`: a read-only format offered here
                // fails only once the user is already holding a tag against
                // the phone (ELEGOO did, until it gained an encoder).
                Picker("Format", selection: $selectedFormatOverride) {
                    ForEach(TagFormat.writable) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            }

            Section("Filament Details") {
                if selectedFormatOverride == .elegoo {
                    elegooFilamentRow
                }

                // Material Type
                if visibleFieldIDs.contains("material") && selectedFormatOverride != .elegoo {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Material")
                                .frame(width: 80, alignment: .leading)
                            TextField("Type", text: $material)
                            if selectedFormatOverride == .tigerTag {
                                Button {
                                    registryPickerTarget = .material
                                } label: {
                                    Image(systemName: "chevron.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .accessibilityLabel("Choose from the TigerTag material registry")
                            } else {
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
                        if selectedFormatOverride == .tigerTag {
                            tigerRegistryCaption(
                                TigerTagRegistry.materialID(for: material), undefinedLabel: "None"
                            )
                        }
                    }
                }
                
                // Color
                if visibleFieldIDs.contains("color_hex") {
                    FilamentColorEditor(colors: $colors, showsPattern: false, title: "Color")
                }
                
                // Brand Name
                if visibleFieldIDs.contains("brand") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Brand")
                                .frame(width: 80, alignment: .leading)
                            TextField("Brand Name", text: $brand)
                                .accessibilityIdentifier("writeTag.brand")
                            if selectedFormatOverride == .tigerTag {
                                Button {
                                    registryPickerTarget = .brand
                                } label: {
                                    Image(systemName: "chevron.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .accessibilityLabel("Choose from the TigerTag brand registry")
                            } else {
                                Button {
                                    showBrandPicker = true
                                } label: {
                                    Image(systemName: "chevron.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .accessibilityIdentifier("writeTag.brandPicker")
                                .accessibilityLabel("Choose a manufacturer")
                            }
                        }
                        if selectedFormatOverride == .tigerTag {
                            tigerRegistryCaption(
                                TigerTagRegistry.brandID(for: brand), undefinedLabel: "Generic"
                            )
                        }
                    }
                }

                if visibleFieldIDs.contains("subtype") {
                    VStack(alignment: .leading, spacing: 2) {
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
                        if selectedFormatOverride == .tigerTag {
                            // Aspects carry the subtype; show what the words resolve to.
                            let aspects = TigerTagRegistry.aspects(forSubtype: subtype)
                            if let label = TigerTagRegistry.subtypeLabel(aspect1: aspects.aspect1, aspect2: aspects.aspect2) {
                                Text("→ Aspects: \(label)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if WriteTagFormAssembler.shouldShowNameField(
                    visibleFieldIDs: visibleFieldIDs
                ) {
                    // On an ACE tag this field is the SKU, and it can default
                    // to the spool ID rather than the name — so it says so.
                    if selectedFormatOverride == .anycubicACE {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("SKU")
                                    .frame(width: 80, alignment: .leading)
                                TextField("SKU", text: skuBinding)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                            }
                            // Only where this backend's spool IDs are the ones
                            // SpoolLink resolves: on the on-device Library, "spool
                            // 3" would name a different spool than the one listed.
                            if store.capabilities.spoolIDsResolveViaSpoolLink,
                               let spoolID = SpoolLinkSKU.spoolID(fromSKU: skuBinding.wrappedValue) {
                                Text("Lets an ACE find spool \(spoolID) through SpoolLink. Type over it to write a name instead.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text("Name")
                                .frame(width: 80, alignment: .leading)
                            TextField("Filament Name", text: $name)
                        }
                    }
                }

                if visibleFieldIDs.contains("density") {
                    HStack {
                        Text("Density")
                            .frame(width: 80, alignment: .leading)
                        TextField("g/cm³", text: $densityInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if visibleFieldIDs.contains("diameter") {
                    HStack {
                        Text("Diameter")
                            .frame(width: 80, alignment: .leading)
                        TextField("mm", text: $diameterInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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
                    
                    // The ELEGOO block holds no bed range.
                    if selectedFormatOverride != .elegoo {
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

                    if visibleFieldIDs.contains("preheat_temp") {
                        HStack {
                            Text("Preheat")
                            Spacer()
                            TextField("°C", value: $preheatTemp, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                            Stepper("", value: $preheatTemp, in: 0...400).labelsHidden()
                        }
                    }
                }
            }


            
            if visibleFieldIDs.contains("nominal_weight") || visibleFieldIDs.contains("empty_weight")
                || visibleFieldIDs.contains("remaining") || countdownNote != nil {
                Section {
                    if visibleFieldIDs.contains("nominal_weight") {
                        HStack {
                            Text("Net Weight")
                            Spacer()
                            TextField("g", value: $nominalWeight, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                        }
                    }
                    if visibleFieldIDs.contains("empty_weight") {
                        HStack {
                            Text("Empty Spool")
                            Spacer()
                            TextField("g", value: $emptyWeight, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                        }
                    }
                    if visibleFieldIDs.contains("remaining") {
                        HStack {
                            Text("Remaining")
                            Spacer()
                            TextField("g", value: $remainingWeight, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                        }
                    }
                } header: {
                    Text("Weight")
                } footer: {
                    if let countdownNote {
                        Text(countdownNote).font(.subheadline)
                    }
                }
            }

            if visibleFieldIDs.contains("drying_temp") || visibleFieldIDs.contains("drying_time") {
                Section("Drying") {
                    if visibleFieldIDs.contains("drying_temp") {
                        HStack {
                            Text("Drying Temp")
                            Spacer()
                            TextField("°C", value: $dryingTemp, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 50)
                            Stepper("", value: $dryingTemp, in: 0...120).labelsHidden()
                        }
                    }
                    if visibleFieldIDs.contains("drying_time") {
                        HStack {
                            Text("Drying Time")
                            Spacer()
                            TextField("min", value: $dryingTime, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60)
                        }
                    }
                }
            }

            if visibleFieldIDs.contains("gtin") || visibleFieldIDs.contains("country") || visibleFieldIDs.contains("manufactured_date") {
                Section("Identification") {
                    if visibleFieldIDs.contains("gtin") {
                        HStack {
                            Text("GTIN").frame(width: 100, alignment: .leading)
                            TextField("Barcode digits", text: $gtin).keyboardType(.numberPad)
                        }
                    }
                    if visibleFieldIDs.contains("country") {
                        HStack {
                            Text("Country").frame(width: 100, alignment: .leading)
                            TextField("ISO-2 (e.g. CZ)", text: $country)
                                .textInputAutocapitalization(.characters).disableAutocorrection(true)
                        }
                    }
                    if visibleFieldIDs.contains("manufactured_date") {
                        DatePicker("Manufactured", selection: $manufacturedDate, displayedComponents: .date)
                    }
                }
            }

            if visibleFieldIDs.contains("url") {
                Section("NFC Tag Options") {
                    HStack {
                        Text("URL").frame(width: 60, alignment: .leading)
                        TextField("https://… (optional)", text: $urlRecord)
                            .keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                    }
                    Text("Adds a URL NDEF record readable by any NFC device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if FilamentOpacity.offersWriteSwitch(td: transmissionDistance, format: selectedFormatOverride) {
                Section {
                    Toggle("Write Opacity to Tag", isOn: $writesOpacity)
                } footer: {
                    Text("\(FilamentOpacity.displayText(alpha: FilamentOpacity.alpha(forTD: transmissionDistance))), from this filament's TD. Off writes every filament as opaque, on every tag from now on.")
                }
            }

            if visibleFieldIDs.contains("spool_id"), store.tagIdentity.writesSpoolID {
                Section("Linked Data") {
                HStack {
                    // "Spool ID" is what the field catalog itself calls this
                    // (`NFCFieldSchema`), and the id written to the tag is the
                    // active backend's — not necessarily Spoolman's.
                    Text("Spool ID")
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
            }
            }

            if let breakdown = capacityBreakdown {
                Section("Tag capacity") {
                    TagCapacityGaugeView(breakdown: breakdown)
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                TagReaderPicker(selection: $tagReader, purpose: .write(format: selectedFormatOverride), floating: true)
                if offersOtherSide {
                    WriteOtherSideButton(action: writeOtherSide)
                        .disabled(nfcManager.isScanning)
                }
                Button(action: requestWrite) {
                    Label(writeButtonTitle, systemImage: "badge.plus.radiowaves.right")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .writeTagButtonStyle()
                .tagReplacePrompt($replaceRequest) { _ in
                    replacesOnWriteLink = true
                    writeTag()
                }
                .disabled(nfcManager.isScanning || (selectedFormatOverride == .elegoo && elegooEntry == nil)
                    || (visibleFieldIDs.contains("color_hex") && !colors.isValid)
                    || serverTagGate == .locked)
            }
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
                        Text("\(brand) \(material) — \(colors.hexes.compactMap(FilamentColors.normalizedHex).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    FilamentSwatch(colors: colors, size: 28)
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
        .keyboardDoneBar()
        .selectsTextOnFocus()
        .navigationTitle("Write Tag")
        .navigationBarBackButtonHidden(run.holdsScreen(isScanning: nfcManager.isScanning))
        .interactiveDismissDisabled(run.holdsScreen(isScanning: nfcManager.isScanning))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCustomizeFields = true
                } label: {
                    Label("Customize Fields", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showCustomizeFields, onDismiss: { fieldVisibilityRefreshToken += 1 }) {
            NavigationStack {
                Form {
                    Section("Optional Fields") {
                        FieldVisibilityEditor(format: selectedFormatOverride)
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
        .sheet(isPresented: $showBrandPicker) {
            NavigationStack {
                ManufacturerPickerView(current: ManufacturerChoice.named(brand, in: store.vendors)) { choice in
                    brand = choice.name ?? ""
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showBrandPicker = false }
                    }
                }
            }
        }
        .sheet(item: $registryPickerTarget) { target in
            switch target {
            case .material:
                RegistryPickerSheet(title: "Material", entries: TigerTagRegistry.allMaterials, label: \.label, selection: $pickedMaterial)
            case .brand:
                RegistryPickerSheet(title: "Brand", entries: TigerTagRegistry.allBrands, label: \.label, selection: $pickedBrand)
            case .canvasFilament:
                RegistryPickerSheet(title: "Canvas Filament", entries: ElegooCanvasCatalog.entries, label: \.name, selection: $elegooEntry)
            }
        }
        .onChange(of: pickedMaterial) { _, entry in
            if let entry { material = entry.label }
        }
        .onChange(of: pickedBrand) { _, entry in
            if let entry { brand = entry.label }
        }
        // Using the feature retires its tip; a tap outside the popover only
        // hides it. Every way in to writing a tag lands here. On disappear,
        // not appear: retiring it makes the Settings tip (AboutTip) current,
        // and the Tags root is still on screen while this one slides in, so
        // its popover flashed over this screen's toolbar.
        .onDisappear { WriteTagTip().invalidate(reason: .actionPerformed) }
        .onAppear {
            if !didApplyInitialReader {
                didApplyInitialReader = true
                tagReader = initialReader
            }
            selectedFormatOverride = WriteTagFormAssembler.initialOverride(
                defaultRawValue: nfcTagFormat,
                recordedFormat: recentTagsKeepFormat ? initialFormat : nil
            )
            if let data = initialData {
                populateFromData(data)
                clearStaleSpoolID()
            }
            suggestElegooEntry()
        }
        .onChange(of: selectedFormatOverride) { _, format in
            if format == .elegoo { suggestElegooEntry() }
        }
        // A form opened before the first spool fetch landed could not judge.
        .onChange(of: store.spools.isEmpty) { _, isEmpty in
            if !isEmpty { clearStaleSpoolID() }
        }
        .alert(isPresented: Binding<Bool>(
            get: { !nfcManager.alertMessage.isEmpty },
            set: { _ in nfcManager.alertMessage = "" }
        )) {
            Alert(title: Text("NFC Error"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
        }
        .onChange(of: nfcManager.lastWriteSucceeded) { _, succeeded in
            if succeeded { onTagWritten?(nfcManager.lastWrittenTagUID) }
            if succeeded, var data = nfcManager.tagDataToWrite?.readingSpoolLinkSKU() {
                // Restore name for Recent Tags display (may have been stripped for NFC format)
                if data.name == nil && !name.isEmpty {
                    data.name = name
                }
                // The Recent Tag that carried the stale ID is superseded by
                // this one, not kept beside it with its badge.
                recentTagManager.addTag(
                    data,
                    format: nfcManager.writeFormatToUse,
                    replacing: clearedSpoolID == nil ? nil : initialData
                )
                triggerWriteSuccess()
                supportPrompts.record(.tagWriteSucceeded)
                linkWrittenTagToItsSpool()
                linkWrittenTagToItsFilament()
            }
        }
        .alert("Tag Written, Not Linked", isPresented: Binding(
            get: { linkFailure != nil },
            set: { if !$0 { linkFailure = nil } }
        ), presenting: linkFailure) { _ in
            Button("OK", role: .cancel) { linkFailure = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Maps the tag that was just written to the spool it was written FOR.
    ///
    /// Writing a tag from an existing spool used to leave the two unconnected:
    /// the write ran on an `NFCNDEFReaderSession`, which never reports a tag's
    /// UID, so the app finished the write without knowing which tag it had just
    /// written. Writes now run on the tag session and `lastWrittenTagUID` is
    /// the missing half.
    ///
    /// The spool id on the FORM is what identifies the owner — not the id that
    /// reached the tag. Those differ outside Spool ID mode, where no spool id
    /// is written, yet the tag was still written for this spool.
    private func linkWrittenTagToItsSpool() {
        guard store.tagIdentity.writesLinks,
              store.capabilities.supportsTagMapping,
              let uid = nfcManager.lastWrittenTagUID,
              let spoolId = spoolmanId,
              let spool = store.spools.first(where: { $0.id == spoolId })
        else { return }

        let replacing = replacesOnWriteLink
        replacesOnWriteLink = false
        Task {
            let outcome = await TagLinkService.assign(uid, to: spool, in: store, replacing: replacing)
            // A caveat here is not a failed write — the tag is written either
            // way — so it is reported as what it is: the mapping half.
            linkFailure = outcome.followUpNote
        }
    }
    
    /// Spec 4: a tag written from a filament, with no spool chosen, is linked
    /// to that filament — where filament links are written at all.
    private func linkWrittenTagToItsFilament() {
        guard spoolmanId == nil,
              let filamentId = linkFilamentId,
              store.tagIdentity.writesFilamentLinks(store: store.filamentTagStore),
              let uid = nfcManager.lastWrittenTagUID
        else { return }
        Task {
            switch await store.linkFilamentTag(filamentId: filamentId, uid: uid) {
            case .linked:
                break
            case .failed(let message):
                linkFailure = message
            case .heldBySpool(let id):
                linkFailure = "Spool #\(id) holds this tag, so it was not linked to the filament."
            case .heldByFilament(let id):
                linkFailure = "Filament #\(id) holds this tag, so it was not linked to this one."
            }
        }
    }

    private var defaultSKU: String {
        WriteTagFormAssembler.defaultACESKU(
            name: name,
            spoolID: spoolmanId,
            spoolIDsResolveViaSpoolLink: store.capabilities.spoolIDsResolveViaSpoolLink
        )
    }

    private var skuBinding: Binding<String> {
        Binding(get: { skuOverride ?? defaultSKU }, set: { skuOverride = $0 })
    }

    private func populateFromData(_ data: FilamentTagData) {
        self.name = data.name ?? ""
        self.material = data.material
        if let subtype = data.subtype, !subtype.isEmpty {
            self.subtype = subtype
        } else if let name = data.name {
            self.subtype = SubtypeOptionService.derive(from: name)
        } else {
            self.subtype = ""
        }
        self.brand = data.brand
        self.colors = data.colors
        self.minNozzleTemp = data.minNozzleTemp
        self.maxNozzleTemp = data.maxNozzleTemp
        self.minBedTemp = data.minBedTemp
        self.maxBedTemp = data.maxBedTemp
        self.spoolmanId = data.spoolmanId
        self.spoolmanIdInput = data.spoolmanId.map(String.init) ?? ""

        self.transmissionDistance = data.transmissionDistance
        self.carriedAlpha = data.colorAlpha

        let rows = WriteTagFormAssembler.prefill(from: data)
        self.nominalWeight = rows.nominalWeight
        self.emptyWeight = rows.emptyWeight
        self.remainingWeight = rows.remaining
        self.densityInput = rows.density
        self.diameterInput = rows.diameter
        self.preheatTemp = rows.preheat
        self.dryingTemp = rows.dryingTemp
        self.dryingTime = rows.dryingTime
        self.gtin = rows.gtin
        self.country = rows.country
        if let manufactured = rows.manufactured { self.manufacturedDate = manufactured }
        self.urlRecord = rows.url
    }

    /// Drops a pre-filled spool ID that now names a different spool, or none,
    /// before it can be written onto the tag (OpenSpool `spool_id`, the ACE
    /// SKU) or link the tag to that spool. Leaves an ID the user has already
    /// changed alone.
    private func clearStaleSpoolID() {
        guard let data = initialData, spoolmanId == data.spoolmanId,
              let stale = WriteTagFormAssembler.staleSpoolID(in: data, spools: store.spools)
        else { return }
        spoolmanId = nil
        spoolmanIdInput = ""
        clearedSpoolID = stale
    }

    private func updateSpoolmanId(from rawValue: String) {
        let digitsOnly = rawValue.filter { $0.isNumber }
        if digitsOnly != rawValue {
            spoolmanIdInput = digitsOnly
        }
        spoolmanId = Int(digitsOnly)
    }
    
    /// ELEGOO's material row: a Canvas filament from the catalog rather than
    /// free text, because page 19 can only name what the Canvas knows. The
    /// whole row opens the list — 33 entries, chosen one-handed at the bench —
    /// in the sheet TigerTag's registries use; every name carries its type.
    @ViewBuilder
    private var elegooFilamentRow: some View {
        Button {
            registryPickerTarget = .canvasFilament
        } label: {
            HStack {
                Text("Canvas Filament")
                    .foregroundStyle(.primary)
                Spacer()
                Text(elegooEntry?.name ?? "Choose")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down.circle")
                    .foregroundColor(.accentColor)
            }
            .contentShape(Rectangle())
        }
        // Plain, so the label reads like the form's other rows rather than
        // taking the button tint; the whole row stays the tap target.
        .buttonStyle(.plain)
        .accessibilityLabel("Canvas Filament")
        .accessibilityValue(elegooEntry?.name ?? "None chosen")
        .accessibilityHint("Chooses what an ELEGOO Canvas reads this tag as")
        Text(WriteTagFormAssembler.elegooFilamentCaption(entry: elegooEntry, material: material))
            .font(elegooEntry == nil ? .body : .subheadline)
            .foregroundStyle(elegooEntry == nil ? Color.orange : Color.secondary)
    }

    private func suggestElegooEntry() {
        elegooEntry = ElegooCanvasCatalog.suggestedEntry(material: material, subtype: subtype)
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

        // ELEGOO writes the picked Canvas filament, never the free-text fields.
        let elegooFields = selectedFormatOverride == .elegoo
            ? elegooEntry.map(ElegooCanvasCatalog.tagFields(for:))
            : nil

        let resolvedSpoolmanID: Int? = if visibleFieldIDs.contains("spool_id") {
            spoolmanId
        } else {
            nil
        }

        // `visibleFieldIDs` is already scoped to the selected format, so
        // membership is the whole test — a second format check here would
        // hide fields the format's own catalog offers.
        func vis(_ id: String) -> Bool { visibleFieldIDs.contains(id) }

        let data = WriteTagFormAssembler.buildTagData(
            format: selectedFormatOverride,
            name: resolvedName,
            sku: skuBinding.wrappedValue,
            material: elegooFields?.material ?? material,
            subtype: elegooFields.map { $0.subtype ?? "" } ?? resolvedSubtype,
            brand: brand,
            colorHex: colors.tagColorFields.colorHex,
            additionalColorHexes: colors.tagColorFields.additionalColorHexes,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            spoolmanId: resolvedSpoolmanID,
            writeSpoolID: store.tagIdentity.writesSpoolID,
            preheatTemp: vis("preheat_temp") ? preheatTemp : nil,
            nominalNetWeight: vis("nominal_weight") ? Double(nominalWeight) : nil,
            emptyContainerWeight: vis("empty_weight") ? Double(emptyWeight) : nil,
            density: vis("density") ? WriteTagFormAssembler.statedDecimal(densityInput) : nil,
            diameter: vis("diameter") ? WriteTagFormAssembler.statedDecimal(diameterInput) : nil,
            dryingTemp: vis("drying_temp") ? dryingTemp : nil,
            dryingTime: vis("drying_time") ? dryingTime : nil,
            gtin: vis("gtin") && !gtin.isEmpty ? gtin : nil,
            countryOfOrigin: vis("country") && !country.isEmpty ? country : nil,
            manufacturedDateUnix: vis("manufactured_date") ? WriteTagFormAssembler.unixSeconds(from: manufacturedDate) : nil,
            tagURL: vis("url") && !urlRecord.trimmingCharacters(in: .whitespaces).isEmpty ? urlRecord : nil,
            remainingWeight: vis("remaining") ? remainingWeight : nil,
            transmissionDistance: transmissionDistance,
            carriedAlpha: carriedAlpha,
            writesOpacity: writesOpacity
        )

        return data
    }

    /// The Write Tag button: asks first when the write would replace FilaMan's
    /// one tag. The tag's ID is known up front only for a scanned one; for a
    /// blank tag the spool holding any tag is the condition (see
    /// `TagReplaceRequest.writing`).
    /// While the server is down: a write that links is locked, and one onto a
    /// scanned tag the server still links elsewhere is refused. A blank tag's
    /// ID is unknown until it is written, so only a scanned one is checked.
    private var serverTagGate: ServerTagWriteRule.Gate {
        let owner = scannedCardUID.map { store.owner(ofTagUID: $0) } ?? .none
        return ServerTagWriteRule.gate(
            isDown: serverLink.isDown,
            links: store.tagIdentity.writesLinks && (spoolmanId != nil || linkFilamentId != nil),
            isOwned: owner != .none,
            ownerName: owner == .none ? nil : owner.label
        )
    }

    private var writeButtonTitle: String {
        guard nfcManager.isScanning else { return "Write Tag" }
        return run.progressText ?? "Write Tag"
    }

    private func requestWrite() {
        if case .refused(let message) = serverTagGate {
            nfcManager.alertMessage = message
            return
        }
        replacesOnWriteLink = false
        if store.tagIdentity.writesLinks, store.capabilities.supportsTagMapping,
           let spoolId = spoolmanId, let spool = store.spools.first(where: { $0.id == spoolId }),
           let request = TagReplaceRequest.writing(
               spool: spool, knownUID: scannedCardUID, targets: store.tagIdentity.linkTargets
           ) {
            replaceRequest = request
            return
        }
        writeTag()
    }

    private func writeTag() {
        let data = buildTagData()
        
        // Validate data before attempting write
        if let error = data.validate() {
            nfcManager.alertMessage = error.localizedDescription
            return
        }
        
        run = .start(tagReader, purpose: .write(format: selectedFormatOverride), printer: printer, store: store)
        writtenSignature = formSignature
        nfcManager.writeTag(data: data, format: selectedFormatOverride, cardUID: scannedCardUID, reader: run.reader)
    }

    /// What the form says now, as the write would send it.
    private var formSignature: String {
        var data = buildTagData()
        data.id = nil
        let json = (try? JSONEncoder().encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return "\(selectedFormatOverride.rawValue)|\(json)"
    }

    /// A toolhead wrote this form's data and the form still says the same.
    private var offersOtherSide: Bool {
        nfcManager.lastWriteSucceeded && run.offersOtherSide && writtenSignature == formSignature
    }

    /// The same data in the same format, written to the spool's other tag.
    private func writeOtherSide() {
        guard let data = nfcManager.tagDataToWrite, let format = nfcManager.writeFormatToUse else { return }
        run = TagReaderRun(reader: .iPhone, isWriting: true)
        nfcManager.writeTag(data: data, format: format, cardUID: scannedCardUID, reader: .iPhone)
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
}
