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

import Foundation

struct AppConfig {
    static let spoolmanUrlKey = "spoolman_url"
    static let defaultSpoolmanUrl = "http://[YOUR_SPOOLMAN_IP]:7912"
    
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
    
    struct Defaults {
        static let colorHex = "000000"
        static let density = 1.24
        static let diameter = 1.75
        static let extruderTemp = 205
        static let bedTemp = 60
        static let material = "PLA"
        static let brand = "Generic"
        static let minNozzleTemp = 190
        static let maxNozzleTemp = 220
        static let minBedTemp = 50
        static let maxBedTemp = 70
    }
}
