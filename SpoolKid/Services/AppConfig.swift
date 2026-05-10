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

    // MARK: - Spoolman Field Visibility

    static let visibilityVendorNameKey = "visibility_vendor_name"
    static let visibilityVendorCommentKey = "visibility_vendor_comment"
    static let visibilityVendorEmptySpoolWeightKey = "visibility_vendor_empty_spool_weight"
    static let visibilityVendorExternalIdKey = "visibility_vendor_external_id"
    static let visibilityVendorExtraKey = "visibility_vendor_extra"

    static let visibilityFilamentPriceKey = "visibility_filament_price"
    static let visibilityFilamentWeightKey = "visibility_filament_weight"
    static let visibilityFilamentSpoolWeightKey = "visibility_filament_spool_weight"
    static let visibilityFilamentArticleNumberKey = "visibility_filament_article_number"
    static let visibilityFilamentCommentKey = "visibility_filament_comment"
    static let visibilityFilamentMultiColorHexesKey = "visibility_filament_multi_color_hexes"
    static let visibilityFilamentMultiColorDirectionKey = "visibility_filament_multi_color_direction"
    static let visibilityFilamentExternalIdKey = "visibility_filament_external_id"
    static let visibilityFilamentExtraKey = "visibility_filament_extra"

    static let visibilitySpoolUsedWeightKey = "visibility_spool_used_weight"
    static let visibilitySpoolCommentKey = "visibility_spool_comment"
    static let visibilitySpoolArchivedKey = "visibility_spool_archived"
    static let visibilitySpoolFirstUsedKey = "visibility_spool_first_used"
    static let visibilitySpoolLastUsedKey = "visibility_spool_last_used"
    static let visibilitySpoolExtraKey = "visibility_spool_extra"

    static let visibilityNFCOpenSpoolNameKey = "visibility_nfc_opensp_name"
    static let visibilityNFCOpenSpoolSubtypeKey = "visibility_nfc_opensp_subtype"
    static let visibilityNFCOpenSpoolSpoolIDKey = "visibility_nfc_opensp_spool_id"
    static let visibilityNFCOpenPrintTagSpoolIDKey = "visibility_nfc_opt_spool_id"
    static let visibilityNFCOpenPrintTagDensityKey = "visibility_nfc_opt_density"
    static let visibilityNFCOpenPrintTagTransmissionDistanceKey = "visibility_nfc_opt_transmission_distance"
    static let visibilityNFCOpenPrintTagMaterialTypeKey = "visibility_nfc_opt_material_type"
    static let visibilityNFCOpenPrintTagGTINKey = "visibility_nfc_opt_gtin"
    static let visibilityNFCOpenPrintTagManufacturedDateKey = "visibility_nfc_opt_manufactured_date"
    static let visibilityNFCOpenPrintTagCountryOfOriginKey = "visibility_nfc_opt_country_of_origin"
    static let visibilityNFCOpenPrintTagPreheatTempKey = "visibility_nfc_opt_preheat_temp"
    static let visibilityNFCOpenPrintTagDryingTempKey = "visibility_nfc_opt_drying_temp"
    static let visibilityNFCOpenPrintTagDryingTimeKey = "visibility_nfc_opt_drying_time"
    static let visibilityNFCOpenPrintTagNominalWeightKey = "visibility_nfc_opt_nominal_weight"
    static let visibilityNFCOpenPrintTagActualWeightKey = "visibility_nfc_opt_actual_weight"
    static let visibilityNFCOpenPrintTagEmptyContainerWeightKey = "visibility_nfc_opt_empty_container_weight"
    static let visibilityNFCOpenPrintTagTagsKey = "visibility_nfc_opt_tags"
    static let visibilityNFCOpenPrintTagCertificationsKey = "visibility_nfc_opt_certifications"
    static let visibilityNFCOpenPrintTagURLKey = "visibility_nfc_opt_url"
    static let visibilityNFCOpenTag3DSubtypeKey = "visibility_nfc_ot3d_subtype"
    static let visibilityNFCOpenTag3DNameKey = "visibility_nfc_ot3d_name"

    static let fieldVisibilityDefaults: [String: Any] = [
        visibilityVendorNameKey: true,
        visibilityVendorCommentKey: false,
        visibilityVendorEmptySpoolWeightKey: false,
        visibilityVendorExternalIdKey: false,
        visibilityVendorExtraKey: false,
        visibilityFilamentPriceKey: false,
        visibilityFilamentWeightKey: false,
        visibilityFilamentSpoolWeightKey: false,
        visibilityFilamentArticleNumberKey: false,
        visibilityFilamentCommentKey: false,
        visibilityFilamentMultiColorHexesKey: false,
        visibilityFilamentMultiColorDirectionKey: false,
        visibilityFilamentExternalIdKey: false,
        visibilityFilamentExtraKey: false,
        visibilitySpoolUsedWeightKey: false,
        visibilitySpoolCommentKey: false,
        visibilitySpoolArchivedKey: false,
        visibilitySpoolFirstUsedKey: false,
        visibilitySpoolLastUsedKey: false,
        visibilitySpoolExtraKey: false,
        visibilityNFCOpenSpoolNameKey: true,
        visibilityNFCOpenSpoolSubtypeKey: true,
        visibilityNFCOpenSpoolSpoolIDKey: true,
        visibilityNFCOpenPrintTagSpoolIDKey: false,
        visibilityNFCOpenPrintTagDensityKey: false,
        visibilityNFCOpenPrintTagTransmissionDistanceKey: false,
        visibilityNFCOpenPrintTagMaterialTypeKey: false,
        visibilityNFCOpenPrintTagGTINKey: false,
        visibilityNFCOpenPrintTagManufacturedDateKey: false,
        visibilityNFCOpenPrintTagCountryOfOriginKey: false,
        visibilityNFCOpenPrintTagPreheatTempKey: false,
        visibilityNFCOpenPrintTagDryingTempKey: false,
        visibilityNFCOpenPrintTagDryingTimeKey: false,
        visibilityNFCOpenPrintTagNominalWeightKey: false,
        visibilityNFCOpenPrintTagActualWeightKey: false,
        visibilityNFCOpenPrintTagEmptyContainerWeightKey: false,
        visibilityNFCOpenPrintTagTagsKey: false,
        visibilityNFCOpenPrintTagCertificationsKey: false,
        visibilityNFCOpenPrintTagURLKey: false,
        visibilityNFCOpenTag3DSubtypeKey: true,
        visibilityNFCOpenTag3DNameKey: true
    ]

    static let openPrintTagMaterialTypes: [Int: String] = [
        0: "PLA", 1: "PETG", 2: "TPU", 3: "ABS", 4: "ASA", 5: "PC", 6: "PCTG", 7: "PP", 8: "PA6", 9: "PA11",
        10: "PA12", 11: "PA66", 12: "CPE", 13: "TPE", 14: "HIPS", 15: "PHA", 16: "PET", 17: "PEI", 18: "PBT", 19: "PVB",
        20: "PVA", 21: "PEKK", 22: "PEEK", 23: "BVOH", 24: "TPC", 25: "PPS", 26: "PPSU", 27: "PVC", 28: "PEBA", 29: "PVDF",
        30: "PPA", 31: "PCL", 32: "PES", 33: "PMMA", 34: "POM", 35: "PPE", 36: "PS", 37: "PSU", 38: "TPI", 39: "SBS",
        40: "OBC", 41: "EVA"
    ]

    static let openPrintTagMaterialTags: [Int: String] = [
        0: "Filtration Recommended", 1: "Biocompatible", 2: "Antibacterial", 3: "Air Filtering", 4: "Abrasive",
        5: "Foaming", 6: "Self-Extinguishing", 7: "Paramagnetic", 8: "Radiation Shielding", 9: "High Temperature",
        10: "ESD Safe", 11: "Conductive", 12: "Blend", 13: "Water Soluble", 14: "IPA Soluble", 15: "Limonene Soluble",
        16: "Matte", 17: "Silk", 19: "Translucent", 20: "Transparent", 21: "Iridescent", 22: "Pearlescent", 23: "Glitter",
        24: "Glow in the Dark", 25: "Neon (UV)", 26: "Illuminescent Color Change", 27: "Temperature Color Change",
        28: "Gradual Color Change", 29: "Coextruded", 30: "Contains Carbon", 31: "Contains Carbon Fiber",
        32: "Contains Carbon Nano Tubes", 33: "Contains Glass", 34: "Contains Glass Fiber", 35: "Contains Kevlar",
        36: "Contains Stone", 37: "Contains Magnetite", 38: "Organic Material", 39: "Contains Cork", 40: "Contains Wax",
        41: "Contains Wood", 42: "Contains Bamboo", 43: "Contains Pine", 44: "Contains Ceramic", 45: "Contains Boron Carbide",
        46: "Contains Metal", 47: "Contains Bronze", 48: "Contains Iron", 49: "Contains Steel", 50: "Contains Silver",
        51: "Contains Copper", 52: "Contains Aluminium", 53: "Contains Brass", 54: "Contains Tungsten", 55: "Imitates Wood",
        56: "Imitates Metal", 57: "Imitates Marble", 58: "Imitates Stone", 59: "Lithophane", 60: "Recycled",
        61: "Home Compostable", 62: "Industrially Compostable", 63: "Bio-Based", 64: "Low Outgassing", 65: "Without Pigments",
        66: "Contains Algae", 67: "Castable", 68: "Contains PTFE", 69: "Limited Edition", 70: "EMI Shielding",
        71: "High Speed", 72: "Contains Graphene"
    ]

    static let openPrintTagMaterialTagGroups: [(title: String, ids: [Int])] = [
        ("Biological", [0, 1, 2, 3, 61, 62, 63]),
        ("Physical", [4, 5, 6, 7, 8, 9, 71, 67]),
        ("Electrical", [10, 11, 70]),
        ("Chemical", [12, 13, 14, 15, 64]),
        ("Visual & Color", [16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 65]),
        ("Carbon", [30, 31, 32, 72]),
        ("Glass & Kevlar", [33, 34, 35, 68]),
        ("Minerals", [36, 37]),
        ("Organic Materials", [38, 39, 40, 41, 42, 43, 66]),
        ("Ceramic", [44, 45]),
        ("Metals", [46, 47, 48, 49, 50, 51, 52, 53, 54]),
        ("Imitation", [55, 56, 57, 58]),
        ("Other", [59, 60, 69])
    ]

    static let openPrintTagCertifications: [Int: String] = [
        0: "UL 2818 (GREENGUARD)",
        1: "UL 94 V0 (Flame Retardant)",
        2: "UL 2904"
    ]

    static let openPrintTagCertificationGroups: [(title: String, ids: [Int])] = []

    private static let openPrintTagMaterialAliases: [String: Int] = [
        "PLA+": 0,
        "ABS+": 3,
        "ABS-T": 3,
        "FLEXIBLE TPU": 2,
        "FLEXIBLE TPE 32D": 13,
        "FLEXIBLE TPE 88A": 13,
        "SEMI FLEXIBLE FPE": 13,
        "POLYCARBONATE PC": 5,
        "PC ABS": 5,
        "PC PBT": 5,
        "NYLON": 8,
        "PA": 8,
        "PLA-CF": 0,
        "PETG-CF": 1,
        "PA-CF": 8,
        "CARBON FIBER": 0
    ]

    static func openPrintTagMaterialTypeID(for material: String) -> Int? {
        let normalized = normalizedMaterialToken(material)
        guard !normalized.isEmpty else { return nil }

        if let exact = openPrintTagMaterialTypes.first(where: {
            normalizedMaterialToken($0.value) == normalized
        }) {
            return exact.key
        }

        if let alias = openPrintTagMaterialAliases[normalized] {
            return alias
        }

        if normalized.contains("TPU") { return 2 }
        if normalized.contains("TPE") { return 13 }
        if normalized.contains("PETG") { return 1 }
        if normalized.contains("PLA") { return 0 }
        if normalized.contains("ABS") { return 3 }
        if normalized.contains("ASA") { return 4 }
        if normalized.contains("PCTG") { return 6 }
        if normalized.contains("PA12") { return 10 }
        if normalized.contains("PA11") { return 9 }
        if normalized.contains("PA6") || normalized == "PA" || normalized.contains("NYLON") { return 8 }
        if normalized.contains("PC") || normalized.contains("POLYCARBONATE") { return 5 }

        return nil
    }

    static func openPrintTagMaterialName(for material: String) -> String? {
        guard let id = openPrintTagMaterialTypeID(for: material) else { return nil }
        return openPrintTagMaterialTypes[id]
    }

    private static func normalizedMaterialToken(_ raw: String) -> String {
        let upper = raw.uppercased()
        let scalars = upper.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
    
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
