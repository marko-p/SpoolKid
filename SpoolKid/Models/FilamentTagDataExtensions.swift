//
//  FilamentTagDataExtensions.swift
//  SpoolKid
//
//  Purpose: Extensions on FilamentTagData and Color for hex string conversion.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

extension FilamentTagData {
    // Helper to get Color from hex string
    @MainActor
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
    
    /// Creates a `FilamentTagData` from a Spoolman spool, deriving min/max temps
    /// from the single Spoolman temperature values using configured offsets.
    static func from(spool: SpoolmanSpool, writeSpoolId: Bool = true) -> FilamentTagData {
        var minNozzle = AppConfig.Defaults.minNozzleTemp
        var maxNozzle = AppConfig.Defaults.maxNozzleTemp
        if let t = spool.filament.settingsExtruderTemp {
            minNozzle = t
            maxNozzle = t + AppConfig.Defaults.nozzleTempOffset
        }
        
        var minBed = AppConfig.Defaults.minBedTemp
        var maxBed = AppConfig.Defaults.maxBedTemp
        if let t = spool.filament.settingsBedTemp {
            minBed = t
            maxBed = t + AppConfig.Defaults.bedTempOffset
        }
        
        return FilamentTagData(
            name: spool.filament.name,
            material: spool.filament.material ?? AppConfig.Defaults.material,
            brand: spool.filament.vendor?.name ?? AppConfig.Defaults.brand,
            colorHex: spool.filament.colorHex ?? AppConfig.Defaults.colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: writeSpoolId ? spool.id : nil
        )
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
    
    @MainActor
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != Float(1.0) {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
