//
//  BackendNamedCopyTests.swift
//  SpoolKidTests
//
//  The copy contract for shared, backend-agnostic surfaces: a string a FilaMan
//  or Library user can see must never name Spoolman. Every seam here branches
//  on a capability, so the contract can be stated once, for every kind, rather
//  than asserted string by string.
//

import Testing
@testable import SpoolKid

struct BackendNamedCopyTests {

    // MARK: - The general rule

    /// The whole point of the sweep (I4): no shared surface may name a backend
    /// the user is not running. Stated over `BackendKind.allCases` so a fourth
    /// backend inherits the check instead of needing new assertions.
    @Test func noSharedCopyNamesAnotherBackend() {
        let names = ["Spoolman", "FilaMan"]

        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)
            let strings = [
                caps.storageNoun,
                ScanResultHubView.noMappingHeadline(caps),
                FilamentSelectionView.importFailureHint(caps),
                // The first-run guide is a shared surface too — step 2 named
                // Spoolman for every user until 2026-08-23.
                WelcomeGuideView.backendStepTitle(caps),
                WelcomeGuideView.backendStepSubtitle(caps),
                WelcomeGuideView.backendCardHint(caps),
                // The backend-configuration screen keeps its Spoolman TYPE
                // name, but its SpoolLink footer named Spoolman's card_uids
                // field on every backend.
                TagStoreText.mappingFooter(caps)
            ] + DashboardInfo.totalValue(caps)

            for string in strings {
                for foreign in names where foreign != caps.displayName {
                    #expect(
                        !string.contains(foreign),
                        "\(kind) copy \"\(string)\" names \(foreign)"
                    )
                }
            }
        }
    }

    // MARK: - The backend-configuration screen

    @Test func mappingFooterNamesTheActiveBackendsStorage() {
        #expect(TagStoreText.mappingFooter(.spoolman).contains("Spoolman"))
        #expect(TagStoreText.mappingFooter(.filaman).contains("FilaMan"))
    }

    /// The Library keeps its links in `card_uids` too (spec 2), but neither the
    /// field nor SpoolLink means anything there: its footer says what
    /// happens instead.
    @Test func mappingFooterOnTheLibraryNamesNoFieldAndNoSpoolLink() {
        let footer = TagStoreText.mappingFooter(.local)

        #expect(footer == "SpoolKid keeps each tag you link with its spool in your library, and finds the spool when you scan the tag.")
        #expect(!footer.contains("card_uids"))
        #expect(!footer.contains("SpoolLink"))
    }

    @Test func mappingFooterMentionsCardUIDsOnlyOnServers() {
        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)

            #expect(
                TagStoreText.mappingFooter(caps).contains("card_uids") == !caps.isOnDeviceStorage,
                "\(kind) footer disagrees with isOnDeviceStorage"
            )
        }
    }

    // MARK: - Pointing at the Library tab

    /// The row is labelled "Library Mode" on the on-device backend, whose
    /// `displayName` is "Library" — so copy built from the display name said
    /// "Library → Library", a row a local user could not find (final review
    /// FR-1).
    @Test func connectionRowLabelIsWhatTheLibraryTabsFirstRowSays() {
        #expect(BackendCapabilities.local.connectionRowLabel == "Library Mode")
        #expect(BackendCapabilities.spoolman.connectionRowLabel == "Spoolman")
        #expect(BackendCapabilities.filaman.connectionRowLabel == "FilaMan")
    }

    @Test func linkedTagsFooterIsSilentWhileLinksAreWritten() {
        #expect(SpoolFormView.linkedTagsFooter(identity: .init(mode: .tagLinks, linkTargets: [.cardUIDs])) == nil)
    }

    @Test func linkedTagsFooterSaysExistingLinksCanOnlyBeRemoved() {
        #expect(SpoolFormView.linkedTagsFooter(identity: .init(mode: .spoolID, linkTargets: []))
            == "SpoolKid identifies spools by the spool ID on the tag, so it adds no tag links. You can still remove one.")
        #expect(SpoolFormView.linkedTagsFooter(identity: .init(mode: .neither, linkTargets: []))
            == "SpoolKid identifies spools by neither a spool ID nor a tag link, so it adds no tag links. You can still remove one.")
    }

    // MARK: - storageNoun

    /// `displayName` is the backend's name and reads as a proper noun; prose that
    /// says "deleted from …" needs the possessive form for the on-device
    /// library, which is not a place with a name.
    @Test func storageNounIsPossessiveOnDeviceAndTheServerNameOtherwise() {
        #expect(BackendCapabilities.local.storageNoun == "your library")
        #expect(BackendCapabilities.spoolman.storageNoun == "Spoolman")
        #expect(BackendCapabilities.filaman.storageNoun == "FilaMan")
    }

    @Test func storageNounNamesTheServerForEveryServerBackend() {
        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)
            guard !caps.isOnDeviceStorage else { continue }
            #expect(caps.storageNoun == caps.displayName)
        }
    }

    // MARK: - The hub's no-mapping headline

    /// The unknown-tag card and the no-match card sit six lines apart and said
    /// different things: one had been generalised to `displayName`, the other
    /// still read "No Spoolman Mapping Found" on every backend. One helper now
    /// answers for both.
    @Test func noMappingHeadlineNamesTheActiveBackend() {
        #expect(ScanResultHubView.noMappingHeadline(.spoolman) == "No Spoolman Mapping Found")
        #expect(ScanResultHubView.noMappingHeadline(.filaman) == "No FilaMan Mapping Found")
    }

    /// The Library's links are Tags kept in your library, not a server's
    /// "mapping", so it gets a plain sentence rather than a renamed one.
    @Test func noMappingHeadlineOnTheLibraryNamesNoMapping() {
        #expect(ScanResultHubView.noMappingHeadline(.local) == "No Matching Spool")
    }

    // MARK: - Import-failure advice

    /// "Check your Spoolman connection" was shown on every backend. A server
    /// backend gets its own name; on-device storage gets no hint at all,
    /// because it has no connection to check and inventing one would send the
    /// user looking for a setting that does not exist.
    @Test func importFailureHintNamesTheServerAndIsSilentOnDevice() {
        #expect(FilamentSelectionView.importFailureHint(.local).isEmpty)
        #expect(FilamentSelectionView.importFailureHint(.spoolman).contains("Spoolman connection"))
        #expect(FilamentSelectionView.importFailureHint(.filaman).contains("FilaMan connection"))
    }

    @Test func importFailureHintMentionsAConnectionExactlyWhenThereIsOne() {
        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)
            let hint = FilamentSelectionView.importFailureHint(caps)
            #expect(hint.contains("connection") == !caps.isOnDeviceStorage)
        }
    }
}
