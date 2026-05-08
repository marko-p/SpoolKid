import Testing
@testable import SpoolKid

struct OpenPrintTagInferenceTests {
    @Test func infersCommonTagsFromNameKeywords() {
        let inferred = OpenPrintTagInference.inferredMaterialTags(
            name: "Panchroma Matte Silk Glitter Glow",
            material: "PLA",
            subtype: nil
        )

        #expect(inferred.contains(16))
        #expect(inferred.contains(17))
        #expect(inferred.contains(23))
        #expect(inferred.contains(24))
    }

    @Test func infersFiberAndConductiveFamilies() {
        let inferred = OpenPrintTagInference.inferredMaterialTags(
            name: "PETG-CF Conductive ESD",
            material: "PETG-CF",
            subtype: nil
        )

        #expect(inferred.contains(31)) // Carbon Fiber from "CF"
        #expect(inferred.contains(10))  // ESD Safe from "ESD"
        #expect(inferred.contains(11)) // Conductive from "Conductive"
        #expect(!inferred.contains(30)) // "PETG-CF" doesn't contain "CARBON" word
    }

    @Test func mergesExistingAndInferredTagsCappedToSixteen() {
        let existing = [
            0, 1, 2, 3, 4, 5, 6, 7,
            8, 9, 10, 11, 12, 13, 14, 15
        ]

        let merged = OpenPrintTagInference.mergedMaterialTags(
            existing: existing,
            name: "Matte Silk Glitter",
            material: "PLA",
            subtype: nil
        )

        #expect(merged.count == 16)
        #expect(merged == existing)
    }
}
