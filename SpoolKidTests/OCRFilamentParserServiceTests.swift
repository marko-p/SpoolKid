import Testing
@testable import SpoolKid

struct OCRFilamentParserServiceTests {
    @Test func parserExtractsMaterialBrandColorAndTemps() {
        let lines = [
            "Polymaker Fiberon ASA-CF08",
            "Color: Black",
            "Nozzle 250-270C",
            "Bed 90-110C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.material == "ASA")
        #expect(candidate.brand == "Polymaker")
        #expect(candidate.colorHex == "000000")
        #expect(candidate.minNozzleTemp == 250)
        #expect(candidate.maxNozzleTemp == 270)
        #expect(candidate.minBedTemp == 90)
        #expect(candidate.maxBedTemp == 110)
    }

    // Regression: real Anycubic PLA+ label from the OCR archive corpus (scan DC881263…).
    // The OCR text captured both values, but the parser previously missed them — the printing
    // temp because non-temp label text ("Color Black … 330m") followed it, and the diameter
    // because of the "±0.02mm" tolerance (read by OCR as "+0.02mm") between the value and "mm".
    @Test func parserReadsPrintTempAndDiameterFromAnycubicLabel() {
        let lines = [
            "X0027UEIO3",
            "ANYCUBIC PLA Plulien 1kg",
            "ANYCUBIC",
            "PLA+",
            "Diameter",
            "1.75+0.02mm",
            "Printing Temp",
            "190-230°C",
            "Color",
            "Black",
            "Mat weight",
            "1 kg",
            "Langth",
            "330m"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.diameterMM == 1.75)
        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 230)
        #expect(candidate.wasNozzleExplicitlyLabeled == true)
    }

    // Regression: real Anycubic PLA+ label (scan 1ac04b77, 2026-06-28), exact rawLines.
    // OCR read "Length"/"330m" immediately AFTER the "Printing Temp"/"190-230°C" block, so
    // the fixed-width labeled-temp window swept 330 (the filament length in metres, in the
    // 180–450 nozzle domain) into the nozzle range → max 330 instead of 230. Per-block parsing
    // must attribute 330 to its own "Length" label, never to the temperature.
    @Test func parserDoesNotReadFilamentLengthAsNozzleTemp() {
        let lines = [
            "0027UEI03", "ANYCUBIC PLA Plu...Tien 1kg", "New", "AHPLPBK-108",
            "MADE IN CHINA", "ANYCUBIC", "AHPLPBK-108", "PLA+",
            "Dlameter", "Net Weight", "1.75+0.02mm 1 kg",
            "Printing Temp", "190-230°C", "Length", "330m", "Color", "Black"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 230)
        #expect(candidate.wasNozzleExplicitlyLabeled == true)
    }

    // A labeled temperature followed by unrelated label text — including a net weight, which is
    // parsed earlier and consumes its own text range — must still parse. Regression for the bug
    // where the nozzle value window overlapped the already-consumed weight range and was rejected.
    @Test func parserReadsLabeledNozzleTempFollowedByWeight() {
        let lines = ["Generic PLA", "Nozzle 200-220C", "Color Black", "Weight 1kg"]
        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minNozzleTemp == 200)
        #expect(candidate.maxNozzleTemp == 220)
    }

    // Diameter with a tolerance suffix (±/+/-) between the nominal value and "mm".
    @Test func parserReadsDiameterWithToleranceSuffix() {
        let plus = OCRFilamentParserService.parse(lines: ["PLA", "1.75+0.02mm"])
        let pm = OCRFilamentParserService.parse(lines: ["PLA", "1.75 ± 0.02 mm"])

        #expect(plus.diameterMM == 1.75)
        #expect(pm.diameterMM == 1.75)
    }

    @Test func parserReturnsRawLinesEvenWhenNoFieldsDetected() {
        let lines = ["hello world", "random text"]
        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.rawLines == lines)
        #expect(candidate.material == nil)
        #expect(candidate.brand == nil)
    }

    @Test func parserExtractsSerialDiameterAndSingleTemperaturesFromPartialLabels() {
        let lines = [
            "Polymaker PLA",
            "Dia 1.75mm",
            "SN: PMK-12345",
            "Noz 210-230C",
            "Bed 60C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.serialNumber == "PMK-12345")
        #expect(candidate.diameterMM == 1.75)
        #expect(candidate.minNozzleTemp == 210)
        #expect(candidate.maxNozzleTemp == 230)
        #expect(candidate.minBedTemp == 60)
        #expect(candidate.maxBedTemp == 60)
    }

    @Test func parserUsesDomainHeuristicsForUnlabeledTemperatures() {
        let lines = [
            "Generic PLA",
            "190-220C",
            "Build plate 55"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 220)
        #expect(candidate.minBedTemp == 55)
        #expect(candidate.maxBedTemp == 55)
    }

    @Test func parserDoesNotMatchIncidentalMaterialSubstrings() {
        let lines = [
            "Packaging details",
            "Compatible with many printers"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.material == nil)
    }

    @Test func parserDoesNotTreatNozzleSizeAsFilamentDiameter() {
        let lines = [
            "PLA filament",
            "Nozzle 0.4mm",
            "Nozzle 200-220C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.diameterMM == nil)
    }

    @Test func parserAllows120CAsUnlabeledBedHeuristicThreshold() {
        let lines = [
            "Generic spool",
            "200-220C",
            "120C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minNozzleTemp == 200)
        #expect(candidate.maxNozzleTemp == 220)
        #expect(candidate.minBedTemp == 120)
        #expect(candidate.maxBedTemp == 120)
    }

    @Test func parserExtractsFilamentNameSubtypeNetWeightAndResolvedColor() {
        let lines = [
            "Polymaker PolyLite PLA Matte Army Green",
            "Net Weight: 1kg",
            "Nozzle Temp: 205-225C",
            "Bed Temp: 55-65C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.filamentName == "PLA Matte Army Green")
        #expect(candidate.subtype == "Matte")
        #expect(candidate.netWeightG == 1000)
        // Colour resolves from the bundled catalogue (which now contains a "Matte Army
        // Green" entry); assert a valid 6-char hex rather than a brittle exact value.
        #expect(candidate.colorHex?.count == 6)
    }

    @Test func parserPrefersLabeledMultiSpeedNozzleOverSingleKeywordParse() {
        let lines = [
            "Bambu Lab ABS",
            "Nozzle: 220/240/260C",
            "Bed Temp: 60-100C"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minNozzleTemp == 220)
        #expect(candidate.maxNozzleTemp == 260)
        #expect(candidate.minBedTemp == 60)
        #expect(candidate.maxBedTemp == 100)
        #expect(candidate.isBedTempInferred == false)
    }

    @Test func parserInfersBedTempFromMaterialWhenMissingAndFlagsInference() {
        let lines = [
            "Generic PETG",
            "Nozzle 235-255C",
            "Color: White"
        ]

        let candidate = OCRFilamentParserService.parse(lines: lines)

        #expect(candidate.minBedTemp == 70)
        #expect(candidate.maxBedTemp == 70)
        #expect(candidate.isBedTempInferred == true)
    }

    @Test func parserOnlyAcceptsSupportedFilamentDiameters() {
        let linesWithSupported = [
            "Premium PLA",
            "Filament Diameter: 3.00 mm"
        ]
        let linesWithUnsupported = [
            "Premium PLA",
            "Filament Diameter: 2.50 mm"
        ]

        let supported = OCRFilamentParserService.parse(lines: linesWithSupported)
        let unsupported = OCRFilamentParserService.parse(lines: linesWithUnsupported)

        #expect(supported.diameterMM == 3.0)
        #expect(unsupported.diameterMM == nil)
    }

    @Test func parserMatchesPETGNotPET() {
        let lines = ["Generic PETG", "Nozzle 230-250C", "Bed 70C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "PETG")
    }

    @Test func parserMatchesPPNotPPA() {
        let lines = ["Fiberlogy PP", "Nozzle 220-250C", "Bed 30C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "PP")
    }

    @Test func parserMatchesBrandFromBundledList() {
        let lines = ["Fiberlogy TPU", "Nozzle 200-220C", "Bed 50C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.brand == "Fiberlogy")
    }

    @Test func parserRecognizesPrintTempAsNozzle() {
        let lines = [
            "Polymaker PLA",
            "Print temp: 210-230C",
            "Bed 55C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 210)
        #expect(candidate.maxNozzleTemp == 230)
    }

    @Test func parserDoesNotFallbackWhenNozzleHasHighConfidence() {
        let lines = [
            "Polymaker PLA Black",
            "Nozzle: 220-240C",
            "Bed 55C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 220)
        #expect(candidate.maxNozzleTemp == 240)
        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
    }

    @Test func parserRejectsSingleDigitBedTemp() {
        let lines = [
            "Generic PLA",
            "Nozzle 200-220C",
            "Bed 5C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minBedTemp == 50)
        #expect(candidate.maxBedTemp == 50)
        #expect(candidate.isBedTempInferred == true)
    }

    @Test func parserInfersBedWhenUnlabeledTempTooLow() {
        let lines = [
            "Generic PETG",
            "Nozzle 230-250C",
            "25C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minBedTemp == 70)
        #expect(candidate.maxBedTemp == 70)
        #expect(candidate.isBedTempInferred == true)
    }

    @Test func parserRejectsBedTempOutsideMaterialDeviation() {
        // PLA inferred = 50; 50% bounds = 25-75. Scanned 108 is outside → use inferred.
        let lines = [
            "Generic PLA",
            "Nozzle 200-220C",
            "Bed 108C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minBedTemp == 50)
        #expect(candidate.maxBedTemp == 50)
        #expect(candidate.isBedTempInferred == true)
    }

    @Test func parserAcceptsBedTempWithinMaterialDeviation() {
        // ASA inferred = 90; 50% bounds = 45-135. Scanned 80-100 is inside → keep scanned.
        let lines = [
            "Generic ASA",
            "Nozzle 250-270C",
            "Bed 80-100C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minBedTemp == 80)
        #expect(candidate.maxBedTemp == 100)
        #expect(candidate.isBedTempInferred == false)
    }

    @Test func parserRejectsBedTempAboveMaterialDeviation() {
        // ABS inferred = 90 (median of bundled ABS bed temps); 50% bounds = 45-135.
        // Scanned 180 is outside → use inferred.
        let lines = [
            "Generic ABS",
            "Nozzle 240-260C",
            "Bed 180C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minBedTemp == 90)
        #expect(candidate.maxBedTemp == 90)
        #expect(candidate.isBedTempInferred == true)
    }

    @Test func parserParsesNozzleTempWithUnitsAndSlashes() {
        let lines = [
            "Polymaker PLA",
            "Print temp: 190°C / 210°C / 230°C",
            "Bed 55C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 230)
        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
    }

    @Test func parserParsesDashSeparatedTripleNozzleTemps() {
        let lines = [
            "Bambu Lab ABS",
            "Nozzle 240 - 260 - 280°C",
            "Bed 90C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 240)
        #expect(candidate.maxNozzleTemp == 280)
        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
    }

    @Test func parserParsesNozzleTempWithWideKeywordGap() {
        let lines = [
            "Generic PLA",
            "Recommended print temperature is 200°C",
            "Bed 60C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 200)
        #expect(candidate.maxNozzleTemp == 200)
        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
    }

    @Test func parserHandlesNonASCIIWithoutMisaligningRanges() {
        let lines = [
            "Generic PLA weiß",
            "Net Weight: 1kg",
            "Nozzle 200-220C",
            "Bed 60C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "PLA")
        #expect(candidate.netWeightG == 1000)
        #expect(candidate.minNozzleTemp == 200)
        #expect(candidate.maxNozzleTemp == 220)
        #expect(candidate.minBedTemp == 60)
        #expect(candidate.maxBedTemp == 60)
    }

    @Test func parserPairsNozzleTempAcrossLineBreak() {
        let lines = [
            "Generic PLA",
            "Nozzle:",
            "210-230C",
            "Bed 60C"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 210)
        #expect(candidate.maxNozzleTemp == 230)
        #expect(candidate.minBedTemp == 60)
        #expect(candidate.maxBedTemp == 60)
    }

    // MARK: - Filament name construction (spec 044)

    @Test func parserConstructsFilamentNameFromMaterialSubtypeColor() {
        let lines = ["Generic PLA Matte", "Color: Charcoal", "Nozzle 200-220C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "PLA")
        #expect(candidate.subtype == "Matte")
        #expect(candidate.filamentName == "PLA Matte Charcoal")
    }

    @Test func parserConstructsFilamentNameFromMaterialColorWhenSubtypeAbsent() {
        let lines = ["Generic PLA", "Color: Charcoal", "Nozzle 200-220C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.subtype == nil)
        #expect(candidate.filamentName == "PLA Charcoal")
    }

    @Test func parserFallsBackToFirstLineWhenMaterialMissing() {
        let lines = ["PolyColor Pro Filament", "Color: Charcoal"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == nil)
        #expect(candidate.filamentName == "PolyColor Pro Filament")
    }

    @Test func parserFallsBackToFirstLineWhenColorNameMissing() {
        let lines = ["Generic PLA", "1.75mm diameter"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "PLA")
        #expect(candidate.colorHex == nil)
        #expect(candidate.filamentName == "Generic PLA")
    }

    @Test func parserFilamentNameExcludesBrand() {
        let lines = ["Polymaker PLA", "Color: Charcoal"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.brand == "Polymaker")
        #expect(candidate.filamentName == "PLA Charcoal")
    }

    // MARK: - Subtype/color dedup in name construction (spec 048)

    @Test func parserFilamentNameDeduplicatesLeadingSubtypeInColor() {
        // Dedupe: subtype "Matte" + color "Matte Army Green" → "PLA Matte Army Green" (not "…Matte Matte Army Green").
        let dedupeLines = ["Generic PLA Matte", "Color: Matte Army Green", "Nozzle 200-220C"]
        let dedupeCandidate = OCRFilamentParserService.parse(lines: dedupeLines)
        #expect(dedupeCandidate.subtype == "Matte")
        #expect(dedupeCandidate.filamentName == "PLA Matte Army Green")

        // Non-dedupe: subtype "Matte" + color "Charcoal" (does not lead with "Matte") → unchanged.
        let nonDedupeLines = ["Generic PLA Matte", "Color: Charcoal", "Nozzle 200-220C"]
        let nonDedupeCandidate = OCRFilamentParserService.parse(lines: nonDedupeLines)
        #expect(nonDedupeCandidate.subtype == "Matte")
        #expect(nonDedupeCandidate.filamentName == "PLA Matte Charcoal")
    }

    // MARK: - Fuzzy vocabulary fallback (spec 046)

    @Test func parserFuzzyMatchesMisreadMaterialToken() {
        // "HIQS" is a Q-for-P OCR misread of "HIPS" (distance 1, unambiguous in the real
        // vocabulary); exact match fails, fuzzy fallback recovers the correct material.
        let lines = ["HIQS filament", "Nozzle 210-230C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == "HIPS")
    }

    @Test func parserDoesNotFuzzyMatchShortMaterialToken() {
        // "ABZ" is 3 chars — the parser applies a ≥4-char guard before calling the fuzzy
        // matcher, so no fuzzy promotion occurs regardless of vocabulary distance.
        let lines = ["ABZ filament", "Nozzle 230C"]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.material == nil)
    }

    // MARK: - OCR corpus regressions (2026-06-22 batch)
    // Each test below uses the exact `rawLines` from a real OCR scan archive whose
    // `corrections` array recorded a parser miss. Comments cite the scanId.

    // R1 — AzureFilm PETG "Hyper Speed": three print-speed tiers (240/255/265°C).
    // The 30-char labeled-temp window stopped at 255, dropping the 265°C third tier.
    // scanId 676CAC54 (max nozzle corrected 255 → 265).
    @Test func parserReadsMaxAcrossMultiSpeedNozzleTiers() {
        let lines = [
            "azurefilm", "PETG MATTE Hyper Speed", "COLOR: LIPSTICK RED",
            "SKU: FGM171-3002", "NET WEIGHT: 1000g", "TYPE: REUSABLE SPOOL",
            "DIAMETER:", "1.75mm + 0.02mm", "NOZZLE TEMP at PRINT SPEED:",
            "240°C at 100mm/s", "255°C at 100-500mm/s", "265°C at 500-1000mm/s",
            "BED TEMP:", "80°C", "3830083548075", "14052025M3"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.minNozzleTemp == 240)
        #expect(candidate.maxNozzleTemp == 265)
        #expect(candidate.minBedTemp == 80)
        #expect(candidate.maxBedTemp == 80)
    }

    // S1 — color resolver matched the polluted catalogue phrase "White 1" (the trailing
    // "1" comes from "Color: White 1-2601-0116"); the stray digit leaked into the name.
    // scanId 3EFC2B49 (filamentName corrected "PLA White 1" → "PLA White").
    @Test func parserStripsTrailingDigitFromResolvedColorInName() {
        let lines = [
            "9", "2", "Elegoo PLA (RFID) Filament 1000g-White", "PLA",
            "1.75mm 1KG", "Color: White", "1-2601-0116", "190°C— 230°C", "50. 203. 0813"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.filamentName == "PLA White")
    }

    // R4 — unlabeled weight: the label states "1000g-White" and "1KG" but no "net weight"
    // label, so the weight was missed. scanId 3EFC2B49 (netWeight corrected ∅ → 1000).
    @Test func parserDetectsUnlabeledKilogramWeightWhenValueIsUnique() {
        let lines = [
            "9", "2", "Elegoo PLA (RFID) Filament 1000g-White", "PLA",
            "1.75mm 1KG", "Color: White", "1-2601-0116", "190°C— 230°C", "50. 203. 0813"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.netWeightG == 1000)
    }

    // S3 + R2 — the em-dash range "190°C— 230°C" must parse as 190-230, and the catalogue
    // fallback (ELEGOO/PLA/White = 190-220) must NOT overwrite a genuinely-scanned range.
    // scanId 3EFC2B49 (max nozzle corrected 220 → 230).
    @Test func parserKeepsScannedNozzleRangeOverCatalogueFallback() {
        let lines = [
            "9", "2", "Elegoo PLA (RFID) Filament 1000g-White", "PLA",
            "1.75mm 1KG", "Color: White", "1-2601-0116", "190°C— 230°C", "50. 203. 0813"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.brand == "ELEGOO")
        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 230)
    }

    // S3 (focused) — a temperature range written with degree units and an em-dash
    // separator ("190°C— 230°C") parses both endpoints. No brand → no catalogue fallback.
    @Test func parserParsesEmDashTemperatureRangeWithDegreeUnits() {
        let candidate = OCRFilamentParserService.parse(lines: ["Generic PLA", "190°C— 230°C", "Bed 60C"])
        #expect(candidate.minNozzleTemp == 190)
        #expect(candidate.maxNozzleTemp == 230)
    }

    // R3 + S4 — AzureFilm PCTG: "PT:"/"BT:" temperature abbreviations and a comma-decimal
    // diameter "1,75mm". With BT recognized, bed reads 80 (was a wrong 75 leaked from the
    // diameter digits). scanId B96531E3 (bed corrected 75 → 80). The nozzle max on this
    // frame is an unrecoverable OCR misread (label 260, OCR read 200), so only the
    // recognition flag is asserted there.
    @Test func parserRecognizesPTandBTAbbreviationsAndCommaDiameter() {
        let lines = [
            "0.02mm)", "azurefilm", "PCTG Grey 1,75mm/1000g", "PT 240-200°C/ BT.80°C",
            "38", "30063 54535", "FC171-7001", "PLAN", "Bleek", "18102001C 8",
            "SN 29373072524 MaseinChin"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.diameterMM == 1.75)
        #expect(candidate.minBedTemp == 80)
        #expect(candidate.maxBedTemp == 80)
        #expect(candidate.wasBedExplicitlyLabeled == true)
        #expect(candidate.wasNozzleExplicitlyLabeled == true)
    }

    // S4 (focused) — comma decimal separator (European labels) in the diameter.
    @Test func parserReadsCommaDecimalDiameter() {
        let candidate = OCRFilamentParserService.parse(lines: ["Generic PCTG", "1,75mm"])
        #expect(candidate.diameterMM == 1.75)
    }

    // S2 — "Support" must NOT be inferred from the contact email "support@3djayo.com" or
    // the help-desk phrase "technical support"; the false subtype also polluted the name.
    // scanId 17A7C06E (subtype corrected "Support" → ∅, name → "PLA+ Black").
    @Test func parserDoesNotInferSupportSubtypeFromContactEmail() {
        let lines = [
            "JAYO", "NEAT WINDING PRO", "Weight: 1.1kg / 2.4lb", "Diameter: 1.75mm",
            "12", "Neatly Wound Filament", "Fit for Most of FDM 3D Printers",
            "98% Tolarence + 0.02mm", "Tangle Free", "Bubble Free", "Clog Free",
            "Thread the line through holes after use.", "- 200g", "100%", "- 400g",
            "For any questions or technical support", "please contact: support@3djayo.com",
            "PLA+", "Black", "01.75mm", "400g-", "-600g", "-1000g", "2006", "800g--",
            "1000g-", "18102001C Print Temp: 205-215'C", "S/N:2937307252A Made In China"
        ]
        let candidate = OCRFilamentParserService.parse(lines: lines)
        #expect(candidate.subtype == nil)
        #expect(candidate.filamentName == "PLA+ Black")
    }
}
