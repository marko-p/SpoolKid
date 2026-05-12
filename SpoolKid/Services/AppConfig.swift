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
        visibilityNFCOpenTag3DSubtypeKey: true,
        visibilityNFCOpenTag3DNameKey: true
    ]

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
    
    static let brands = ["Prusament", "Polymaker", "eSun", "Sunlu", "Elegoo", "Hatchbox", "Overture", "Eryone", "Amolen", "MatterHackers", "Proto-pasta", "ColorFabb", "Generic"]
    
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
}
