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

import SwiftUI

struct WriteTagView: View {
    @StateObject private var nfcManager = NFCManager()
    @StateObject private var spoolManService = SpoolManService()
    @StateObject private var recentTagManager = RecentTagManager()
    
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("write_spool_id") private var writeSpoolId: Bool = true
    
    // Form Fields
    @State private var name: String = ""
    @State private var material: String = AppConfig.Defaults.material
    @State private var showCopyToast: Bool = false
    @State private var brand: String = AppConfig.Defaults.brand
    @State private var color: Color = Color(hex: AppConfig.Defaults.colorHex) ?? .black
    @State private var colorHex: String = AppConfig.Defaults.colorHex
    @State private var minNozzleTemp: Int = AppConfig.Defaults.minNozzleTemp
    @State private var maxNozzleTemp: Int = AppConfig.Defaults.maxNozzleTemp
    @State private var minBedTemp: Int = AppConfig.Defaults.minBedTemp
    @State private var maxBedTemp: Int = AppConfig.Defaults.maxBedTemp
    @State private var spoolmanId: Int? = nil
    
    @State private var selectedSpoolId: Int?
    
    var initialData: FilamentTagData?
    
    let materials = AppConfig.materials
    let brands = AppConfig.brands
    
    var body: some View {
        Form {
            Section(header: Text("Filament Details")) {
                // Material Type
                HStack {
                    Text("Material")
                        .frame(width: 80, alignment: .leading)
                    TextField("Type", text: $material)
                    Menu {
                        ForEach(materials, id: \.self) { mat in
                            Button(mat) {
                                material = mat
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundColor(.blue)
                    }
                }
                
                // Color
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
                
                // Brand Name
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
                            .foregroundColor(.blue)
                    }
                }
                
                // Filament Name
                HStack {
                    Text("Name")
                        .frame(width: 80, alignment: .leading)
                    TextField("Filament Name", text: $name)
                }
            }
            
            Section(header: Text("Printing Parameters")) {
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
            
            if let id = spoolmanId {
                Section(header: Text("Linked Data")) {
                    HStack {
                        Text("SpoolMan ID")
                        Spacer()
                        Text("\(id)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(action: writeTag) {
                    HStack {
                        Image(systemName: "wave.3.right")
                        Text("Write to NFC Tag")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(nfcManager.isScanning)

                Button(action: copyPayload) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Payload")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Create Tag")
        .onAppear {
            if let data = initialData {
                populateFromData(data)
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { !nfcManager.alertMessage.isEmpty },
            set: { _ in nfcManager.alertMessage = "" }
        )) {
            Alert(title: Text("NFC"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
        }
        .overlay(
            VStack {
                Spacer()
                if showCopyToast {
                    Text("Payload Copied!")
                        .font(.body)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: showCopyToast)
            .allowsHitTesting(false)
        )
    }
    
    private func populateFromData(_ data: FilamentTagData) {
        self.name = data.name ?? ""
        self.material = data.material
        self.brand = data.brand
        self.color = data.color
        self.colorHex = data.colorHex
        self.minNozzleTemp = data.minNozzleTemp
        self.maxNozzleTemp = data.maxNozzleTemp
        self.minBedTemp = data.minBedTemp
        self.maxBedTemp = data.maxBedTemp
        self.spoolmanId = data.spoolmanId
    }
    
    private func populateFromSpool(_ spool: SpoolManSpool) {
        if let n = spool.filament.name {
            self.name = n
        }
        if let mat = spool.filament.material {
            self.material = mat
        }
        if let vendor = spool.filament.vendor?.name {
            self.brand = vendor
        }
        if let hex = spool.filament.colorHex {
            self.color = Color(hex: hex) ?? .black
            self.colorHex = hex
        }
        if let minTemp = spool.filament.settingsExtruderTemp {
            self.minNozzleTemp = minTemp
            self.maxNozzleTemp = minTemp + 10 // Default range if only one provided
        }
        if let bedTemp = spool.filament.settingsBedTemp {
            self.minBedTemp = bedTemp
            self.maxBedTemp = bedTemp + 5
        }
        self.spoolmanId = spool.id
    }
    
    private func writeTag() {
        let data = FilamentTagData(
            name: name,
            material: material,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            // Passing nil for an optional Codable property causes the key to be omitted from the JSON output
            spoolmanId: writeSpoolId ? spoolmanId : nil
        )
        nfcManager.writeTag(data: data)
        
        // Save to recent tags
        recentTagManager.addTag(data)
    }
    
    private func copyPayload() {
        let data = FilamentTagData(
            name: name,
            material: material,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            spoolmanId: writeSpoolId ? spoolmanId : nil
        )
        
        if let jsonData = TagFormatService.shared.encode(data: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            UIPasteboard.general.string = jsonString
            
            withAnimation {
                showCopyToast = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopyToast = false
                }
            }
        }
    }
}
