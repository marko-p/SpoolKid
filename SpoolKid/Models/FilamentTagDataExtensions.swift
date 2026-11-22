//
//  FilamentTagDataExtensions.swift
//  SpoolKid
//
//  Purpose: Extensions on FilamentTagData and Color for hex string conversion.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

extension FilamentTagData {
    /// This data with an `SM<id>` name read as the spool ID it names, as
    /// `AnycubicACEPayload` reads a scanned tag's SKU. Write Tag records an ACE
    /// write with its SKU in `name` and no `spoolmanId`, so a Recent Tag kept
    /// its spool ID where the stale-ID check never looked. An ID already
    /// present wins, and any other name stays a name.
    func readingSpoolLinkSKU() -> FilamentTagData {
        guard spoolmanId == nil, let name, let spoolID = SpoolLinkSKU.spoolID(fromSKU: name) else { return self }
        var read = self
        read.spoolmanId = spoolID
        read.name = nil
        return read
    }

    /// The label the scan UI headlines this tag data with: the name the tag
    /// states, or the brand+material construct for formats that carry no name
    /// (ELEGOO; Anycubic without a SKU) — the same label the recent-tags list
    /// has always shown. "Unknown Filament" only when nothing names it.
    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let constructed = "\(brand) \(material)".trimmingCharacters(in: .whitespacesAndNewlines)
        return constructed.isEmpty ? "Unknown Filament" : constructed
    }

    /// The two text lines the scan cards render for this data. With
    /// `nameBelowDescriptor` (formats whose `name` is a machine label — the
    /// Anycubic SKU) the readable brand•material(•subtype) construct headlines
    /// and the raw name renders under it in smaller type. A whitespace-only
    /// name is absent, exactly as `displayName` treats it.
    func displayLabels(nameBelowDescriptor: Bool) -> (headline: String, secondary: String?) {
        let descriptor = [brand, material, subtype ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        if nameBelowDescriptor {
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (descriptor, trimmedName.isEmpty ? nil : trimmedName)
        }
        return (displayName, descriptor)
    }
    
    /// Creates a `FilamentTagData` from a Spoolman spool, deriving min/max temps
    /// from the single Spoolman temperature values using configured offsets.
    ///
    /// Carries the spool's ID so the write screen knows whose tag it writes;
    /// `WriteTagFormAssembler` decides whether the ID reaches the tag.
    ///
    /// The spool's own weights win over its filament's, and what the spool has
    /// used becomes `consumedWeight`, so a printer that counts down from the
    /// tag starts from what is left. Only OpenPrintTag writes it.
    static func from(spool: Spool) -> FilamentTagData {
        var tagData = from(filament: spool.filament)
        tagData.spoolmanId = spool.id
        tagData.nominalNetWeight = statedMeasurement(spool.initialWeight) ?? tagData.nominalNetWeight
        tagData.emptyContainerWeight = statedMeasurement(spool.spoolWeight) ?? tagData.emptyContainerWeight
        tagData.consumedWeight = consumption(fullWeight: tagData.nominalNetWeight, remaining: spool.remainingWeight)
        return tagData
    }

    /// Creates a `FilamentTagData` from a backend filament, deriving min/max
    /// temps from the single stored temperature values using configured
    /// offsets. One field mapping for both spool- and filament-derived data.
    static func from(filament: Filament) -> FilamentTagData {
        let colors = filament.colors
        var minNozzle = AppConfig.Defaults.minNozzleTemp
        var maxNozzle = AppConfig.Defaults.maxNozzleTemp
        if let t = filament.settingsExtruderTemp {
            minNozzle = t
            maxNozzle = t + AppConfig.Defaults.nozzleTempOffset
        }
        
        var minBed = AppConfig.Defaults.minBedTemp
        var maxBed = AppConfig.Defaults.maxBedTemp
        if let t = filament.settingsBedTemp {
            minBed = t
            maxBed = t + AppConfig.Defaults.bedTempOffset
        }
        
        return FilamentTagData(
            name: filament.name,
            material: filament.material ?? AppConfig.Defaults.material,
            subtype: filament.name.map { SubtypeOptionService.derive(from: $0) },
            brand: filament.vendor?.name ?? AppConfig.Defaults.brand,
            colorHex: colors.primaryHex ?? AppConfig.Defaults.colorHex,
            additionalColorHexes: colors.isMulti ? Array(colors.hexes.dropFirst()) : nil,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil,
            density: filament.density,
            diameter: statedMeasurement(filament.diameter),
            transmissionDistance: filament.transmissionDistance,
            nominalNetWeight: statedMeasurement(filament.weight),
            emptyContainerWeight: statedMeasurement(filament.spoolWeight)
        )
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        let length = hexSanitized.count

        if length == 8 {
            let rgbHex = String(hexSanitized.prefix(6))
            let alphaHex = String(hexSanitized.suffix(2))
            guard let rgb = ColorMatching.parseHex(rgbHex),
                  let alphaValue = UInt32(alphaHex, radix: 16) else {
                return nil
            }
            let a = CGFloat(alphaValue) / 255.0
            self.init(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), opacity: a)
        } else {
            guard let rgb = ColorMatching.parseHex(hexSanitized) else { return nil }
            self.init(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), opacity: 1.0)
        }
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
