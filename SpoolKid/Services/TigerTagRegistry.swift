//
//  TigerTagRegistry.swift
//  SpoolKid
//
//  Purpose: Resolves TigerTag protocol IDs (material, brand, aspect, diameter)
//  against the reference tables shipped with the spec, in both directions.
//  FilaManDB names resolve through the alias tables; anything else falls back
//  to the protocol's reserved undefined IDs (0xFFFF = material "None" /
//  brand "Generic"), so a write never fails for want of an ID.
//
//  Tables: CC0 from github.com/TigerTag-Project/TigerTag-RFID-Guide (v2.1),
//  fetched 2026-09-16. They move slowly; updates ride app updates.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CryptoKit
import os.log

enum TigerTagRegistry {

    static let undefinedMaterialID: UInt16 = 0xFFFF   // registry label "None"
    static let undefinedBrandID: UInt16 = 0xFFFF      // registry label "Generic"

    struct IDResolution: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable { case exact, aliased, fallback }
        let id: UInt16
        let label: String
        let kind: Kind
    }

    // MARK: - Embedded tables (lazy, parsed once)

    private struct MaterialRecord: Sendable {
        let label: String
        let density: Double?
    }

    private static let materials: [UInt16: MaterialRecord] = load("id_material") { json in
        var result: [UInt16: MaterialRecord] = [:]
        for entry in json {
            result[UInt16(truncatingIfNeeded: entry["id"] as? Int ?? 0)] =
                MaterialRecord(label: entry["label"] as? String ?? "",
                               density: entry["density"] as? Double)
        }
        return result
    }

    private static let brands: [UInt16: String] = load("id_brand") { json in
        var result: [UInt16: String] = [:]
        for entry in json {
            result[UInt16(truncatingIfNeeded: entry["id"] as? Int ?? 0)] = entry["name"] as? String ?? ""
        }
        return result
    }

    private static let aspects: [UInt8: String] = load("id_aspect") { json in
        var result: [UInt8: String] = [:]
        for entry in json {
            result[UInt8(truncatingIfNeeded: entry["id"] as? Int ?? 0)] = entry["label"] as? String ?? ""
        }
        return result
    }

    private static let diameters: [UInt8: Double] = load("id_diameter") { json in
        var result: [UInt8: Double] = [:]
        for entry in json {
            result[UInt8(truncatingIfNeeded: entry["id"] as? Int ?? 0)] =
                Double(entry["label"] as? String ?? "")
        }
        return result
    }

    /// Public keys per ID TigerTag, keyed by the u32 magic. All current
    /// variants share one key; keyed by magic so a future variant can differ.
    private static let publicKeys: [UInt32: String] = load("id_version") { json in
        var result: [UInt32: String] = [:]
        for entry in json {
            guard let pem = entry["public_key"] as? String, !pem.isEmpty else { continue }
            result[UInt32(truncatingIfNeeded: entry["id"] as? Int ?? 0)] = pem
        }
        return result
    }

    private static func load<T>(_ resource: String, _ transform: @escaping ([[String: Any]]) -> T) -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            Logger(subsystem: "com.spoolkid", category: "TigerTagRegistry")
                .error("TigerTag registry table missing: \(resource, privacy: .public)")
            // An empty table still writes valid (undefined) IDs — the test
            // suite is what makes sure it never ships that way.
            return transform([])
        }
        return transform(json)
    }

    // MARK: - Aliases (FilaManDB names measured 2026-09-16, plus the filament
    // form's material menu; keys are normalized)

    static let materialAliases: [String: String] = [
        "abs+": "ABS",
        "abs+gf20": "ABS-CF",
        "acetal pom": "POM",
        "apla": "PLA",
        "biofusion": "PLA",
        "cf": "PA-CF",
        "copa": "PA",
        "cpe": "CoPE",
        "flax": "PLA",
        "flexible tpe 32d": "TPE",
        "flexible tpe 88a": "TPE",
        "flexible tpu": "TPU",
        "greentec": "PLA",
        "greentec cf": "PLA-CF",
        "ht pla": "PLA",
        "nylon": "PA",
        "pa nylon": "PA",
        "pa612": "PA",
        "pc+abs": "PC-ABS",
        "pcabs": "PC-ABS",
        "pcpbt": "PC-PBT",
        "pcpbt cf": "PC-PBT-CF",
        "pearl": "PLA",
        "petg+": "PETG",
        "petg cf10": "PETG-CF",
        "pla+ pro": "PLA+",
        "pla+wood": "PLA Wood",
        "polycarbonate pc": "PC",
        "polypropylene pp": "PP",
        "pvdf+graphene": "PVDF",
        "smp": "TPU",
        "tpu 55d": "TPU",
        "tpu 85a": "TPU",
        "tpu 90a": "TPU",
        "tpu 95a": "TPU",
        "tpu cf": "TPU-GF",
        "wood": "PLA Wood",
    ]

    // Exact renames only. PolyTerra deliberately stays unaliased: it is
    // Polymaker's value line, not Polymaker, and the tag would assert a
    // relationship the brand has not made.
    static let brandAliases: [String: String] = [
        "protopasta": "Proto-Pasta",
        "coex": "Coex 3D",
        "bambulab": "Bambu Lab",
    ]

    // MARK: - Normalization

    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased().replacingOccurrences(of: "&", with: "and")
        var kept = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            let isAllowed = scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || scalar == "+")
            kept.append(isAllowed ? scalar : " ")
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Forward resolution

    static func materialID(for name: String) -> IDResolution {
        resolve(name: name, aliases: materialAliases, table: materials.mapValues(\.label),
                fallbackID: undefinedMaterialID)
    }

    static func brandID(for name: String) -> IDResolution {
        resolve(name: name, aliases: brandAliases, table: brands, fallbackID: undefinedBrandID)
    }

    private static func resolve(
        name: String,
        aliases: [String: String],
        table: [UInt16: String],
        fallbackID: UInt16
    ) -> IDResolution {
        let normalized = normalize(name)
        guard !normalized.isEmpty else {
            return IDResolution(id: fallbackID, label: table[fallbackID] ?? "", kind: .fallback)
        }
        for (id, label) in table where normalize(label) == normalized {
            return IDResolution(id: id, label: label, kind: .exact)
        }
        if let target = aliases[normalized] {
            for (id, label) in table where normalize(label) == normalize(target) {
                return IDResolution(id: id, label: label, kind: .aliased)
            }
        }
        return IDResolution(id: fallbackID, label: table[fallbackID] ?? "", kind: .fallback)
    }

    // MARK: - Reverse lookups

    static func materialLabel(forID id: UInt16) -> String? { materials[id]?.label }
    static func brandLabel(forID id: UInt16) -> String? { brands[id] }
    static func materialDensity(forID id: UInt16) -> Double? { materials[id]?.density }
    static func diameterMM(forID id: UInt8) -> Double? { diameters[id] }

    /// The registry's typical density for a free-text material, resolved the
    /// way a TigerTag write resolves it (exact, then alias). Nil when the name
    /// is not in the registry, or its row states no density or a zero.
    static func materialDensity(for name: String) -> Double? {
        let resolution = materialID(for: name)
        guard resolution.kind != .fallback else { return nil }
        return FilamentTagData.statedMeasurement(materialDensity(forID: resolution.id))
    }

    // MARK: - Aspects (subtype words)

    static func aspects(forSubtype subtype: String) -> (aspect1: UInt8, aspect2: UInt8) {
        var first: UInt8 = 0
        var second: UInt8 = 0
        for word in subtype.split(separator: " ") {
            let normalized = normalize(String(word))
            guard let id = aspects.first(where: { normalize($0.value) == normalized })?.key,
                  id != 0 else { continue }  // 0 is "-" (none)
            if first == 0 {
                first = id
            } else if second == 0 && id != first {
                second = id
            }
        }
        return (first, second)
    }

    static func subtypeLabel(aspect1: UInt8, aspect2: UInt8) -> String? {
        let labels = [aspect1, aspect2].compactMap { id -> String? in
            guard id != 0, let label = aspects[id], label != "-" else { return nil }
            return label
        }
        return labels.isEmpty ? nil : labels.joined(separator: " ")
    }

    // MARK: - Picker entries

    static var allMaterials: [IDResolution] {
        materials.map { IDResolution(id: $0.key, label: $0.value.label, kind: .exact) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static var allBrands: [IDResolution] {
        brands.map { IDResolution(id: $0.key, label: $0.value, kind: .exact) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    // MARK: - Write-form caption (pure — the view only renders it)

    static func caption(for resolution: IDResolution, undefinedLabel: String) -> String {
        switch resolution.kind {
        case .exact:
            return "→ \(resolution.label) (\(resolution.id))"
        case .aliased:
            return "→ \(resolution.label) (\(resolution.id) · via alias)"
        case .fallback:
            return "Not in the TigerTag registry — writes as \(undefinedLabel) (\(resolution.id))"
        }
    }

    // MARK: - Signature public key

    /// The protocol's ECDSA public key for a tag variant, taken straight
    /// from id_version.json — CryptoKit parses the PEM (SPKI) directly.
    static func publicKey(forVariantMagic magic: UInt32 = 0x5BF5_9264) -> P256.Signing.PublicKey? {
        guard let pem = publicKeys[magic] ?? publicKeys[0x5BF5_9264] else { return nil }
        return try? P256.Signing.PublicKey(pemRepresentation: pem)
    }
}
