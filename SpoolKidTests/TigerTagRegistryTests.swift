//
//  TigerTagRegistryTests.swift
//  SpoolKidTests
//
//  The registry is the seam between SpoolKid's free-text material and brand
//  fields and TigerTag's numeric protocol IDs. The FilaManDB fixtures below
//  are the measured snapshot (2026-09-16, paginated /api/v1) that motivated
//  the alias tables: every name but PIPG must resolve to a real ID.
//

import Testing
import Foundation
import CryptoKit
@testable import SpoolKid

struct TigerTagRegistryTests {

    // MARK: - Normalization

    @Test func normalizationFoldsCasePunctuationAndWhitespace() {
        // Punctuation becomes a separator: PLA+/Pro is the two words PLA+ and Pro.
        #expect(TigerTagRegistry.normalize("  PLA+/Pro ") == "pla+ pro")
        #expect(TigerTagRegistry.normalize("HT-PLA") == "ht pla")
        #expect(TigerTagRegistry.normalize("PA (Nylon)") == "pa nylon")
        #expect(TigerTagRegistry.normalize("eSun\tPLA") == "esun pla")
    }

    // MARK: - Direct matches

    @Test func resolvesDirectMaterialAndBrand() {
        let material = TigerTagRegistry.materialID(for: "PLA")
        #expect(material.id == 38219)
        #expect(material.label == "PLA")
        #expect(material.kind == .exact)

        let caseInsensitive = TigerTagRegistry.materialID(for: "pla")
        #expect(caseInsensitive.id == 38219)

        let esun = TigerTagRegistry.brandID(for: "eSun")
        // Registry JSON is normative: eSun is 47930 (the spec README's hex
        // examples carry arithmetic typos — 48026 among them).
        #expect(esun.id == 47930)
        #expect(esun.kind == .exact)
    }

    // MARK: - Alias table

    @Test func resolvesFilaManDBNamesThroughAliases() {
        #expect(TigerTagRegistry.materialID(for: "PLA+/Pro").id == TigerTagRegistry.materialID(for: "PLA+").id)
        #expect(TigerTagRegistry.materialID(for: "PLA+/Pro").kind == .aliased)
        #expect(TigerTagRegistry.materialID(for: "HT-PLA").id == TigerTagRegistry.materialID(for: "PLA").id)
        #expect(TigerTagRegistry.materialID(for: "TPU-95A").id == TigerTagRegistry.materialID(for: "TPU").id)
        #expect(TigerTagRegistry.materialID(for: "PCABS").id == TigerTagRegistry.materialID(for: "PC-ABS").id)
        #expect(TigerTagRegistry.materialID(for: "CPE").id == TigerTagRegistry.materialID(for: "CoPE").id)
        #expect(TigerTagRegistry.materialID(for: "PCPBT").id == TigerTagRegistry.materialID(for: "PC-PBT").id)
        #expect(TigerTagRegistry.materialID(for: "WOOD").id == TigerTagRegistry.materialID(for: "PLA Wood").id)
        #expect(TigerTagRegistry.brandID(for: "Protopasta").label == "Proto-Pasta")
        #expect(TigerTagRegistry.brandID(for: "Protopasta").kind == .aliased)
    }

    /// Every alias target must exist in the embedded registry — an alias
    /// pointing at a renamed label would silently fall back.
    @Test func everyAliasTargetExistsInTheRegistry() {
        for (key, target) in TigerTagRegistry.materialAliases {
            #expect(TigerTagRegistry.materialID(for: target).kind != .fallback,
                    "alias '\(key)' -> '\(target)' missing from registry")
        }
        for (key, target) in TigerTagRegistry.brandAliases {
            #expect(TigerTagRegistry.brandID(for: target).kind != .fallback,
                    "brand alias '\(key)' -> '\(target)' missing from registry")
        }
    }

    // MARK: - FilaManDB total coverage

    @Test func everyFilaManDBMaterialNameResolves() {
        let unresolved = filaManDBMaterialNames.filter {
            TigerTagRegistry.materialID(for: $0).kind == .fallback
        }
        // PIPG is the one honest fallback; anything else is a mapping gap.
        #expect(unresolved == ["PIPG"])
    }

    @Test func everyFilaManDBBrandNameResolvesToSomeID() {
        for name in filaManDBBrandNames {
            _ = TigerTagRegistry.brandID(for: name).id // must not trap; fallback is valid
        }
    }

    // MARK: - Fallback

    @Test func unknownNamesFallBackToUndefinedIDs() {
        let material = TigerTagRegistry.materialID(for: "Mike's Exotic Blend")
        #expect(material.id == 0xFFFF)
        #expect(material.kind == .fallback)
        let brand = TigerTagRegistry.brandID(for: "Mike's Filaments")
        #expect(brand.id == 0xFFFF)
        #expect(brand.label == "Generic")
    }

    // MARK: - Reverse lookups + helpers

    @Test func reverseLookups() {
        #expect(TigerTagRegistry.materialLabel(forID: 38219) == "PLA")
        #expect(TigerTagRegistry.brandLabel(forID: 0xFFFF) == "Generic")
        #expect(TigerTagRegistry.diameterMM(forID: 56) == 1.75)
        #expect(TigerTagRegistry.diameterMM(forID: 221) == 2.85)
        #expect(TigerTagRegistry.diameterMM(forID: 0) == nil)
        #expect(TigerTagRegistry.materialDensity(forID: 38219) != nil)
    }

    @Test func densityByMaterialName() {
        #expect(TigerTagRegistry.materialDensity(for: "PETG") == 1.27)
        #expect(TigerTagRegistry.materialDensity(for: "abs") == 1.04)
        // Through the alias table, like a TigerTag write resolves it.
        #expect(TigerTagRegistry.materialDensity(for: "PETG+") == 1.27)
        // Unknown name: the registry's "None" row is not a density.
        #expect(TigerTagRegistry.materialDensity(for: "Mike's Exotic Blend") == nil)
        // The registry states 0 for some rows; zero is not a measurement.
        #expect(TigerTagRegistry.materialDensity(for: "Biopolymer") == nil)
    }

    /// The curated material presets seed density from the registry, so every
    /// preset resolves unless it is ambiguous on purpose — those seed PLA's
    /// default instead of guessing a base polymer. Vocabulary-only menu names
    /// (no preset) may fall back, shown by the orange TigerTag caption.
    @Test func everyFormMenuMaterialResolvesUnlessAmbiguous() {
        let ambiguous: Set<String> = ["ABS-T", "Carbon Fiber", "Semi flexible (FPE)", "PEI (Ultem)"]
        for material in AppConfig.materialPresets.keys where !ambiguous.contains(material) {
            #expect(TigerTagRegistry.materialID(for: material).kind != .fallback,
                    "\(material) does not resolve")
        }
    }

    @Test func subtypeSplitsIntoAtMostTwoAspects() {
        let both = TigerTagRegistry.aspects(forSubtype: "Silk Bicolor")
        #expect(TigerTagRegistry.subtypeLabel(aspect1: both.aspect1, aspect2: both.aspect2) == "Silk Bicolor")
        let one = TigerTagRegistry.aspects(forSubtype: "Silk")
        #expect(one.aspect1 != 0 && one.aspect2 == 0)
        let unknownWordsIgnored = TigerTagRegistry.aspects(forSubtype: "Super Silk")
        #expect(unknownWordsIgnored.aspect1 == TigerTagRegistry.aspects(forSubtype: "Silk").aspect1)
    }

    @Test func captionsStateWhatWillBeWritten() {
        let exact = TigerTagRegistry.materialID(for: "PLA")
        #expect(TigerTagRegistry.caption(for: exact, undefinedLabel: "None") == "→ PLA (38219)")
        let aliased = TigerTagRegistry.materialID(for: "PLA+/Pro")
        #expect(TigerTagRegistry.caption(for: aliased, undefinedLabel: "None").hasPrefix("→ PLA+ ("))
        #expect(TigerTagRegistry.caption(for: aliased, undefinedLabel: "None").hasSuffix("via alias)"))
        let fallback = TigerTagRegistry.brandID(for: "Nonexistent Brand")
        #expect(TigerTagRegistry.caption(for: fallback, undefinedLabel: "Generic")
                == "Not in the TigerTag registry — writes as Generic (65535)")
    }

    // MARK: - Public key (signature verification consumes this)

    @Test func publicKeyParses() throws {
        let key = try #require(TigerTagRegistry.publicKey())
        #expect(key.rawRepresentation.count == 64) // P-256 X‖Y, no prefix
    }

    // MARK: - FilaManDB fixture (fetched 2026-09-16, /api/v1 paginated)

    private let filaManDBMaterialNames: [String] = [
        "ABS", "ABS+", "ABS+GF20", "ABS-GF", "APLA", "ASA", "ASA+", "ASA-CF",
        "ASA-GF", "BIOFUSION", "BVOH", "CF", "CoPA", "CPE", "FLAX", "GREENTEC",
        "GREENTEC-CF", "HIPS", "HT-PLA", "PA (Nylon)", "PA-CF", "PA12", "PA12-CF",
        "PA6", "PA6-CF", "PA6-GF", "PA612", "PAHT", "PAHT-CF", "PBT", "PC",
        "PC+ABS", "PC-ABS", "PC-CF", "PC-PBT", "PCABS", "PCPBT", "PCPBT-CF",
        "PCTG", "PE", "PEARL", "PEBA", "PEEK", "PET", "PET-CF", "PETG", "PETG+",
        "PETG-CF", "PETG-CF10", "PHA", "PIPG", "PLA", "PLA+", "PLA+/Pro",
        "PLA+WOOD", "PLA-CF", "PMMA", "PP", "PPA", "PPS", "PPS-CF", "PVA", "PVB",
        "PVDF", "PVDF+GRAPHENE", "SBS", "SMP", "TPE", "TPU", "TPU-55D", "TPU-85A",
        "TPU-90A", "TPU-95A", "TPU-CF", "WOOD",
    ]

    private let filaManDBBrandNames: [String] = [
        "123-3D", "3D Fillies", "3D Printing Canada", "Add:north", "Amazon Basics",
        "AMZ3D", "Amolen", "Ankermake", "Anycubic", "AzureFilm", "Bambu Lab", "Bambulab",
        "BBLife", "CC3D", "Coex", "COEX", "ColorFabb", "Comgrow", "Creality",
        "Devil Design", "eSUN", "ELEGOO", "Eryone", "Extrudr", "Fiberon", "Fillamentum",
        "FlashForge", "FormFutura", "Geeetech", "Generic", "Hatchbox", "IC3D", "iSanmate",
        "Inland", "Jayo", "kexcelled", "Kingroon", "Landu", "Nobufil", "Overture",
        "PanChroma", "Polymaker", "PolyTerra", "Protopasta", "R3D", "Recreus", "Rosa3D",
        "SainSmart", "Siddament", "Sunlu", "SUNLU", "Ziro", "Zyltech",
    ]
}
