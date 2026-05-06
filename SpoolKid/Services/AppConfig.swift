//
//  AppConfig.swift
//  SpoolKid
//
//  Created by Marko on 12/30/25.
//
//  Purpose: Central configuration file for the application.
//  Contains:
//  - Storage keys for UserDefaults/AppStorage
//  - Default values for new tags/spools
//  - Predefined lists of Materials and Brands
//  - Temperature presets for different materials
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct AppConfig {
    static let spoolmanUrlKey = "spoolman_url"
    static let defaultSpoolmanUrl = ""
    
    // Authentication & Security
    static let authTypeKey = "spoolman_auth_type"            // "none", "basic", "bearer"
    static let trustAllCertsKey = "spoolman_trust_all_certs" // Bool
    static let authUsernameKey = "spoolman_auth_username"    // String
    static let authPasswordKey = "spoolman_auth_password"    // String
    static let authTokenKey    = "spoolman_auth_token"       // String
    
    // NFC Tag Format
    static let nfcTagFormatKey = "nfc_tag_format"            // TagFormat.rawValue
    
    // Onboarding
    static let hasCompletedWelcomeKey = "has_completed_welcome" // Bool
    
    // Reset
    static let resetAppDataKey = "reset_app_data"              // Bool

    // MARK: - Tag Matching & UID Persistence

    /// Whether to persist a scanned card UID back to the matched spool's lot_nr in Spoolman.
    static let spoolmanPersistCardUIDKey = "spoolman_persist_card_uid"      // Bool, default false
    
    static let materialPresets: [String: (extruder: Int, bed: Int)] = [
        "PLA": (210, 50),
        "PLA+": (215, 60),
        "ABS": (250, 100),
        "ABS+": (245, 90),
        "ABS-T": (245, 95),
        "PETG": (235, 80),
        "PCTG": (240, 85),
        "Nylon": (250, 80),
        "Flexible (TPU)": (220, 50),
        "Flexible (TPE 32D)": (230, 50),
        "Flexible (TPE 88A)": (230, 50),
        "Polycarbonate (PC)": (270, 110),
        "PC/ABS": (270, 100),
        "PC/PBT": (270, 110),
        "HIPS": (240, 110),
        "ASA": (250, 100),
        "Polypropylene (PP)": (240, 100),
        "PVA": (200, 60),
        "PVB": (215, 75),
        "Wood": (205, 60),
        "Carbon Fiber": (240, 70),
        "Acetal (POM)": (220, 110),
        "PMMA": (245, 100),
        "Semi flexible (FPE)": (235, 80),
        "PVDF": (250, 100),
        "PEI (Ultem)": (375, 150),
        "PEKK": (370, 130),
        "PEEK": (390, 140),
        "PPSU": (380, 140),
        "BIOFUSION": (218, 65),
        "GREENTEC": (220, 60),
        "FLAX": (210, 60),
        "PEARL": (215, 60)
    ]
    
    static var materials: [String] {
        materialPresets.keys.sorted()
    }
    
    static let brands = ["Prusament", "Polymaker", "eSun", "Sunlu", "Bambu Lab", "Hatchbox", "Overture", "Eryone", "Amolen", "MatterHackers", "Proto-pasta", "ColorFabb", "Generic"]
    
    static let subtypes = ["Basic", "Rapid", "HF", "Silk", "Matte", "Glossy", "Translucent", "Transparent", "Glitter", "Glow", "Carbon Fiber", "Wood", "Flexible", "Semi Flexible", "Support", "PVA"]
    
    struct Defaults {
        static let colorHex = "000000"
        static let density = 1.24
        static let diameter = 1.75
        static let extruderTemp = 205
        static let bedTemp = 60
        static let material = "PLA"
        static let brand = "Generic"
        static let subtype = ""
        static let minNozzleTemp = 190
        static let maxNozzleTemp = 220
        static let minBedTemp = 50
        static let maxBedTemp = 70
        
        // Offsets applied when deriving min/max temps from a single Spoolman temp value
        static let nozzleTempOffset = 10
        static let bedTempOffset = 5
    }
    
    // MARK: - Snapmaker U1 Compatibility
    
    /// Material types supported by the Snapmaker U1 printer (from printtag-web).
    static let snapmakerU1Materials: [String] = [
        "PLA", "PETG", "ABS", "ASA", "TPU", "PA", "PA12",
        "PC", "PEEK", "PVA", "HIPS", "PCTG",
        "PLA-CF", "PETG-CF", "PA-CF"
    ]
    
    /// Maps Spoolman/SpoolKid material names to Snapmaker U1 compatible equivalents.
    /// Only materials that need remapping are listed; direct matches are handled separately.
    static let snapmakerU1MaterialMapping: [String: String] = [
        // PLA variants
        "PLA+": "PLA",
        // ABS variants
        "ABS+": "ABS",
        "ABS-T": "ABS",
        // Nylon -> PA
        "Nylon": "PA",
        // Flexible -> TPU
        "Flexible (TPU)": "TPU",
        "Flexible (TPE 32D)": "TPU",
        "Flexible (TPE 88A)": "TPU",
        "Semi flexible (FPE)": "TPU",
        // PC variants
        "Polycarbonate (PC)": "PC",
        "PC/ABS": "PC",
        "PC/PBT": "PC",
        // Carbon fiber (generic) -> PLA-CF as most common CF filament
        "Carbon Fiber": "PLA-CF",
    ]
    
    /// Attempts to map a material type to a Snapmaker U1 compatible type.
    /// Returns the original if already compatible, mapped value if a mapping exists,
    /// or nil if no mapping is possible (user must choose manually).
    static func resolveSnapmakerU1Material(_ material: String) -> String? {
        // Case-insensitive check against known U1 materials
        if snapmakerU1Materials.contains(where: { $0.caseInsensitiveCompare(material) == .orderedSame }) {
            // Return the canonical casing from the U1 list
            return snapmakerU1Materials.first(where: { $0.caseInsensitiveCompare(material) == .orderedSame })
        }
        // Check mapping table (case-insensitive keys)
        if let mapped = snapmakerU1MaterialMapping.first(where: { $0.key.caseInsensitiveCompare(material) == .orderedSame })?.value {
            return mapped
        }
        return nil
    }
}
