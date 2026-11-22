import Testing
@testable import SpoolKid

struct SearchQueryTests {

    private let azureMint: [String?] = ["PLA Matte Mint", "AzureFilm", "PLA", nil]

    @Test func blankQueryMatchesEverything() {
        #expect(SearchQuery.matches("", in: azureMint))
        #expect(SearchQuery.matches("   ", in: azureMint))
    }

    @Test func singleTokenMatchesAnyField() {
        #expect(SearchQuery.matches("AzureFilm", in: azureMint))
        #expect(SearchQuery.matches("Mint", in: azureMint))
        #expect(SearchQuery.matches("PLA", in: azureMint))
    }

    // The bug this type exists for: the old filters tested the WHOLE query
    // against each field separately, so a query naming two different fields
    // could never match anything.
    @Test func tokensMayComeFromDifferentFields() {
        #expect(SearchQuery.matches("AzureFilm PLA", in: azureMint))
        #expect(SearchQuery.matches("AzureFilm Mint", in: azureMint))
        #expect(SearchQuery.matches("PLA Mint", in: azureMint))
    }

    @Test func tokenOrderDoesNotMatter() {
        #expect(SearchQuery.matches("Mint AzureFilm", in: azureMint))
    }

    @Test func everyTokenMustMatch() {
        #expect(!SearchQuery.matches("AzureFilm PETG", in: azureMint))
        #expect(!SearchQuery.matches("Prusament", in: azureMint))
    }

    @Test func matchingIsCaseAndDiacriticInsensitive() {
        #expect(SearchQuery.matches("azurefilm mINT", in: azureMint))
        #expect(SearchQuery.matches("azurefilm", in: ["ÁzureFilm"]))
    }

    @Test func nilAndEmptyFieldsAreSkipped() {
        #expect(!SearchQuery.matches("PLA", in: [nil, ""]))
        #expect(SearchQuery.matches("PLA", in: [nil, "PLA"]))
    }

    @Test func repeatedWhitespaceDoesNotCreateEmptyTokens() {
        #expect(SearchQuery.matches("  AzureFilm    PLA  ", in: azureMint))
    }
}
