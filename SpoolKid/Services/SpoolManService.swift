//
//  SpoolManService.swift
//  SpoolKid
//
//  Purpose: Networking service to interact with the self-hosted Spoolman API.
//  Responsibilities:
//  - Fetching, Creating, Updating, and Deleting Spools, Filaments, and Vendors.
//  - Handling API authentication (if added later) and error handling.
//  - Managing local state (@Published properties) for UI binding.
//

import Foundation
import Combine

class SpoolManService: ObservableObject {
    @Published var spools: [SpoolManSpool] = []
    @Published var filaments: [SpoolManFilament] = []
    @Published var vendors: [SpoolManVendor] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let session = URLSession.shared
    
    func fetchSpools(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/spool", baseUrl: baseUrl) { [weak self] (items: [SpoolManSpool]) in
            self?.spools = items
        }
    }
    
    func fetchFilaments(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/filament", baseUrl: baseUrl) { [weak self] (items: [SpoolManFilament]) in
            self?.filaments = items
        }
    }
    
    func fetchVendors(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/vendor", baseUrl: baseUrl) { [weak self] (items: [SpoolManVendor]) in
            self?.vendors = items
        }
    }
    
    func testConnection(baseUrl: String) async -> Bool {
        do {
            let _: [SpoolManVendor] = try await sendRequest(method: "GET", endpoint: "/api/v1/vendor", baseUrl: baseUrl)
            return true
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
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
                throw NSError(domain: "SpoolManError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            } else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                throw NSError(domain: "SpoolManError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error \(httpResponse.statusCode): \(bodyString)"])
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
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // Vendors
    func addVendor(name: String, baseUrl: String) async -> SpoolManVendor? {
        do {
            let newVendor: SpoolManVendor = try await sendRequest(method: "POST", endpoint: "/api/v1/vendor", baseUrl: baseUrl, body: ["name": name])
            DispatchQueue.main.async {
                self.vendors.append(newVendor)
            }
            return newVendor
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return nil
        }
    }
    
    func updateVendor(id: Int, name: String, baseUrl: String) async {
        do {
            let updatedVendor: SpoolManVendor = try await sendRequest(method: "PATCH", endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl, body: ["name": name])
            DispatchQueue.main.async {
                if let index = self.vendors.firstIndex(where: { $0.id == id }) {
                    self.vendors[index] = updatedVendor
                }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    func deleteVendor(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl)
            DispatchQueue.main.async {
                self.vendors.removeAll { $0.id == id }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    // Filaments
    func addFilament(name: String?, vendorId: Int?, material: String?, colorHex: String?, density: Double?, diameter: Double?, extruderTemp: Int?, bedTemp: Int?, baseUrl: String) async -> SpoolManFilament? {
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
            let newFilament: SpoolManFilament = try await sendRequest(method: "POST", endpoint: "/api/v1/filament", baseUrl: baseUrl, body: body)
            DispatchQueue.main.async {
                self.filaments.append(newFilament)
            }
            return newFilament
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
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
            let updatedFilament: SpoolManFilament = try await sendRequest(method: "PATCH", endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl, body: body)
            DispatchQueue.main.async {
                if let index = self.filaments.firstIndex(where: { $0.id == id }) {
                    self.filaments[index] = updatedFilament
                }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    func deleteFilament(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl)
            DispatchQueue.main.async {
                self.filaments.removeAll { $0.id == id }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    // Spools
    func addSpool(filamentId: Int, remainingWeight: Double?, initialWeight: Double?, spoolWeight: Double?, usedWeight: Double?, price: Double?, baseUrl: String) async -> SpoolManSpool? {
        var body: [String: Any] = ["filament_id": filamentId]
        if let remainingWeight = remainingWeight { body["remaining_weight"] = remainingWeight }
        if let initialWeight = initialWeight { body["initial_weight"] = initialWeight }
        if let spoolWeight = spoolWeight { body["spool_weight"] = spoolWeight }
        if let usedWeight = usedWeight { body["used_weight"] = usedWeight }
        if let price = price { body["price"] = price }
        
        do {
            let newSpool: SpoolManSpool = try await sendRequest(method: "POST", endpoint: "/api/v1/spool", baseUrl: baseUrl, body: body)
            DispatchQueue.main.async {
                self.spools.append(newSpool)
            }
            return newSpool
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return nil
        }
    }
    
    func updateSpool(id: Int, filamentId: Int?, remainingWeight: Double?, initialWeight: Double?, spoolWeight: Double?, usedWeight: Double?, price: Double?, baseUrl: String) async {
        var body: [String: Any] = [:]
        if let filamentId = filamentId { body["filament_id"] = filamentId }
        if let remainingWeight = remainingWeight { body["remaining_weight"] = remainingWeight }
        if let initialWeight = initialWeight { body["initial_weight"] = initialWeight }
        if let spoolWeight = spoolWeight { body["spool_weight"] = spoolWeight }
        if let usedWeight = usedWeight { body["used_weight"] = usedWeight }
        if let price = price { body["price"] = price }
        
        do {
            let updatedSpool: SpoolManSpool = try await sendRequest(method: "PATCH", endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl, body: body)
            DispatchQueue.main.async {
                if let index = self.spools.firstIndex(where: { $0.id == id }) {
                    self.spools[index] = updatedSpool
                }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    func deleteSpool(id: Int, baseUrl: String) async {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl)
            DispatchQueue.main.async {
                self.spools.removeAll { $0.id == id }
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }
    
    private func fetchData<T: Decodable>(endpoint: String, baseUrl: String, completion: @escaping ([T]) -> Void) async {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let decodedItems = try JSONDecoder().decode([T].self, from: data)
            
            DispatchQueue.main.async {
                completion(decodedItems)
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
