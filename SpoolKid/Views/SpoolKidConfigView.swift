//
//  SpoolKidConfigView.swift
//  SpoolKid
//
//  Purpose: Settings screen for configuring the app.
//  Features:
//  - Spoolman URL configuration and connection testing.
//  - Toggle for "Write Spool ID to Tag" preference.
//

import SwiftUI

struct SpoolKidConfigView: View {
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("spoolman_connection_valid") private var isConnectionValid: Bool = false
    @AppStorage("write_spool_id") private var writeSpoolId: Bool = true
    @AppStorage("remember_spool_data") private var rememberSpoolData: Bool = false
    @AppStorage("remember_filament_data") private var rememberFilamentData: Bool = false
    @StateObject private var spoolManService = SpoolManService()
    @State private var testResult: String? = nil
    @State private var isTesting = false
    @State private var connectionFailed = false
    
    var textColor: Color {
        if isConnectionValid { return .green }
        if connectionFailed { return .red }
        return .primary
    }
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("SpoolMan Host"), footer: Text("Default SpoolMan port is 7912.\nNote: This app was tested only with SpoolMan IP address and HTTP protocol (not HTTPS).")) {
                    TextField("SpoolMan URL", text: $spoolmanUrl)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(textColor)
                        .onChange(of: spoolmanUrl) { _ in
                            isConnectionValid = false
                            connectionFailed = false
                            testResult = nil
                        }
                }
                
                Section(header: Text("NFC Tag Options")) {
                    Toggle("Write Spool ID to Tag", isOn: $writeSpoolId)
                }

                Section(header: Text("Spoolman Management"), footer: Text("If enabled, the app will remember values entered when creating a new spool or filament and prepopulate them next time. This is useful when adding batches of similar items.")) {
                    Toggle("Remember last added spool data", isOn: $rememberSpoolData)
                    Toggle("Remember last added filament data", isOn: $rememberFilamentData)
                }
            }
            
            if let result = testResult {
                Text(result)
                    .foregroundColor(result == "Connection Successful" ? .green : .red)
                    .padding(.bottom)
            }
            
            Button(action: testConnection) {
                HStack {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 5)
                    }
                    Text("Test Connection")
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(isConnectionValid || isTesting || spoolmanUrl.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isConnectionValid || isTesting || spoolmanUrl.isEmpty)
            .padding()
        }
        .navigationTitle("Configure SpoolKid")
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        connectionFailed = false
        
        Task {
            let success = await spoolManService.testConnection(baseUrl: spoolmanUrl)
            isTesting = false
            isConnectionValid = success
            connectionFailed = !success
            
            if success {
                testResult = "Connection Successful"
            } else {
                testResult = spoolManService.errorMessage ?? "Connection Failed"
            }
        }
    }
}
