//
//  ReadTagView.swift
//  SpoolKid
//
//  Purpose: The UI for scanning existing NFC tags.
//  Features:
//  - Triggers NFC scan via `NFCManager`.
//  - Displays the decoded data from the tag.
//  - (Future) Could allow editing the scanned data or syncing usage back to Spoolman.
//

import SwiftUI

struct ReadTagView: View {
    @StateObject private var nfcManager = NFCManager()
    
    var body: some View {
        VStack(spacing: 20) {
            if let data = nfcManager.scannedData {
                List {
                    Section(header: Text("Filament Info")) {
                        HStack {
                            Text("Material")
                            Spacer()
                            Text(data.material)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Brand")
                            Spacer()
                            Text(data.brand)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(data.color)
                                .frame(width: 20, height: 20)
                            Text(data.colorHex)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Temperatures")) {
                        HStack {
                            Text("Nozzle")
                            Spacer()
                            Text("\(data.minNozzleTemp) - \(data.maxNozzleTemp) °C")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Bed")
                            Spacer()
                            Text("\(data.minBedTemp) - \(data.maxBedTemp) °C")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let id = data.spoolmanId {
                        Section(header: Text("External Links")) {
                            HStack {
                                Text("SpoolMan ID")
                                Spacer()
                                Text("\(id)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Tag Scanned")
                        .font(.title2)
                        .bold()
                    Text("Scan an OpenSpool NFC tag to view its details.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Button(action: {
                nfcManager.startScanning()
            }) {
                Label("Scan Tag", systemImage: "wave.3.right")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Read Tag")
        .onAppear {
            if nfcManager.scannedData == nil && !nfcManager.isScanning {
                nfcManager.startScanning()
            }
        }
        .alert(isPresented: Binding<Bool>(
            get: { !nfcManager.alertMessage.isEmpty },
            set: { _ in nfcManager.alertMessage = "" }
        )) {
            Alert(title: Text("NFC"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
