import SwiftUI

struct FilamentFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolManService
    let baseUrl: String
    var filamentToEdit: SpoolManFilament?
    
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
    @State private var density: Double = AppConfig.Defaults.density
    @State private var diameter: Double = AppConfig.Defaults.diameter
    @State private var extruderTemp: Int = AppConfig.Defaults.extruderTemp
    @State private var bedTemp: Int = AppConfig.Defaults.bedTemp
    @State private var userModifiedTemps: Bool = false
    
    var materials: [String] { AppConfig.materials }
    
    var extruderTempBinding: Binding<Int> {
        Binding(
            get: { self.extruderTemp },
            set: {
                self.extruderTemp = $0
                self.userModifiedTemps = true
            }
        )
    }
    
    var bedTempBinding: Binding<Int> {
        Binding(
            get: { self.bedTemp },
            set: {
                self.bedTemp = $0
                self.userModifiedTemps = true
            }
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $name)
                    
                    // Material Type with Menu
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
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Picker("Vendor", selection: $vendorId) {
                        Text("None").tag(Optional<Int>.none)
                        ForEach(service.vendors) { vendor in
                            Text(vendor.name).tag(Optional(vendor.id))
                        }
                    }
                }
                
                Section(header: Text("Color")) {
                    HStack {
                        Text("Color")
                            .frame(width: 80, alignment: .leading)
                        
                        TextField("Hex", text: $colorHex)
                            .onChange(of: colorHex) { newValue in
                                if let newColor = Color(hex: newValue) {
                                    color = newColor
                                }
                            }
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                        
                        ColorPicker("", selection: $color)
                            .labelsHidden()
                            .onChange(of: color) { newColor in
                                if let hex = newColor.toHex() {
                                    colorHex = hex
                                }
                            }
                    }
                }
                
                Section(header: Text("Physical Properties")) {
                    HStack {
                        Text("Density (g/cm³)")
                        Spacer()
                        TextField("\(AppConfig.Defaults.density)", value: $density, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Diameter (mm)")
                        Spacer()
                        TextField("\(AppConfig.Defaults.diameter)", value: $diameter, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                Section(header: Text("Temperatures")) {
                    HStack {
                        Text("Extruder Temp")
                        Spacer()
                        TextField("°C", value: extruderTempBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: extruderTempBinding, in: 0...400)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Bed Temp")
                        Spacer()
                        TextField("°C", value: bedTempBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Stepper("", value: bedTempBinding, in: 0...150)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle(filamentToEdit == nil ? "Add Filament" : "Edit Filament")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if rememberFilamentData {
                                lastFilamentMaterial = material
                                lastFilamentVendorId = vendorId ?? -1
                                lastFilamentColorHex = colorHex
                                lastFilamentDensity = density
                                lastFilamentDiameter = diameter
                                lastFilamentExtruderTemp = extruderTemp
                                lastFilamentBedTemp = bedTemp
                            }

                            if let filament = filamentToEdit {
                                await service.updateFilament(
                                    id: filament.id,
                                    name: name.isEmpty ? nil : name,
                                    vendorId: vendorId,
                                    material: material.isEmpty ? nil : material,
                                    colorHex: colorHex.isEmpty ? nil : colorHex,
                                    density: density,
                                    diameter: diameter,
                                    extruderTemp: extruderTemp,
                                    bedTemp: bedTemp,
                                    baseUrl: baseUrl
                                )
                            } else {
                                _ = await service.addFilament(
                                    name: name.isEmpty ? nil : name,
                                    vendorId: vendorId,
                                    material: material.isEmpty ? nil : material,
                                    colorHex: colorHex.isEmpty ? nil : colorHex,
                                    density: density,
                                    diameter: diameter,
                                    extruderTemp: extruderTemp,
                                    bedTemp: bedTemp,
                                    baseUrl: baseUrl
                                )
                            }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                // Ensure vendors are loaded
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
                    if let d = filament.density { density = d }
                    if let dia = filament.diameter { diameter = dia }
                    if let et = filament.settingsExtruderTemp { extruderTemp = et }
                    if let bt = filament.settingsBedTemp { bedTemp = bt }
                    // userModifiedTemps = true // Removed to allow material change to update temps if user hasn't manually edited yet
                } else if rememberFilamentData {
                    if !lastFilamentMaterial.isEmpty { material = lastFilamentMaterial }
                    if lastFilamentVendorId != -1 { vendorId = lastFilamentVendorId }
                    colorHex = lastFilamentColorHex
                    if let newColor = Color(hex: colorHex) { color = newColor }
                    density = lastFilamentDensity
                    diameter = lastFilamentDiameter
                    extruderTemp = lastFilamentExtruderTemp
                    bedTemp = lastFilamentBedTemp
                }
            }
        }
    }
    
    private func updateTempsForMaterial(_ mat: String) {
        if !userModifiedTemps, let defaults = AppConfig.materialPresets[mat] {
            extruderTemp = defaults.extruder
            bedTemp = defaults.bed
        }
    }
}

