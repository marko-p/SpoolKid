import Testing
import Foundation
@testable import SpoolKid

struct OCRNumberTokenizerTests {
    @Test func temperatureUnitsAreCompatibleAndPhysicalUnitsAreNot() {
        #expect(OCRNumberUnit.degree.isTemperatureCompatible == true)
        #expect(OCRNumberUnit.none.isTemperatureCompatible == true)
        #expect(OCRNumberUnit.meter.isTemperatureCompatible == false)
        #expect(OCRNumberUnit.millimeter.isTemperatureCompatible == false)
        #expect(OCRNumberUnit.gram.isTemperatureCompatible == false)
        #expect(OCRNumberUnit.kilogram.isTemperatureCompatible == false)
        #expect(OCRNumberUnit.percent.isTemperatureCompatible == false)
    }

    @Test func tokenizerTagsUnitsAndNearestLabel() {
        let tokens = OCRNumberTokenizer.tokenize("Printing Temp 190-230°C Length 330m")
        #expect(tokens.contains { $0.value == 190 && $0.label == "print" && $0.unit.isTemperatureCompatible })
        #expect(tokens.contains { $0.value == 230 && $0.label == "print" && $0.unit == .degree })
        let threeThirty = tokens.first { $0.value == 330 }
        #expect(threeThirty?.label == "length")
        #expect(threeThirty?.unit == .meter)
        #expect(threeThirty?.unit.isTemperatureCompatible == false)
    }

    @Test func tokenizerExcludesDecimalFractionDigitsButKeepsSeparatorDotDigits() {
        let tokens = OCRNumberTokenizer.tokenize("1.75mm BT.80°C")
        #expect(tokens.contains { $0.value == 80 && $0.unit == .degree && $0.label == "bt" })
        #expect(!tokens.contains { $0.value == 75 })
        #expect(!tokens.contains { $0.value == 1 })
    }

    @Test func tokenizerTagsBareCAsDegreeAndMmPerSecondSpeedAsMillimeter() {
        let tokens = OCRNumberTokenizer.tokenize("Nozzle 250-270C 100mm/s")
        #expect(tokens.first { $0.value == 270 }?.unit == .degree)
        // Qualify `.none`: on an Optional, a bare `.none` would resolve to Optional.none (nil).
        #expect(tokens.first { $0.value == 250 }?.unit == OCRNumberUnit.none)
        #expect(tokens.first { $0.value == 100 }?.unit == .millimeter)
    }

    @Test func tokenizerNormalizesSpacedLabelToDespacedKeyword() {
        let tokens = OCRNumberTokenizer.tokenize("Build Plate 60C")
        #expect(tokens.first { $0.value == 60 }?.label == "buildplate")
    }
}
