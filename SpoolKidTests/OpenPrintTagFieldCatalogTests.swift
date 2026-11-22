//
//  OpenPrintTagFieldCatalogTests.swift
//  SpoolKidTests
//
//  The Write Tag form can only state a number the catalog lists. A Prusa
//  printer counts a spool down from its diameter, density and net weight, and
//  from how much of it is left, so OpenPrintTag's form offers all of them.
//

import Testing
import Foundation
@testable import SpoolKid

struct OpenPrintTagFieldCatalogTests {

    @Test func openPrintTagOffersDiameterAndRemaining() {
        let ids = NFCFieldCatalog.fields(for: .openPrintTag).map(\.id)
        #expect(ids.contains("diameter"))
        #expect(ids.contains("remaining"))

        let store = NFCFieldVisibilityStore()
        #expect(store.visibilityKey(for: .openPrintTag, fieldID: "diameter")
                == AppConfig.visibilityNFCOpenPrintTagDiameterKey)
        #expect(store.visibilityKey(for: .openPrintTag, fieldID: "remaining")
                == AppConfig.visibilityNFCOpenPrintTagRemainingKey)
    }
}
