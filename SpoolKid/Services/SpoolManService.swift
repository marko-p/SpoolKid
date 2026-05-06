//
//  SpoolmanService.swift
//  SpoolKid
//
//  Purpose: Networking service to interact with the self-hosted Spoolman API.
//  Responsibilities:
//  - Fetching, Creating, Updating, and Deleting Spools, Filaments, and Vendors.
//  - Handling API authentication (Basic Auth, Bearer Token) and error handling.
//  - Supporting HTTPS with self-signed certificates when configured.
//  - Managing local state (@Published properties) for UI binding.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation
import Combine

@MainActor
class SpoolmanService: ObservableObject {
    @Published var spools: [SpoolmanSpool] = []
    @Published var filaments: [SpoolmanFilament] = []
    @Published var vendors: [SpoolmanVendor] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// Returns a URLSession configured based on the current "Trust All Certificates" setting.
    /// When enabled, uses a custom delegate that accepts any server certificate (for self-signed HTTPS).
    /// Otherwise, uses the default shared session with standard certificate validation.
    private var session: URLSession {
        let trustAll = UserDefaults.standard.bool(forKey: AppConfig.trustAllCertsKey)
        if trustAll {
            let config = URLSessionConfiguration.default
            return URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
        }
        return URLSession.shared
    }
    
    /// Applies the configured authentication headers to a URLRequest.
    /// Reads the auth type and credentials from UserDefaults (set via Settings.bundle).
    private func applyAuth(to request: inout URLRequest) {
        let authType = UserDefaults.standard.string(forKey: AppConfig.authTypeKey) ?? "none"
        
        switch authType {
        case "basic":
            let username = UserDefaults.standard.string(forKey: AppConfig.authUsernameKey) ?? ""
            let password = UserDefaults.standard.string(forKey: AppConfig.authPasswordKey) ?? ""
            if !username.isEmpty {
                let credentials = "\(username):\(password)"
                if let data = credentials.data(using: .utf8) {
                    let base64 = data.base64EncodedString()
                    request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
                }
            }
        case "bearer":
            let token = UserDefaults.standard.string(forKey: AppConfig.authTokenKey) ?? ""
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        default:
            break
        }
    }
    
    func fetchSpools(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/spool", baseUrl: baseUrl) { [weak self] (items: [SpoolmanSpool]) in
            self?.spools = items
        }
    }
    
    func fetchFilaments(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/filament", baseUrl: baseUrl) { [weak self] (items: [SpoolmanFilament]) in
            self?.filaments = items
        }
    }
    
    func fetchVendors(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/vendor", baseUrl: baseUrl) { [weak self] (items: [SpoolmanVendor]) in
            self?.vendors = items
        }
    }
    
    func testConnection(baseUrl: String) async -> Bool {
        do {
            let _: [SpoolmanVendor] = try await sendRequest(method: "GET", endpoint: "/api/v1/vendor", baseUrl: baseUrl)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    // MARK: - CRUD Operations
    
    // Generic Request Helper
    private func sendRequest<T: Decodable>(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuth(to: &request)
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw NSError(domain: "SpoolmanError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            } else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                throw NSError(domain: "SpoolmanError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error \(httpResponse.statusCode): \(bodyString)"])
            }
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func sendDeleteRequest(endpoint: String, baseUrl: String) async throws {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuth(to: &request)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // Vendors
    func addVendor(name: String, baseUrl: String) async -> SpoolmanVendor? {
        do {
            let newVendor: SpoolmanVendor = try await sendRequest(method: "POST", endpoint: "/api/v1/vendor", baseUrl: baseUrl, body: ["name": name])
            self.vendors.append(newVendor)
            return newVendor
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    func updateVendor(id: Int, name: String, baseUrl: String) async {
        do {
            let updatedVendor: SpoolmanVendor = try await sendRequest(method: "PATCH", endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl, body: ["name": name])
            if let index = self.vendors.firstIndex(where: { $0.id == id }) {
                self.vendors[index] = updatedVendor
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    func deleteVendor(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl)
            self.vendors.removeAll { $0.id == id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // Filaments
    func addFilament(name: String?, vendorId: Int?, material: String?, colorHex: String?, density: Double?, diameter: Double?, extruderTemp: Int?, bedTemp: Int?, baseUrl: String) async -> SpoolmanFilament? {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let vendorId = vendorId { body["vendor_id"] = vendorId }
        if let material = material { body["material"] = material }
        if let colorHex = colorHex { body["color_hex"] = colorHex }
        if let density = density { body["density"] = density }
        if let diameter = diameter { body["diameter"] = diameter }
        if let extruderTemp = extruderTemp { body["settings_extruder_temp"] = extruderTemp }
        if let bedTemp = bedTemp { body["settings_bed_temp"] = bedTemp }
        
        do {
            let newFilament: SpoolmanFilament = try await sendRequest(method: "POST", endpoint: "/api/v1/filament", baseUrl: baseUrl, body: body)
            self.filaments.append(newFilament)
            return newFilament
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    func updateFilament(id: Int, name: String?, vendorId: Int?, material: String?, colorHex: String?, density: Double?, diameter: Double?, extruderTemp: Int?, bedTemp: Int?, baseUrl: String) async {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let vendorId = vendorId { body["vendor_id"] = vendorId }
        if let material = material { body["material"] = material }
        if let colorHex = colorHex { body["color_hex"] = colorHex }
        if let density = density { body["density"] = density }
        if let diameter = diameter { body["diameter"] = diameter }
        if let extruderTemp = extruderTemp { body["settings_extruder_temp"] = extruderTemp }
        if let bedTemp = bedTemp { body["settings_bed_temp"] = bedTemp }
        
        do {
            let updatedFilament: SpoolmanFilament = try await sendRequest(method: "PATCH", endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.filaments.firstIndex(where: { $0.id == id }) {
                self.filaments[index] = updatedFilament
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    func deleteFilament(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl)
            self.filaments.removeAll { $0.id == id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // Spools
    func addSpool(filamentId: Int, remainingWeight: Double?, initialWeight: Double?, spoolWeight: Double?, usedWeight: Double?, price: Double?, lotNr: String? = nil, baseUrl: String) async -> SpoolmanSpool? {
        var body: [String: Any] = ["filament_id": filamentId]
        if let remainingWeight = remainingWeight { body["remaining_weight"] = remainingWeight }
        if let initialWeight = initialWeight { body["initial_weight"] = initialWeight }
        if let spoolWeight = spoolWeight { body["spool_weight"] = spoolWeight }
        if let usedWeight = usedWeight { body["used_weight"] = usedWeight }
        if let price = price { body["price"] = price }
        if let lotNr = lotNr { body["lot_nr"] = lotNr }
        
        do {
            let newSpool: SpoolmanSpool = try await sendRequest(method: "POST", endpoint: "/api/v1/spool", baseUrl: baseUrl, body: body)
            self.spools.append(newSpool)
            return newSpool
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    func updateSpool(id: Int, filamentId: Int?, remainingWeight: Double?, initialWeight: Double?, spoolWeight: Double?, usedWeight: Double?, price: Double?, lotNr: String? = nil, baseUrl: String) async {
        var body: [String: Any] = [:]
        if let filamentId = filamentId { body["filament_id"] = filamentId }
        if let remainingWeight = remainingWeight { body["remaining_weight"] = remainingWeight }
        if let initialWeight = initialWeight { body["initial_weight"] = initialWeight }
        if let spoolWeight = spoolWeight { body["spool_weight"] = spoolWeight }
        if let usedWeight = usedWeight { body["used_weight"] = usedWeight }
        if let price = price { body["price"] = price }
        if let lotNr = lotNr { body["lot_nr"] = lotNr }
        
        do {
            let updatedSpool: SpoolmanSpool = try await sendRequest(method: "PATCH", endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.spools.firstIndex(where: { $0.id == id }) {
                self.spools[index] = updatedSpool
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    /// Returns the first spool whose `lot_nr` contains the given card UID.
    /// Searches the in-memory `spools` array; call `fetchSpools` first to ensure it is current.
    func findSpool(byCardUID uid: String) -> SpoolmanSpool? {
        let normalized = SpoolMappingService.normalizeUID(uid)
        return spools.first { spool in
            SpoolMappingService.cardUIDs(in: spool.lotNr).contains(normalized)
        }
    }

    /// Persists a new `lot_nr` value for a spool via a PATCH request.
    /// On success, updates the in-memory spool entry.
    @discardableResult
    func setLotNr(spoolId: Int, lotNr: String, baseUrl: String) async -> Bool {
        do {
            let updated: SpoolmanSpool = try await sendRequest(
                method: "PATCH",
                endpoint: "/api/v1/spool/\(spoolId)",
                baseUrl: baseUrl,
                body: ["lot_nr": lotNr]
            )
            if let index = spools.firstIndex(where: { $0.id == spoolId }) {
                spools[index] = updated
            }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    /// Clears `lot_nr` by setting it to null via a PATCH request.
    /// On success, updates the in-memory spool entry.
    @discardableResult
    func clearLotNr(spoolId: Int, baseUrl: String) async -> Bool {
        do {
            let updated: SpoolmanSpool = try await sendRequest(
                method: "PATCH",
                endpoint: "/api/v1/spool/\(spoolId)",
                baseUrl: baseUrl,
                body: ["lot_nr": NSNull()]
            )
            if let index = spools.firstIndex(where: { $0.id == spoolId }) {
                spools[index] = updated
            }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSpool(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl)
            self.spools.removeAll { $0.id == id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func fetchData<T: Decodable>(endpoint: String, baseUrl: String, completion: @escaping ([T]) -> Void) async {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyAuth(to: &request)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let decodedItems = try JSONDecoder().decode([T].self, from: data)
            
            completion(decodedItems)
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
