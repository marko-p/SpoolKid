//
//  TagReplacePromptTests.swift
//  SpoolKidTests
//
//  Purpose: The Replace Tag prompt's copy and the guards each link point uses
//  to decide whether to ask.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagReplacePromptTests {
    private func spool(rfid: String?) -> Spool {
        Spool(
            id: 1, filament: Filament(id: 1, name: "PLA", material: "PLA", vendor: nil, diameter: 1.75, weight: 1000),
            extra: nil, rfidUID: rfid, statusId: nil, externalId: nil, purchaseDate: nil, rfidUIDWritable: true
        )
    }

    @Test func copy() {
        #expect(TagStoreText.replacePromptTitle == "FilaMan Holds One Tag per Spool")
        #expect(TagStoreText.replacePromptMessage(spool: "#1 PLA", existing: "A")
            == "#1 PLA is linked to tag A. Replace it with this tag? The old tag will no longer identify the spool in FilaMan or on its scale.")
    }

    @Test func scanLinkAsksOnlyInROnly() {
        let held = spool(rfid: "a")
        #expect(TagReplaceRequest.linking(uid: "T", to: held, targets: [.filamanTags])?.existing == "A")
        #expect(TagReplaceRequest.linking(uid: "T", to: held, targets: [.filamanTags, .cardUIDs]) == nil)
        #expect(TagReplaceRequest.linking(uid: "a", to: held, targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.linking(uid: "T", to: spool(rfid: nil), targets: [.filamanTags]) == nil)
    }

    @Test func writeAsksBeforeWritingWhenSpoolHoldsAnyTag() {
        let held = spool(rfid: "a")
        #expect(TagReplaceRequest.writing(spool: held, knownUID: nil, targets: [.filamanTags])?.existing == "A")
        #expect(TagReplaceRequest.writing(spool: held, knownUID: nil, targets: [.filamanTags, .cardUIDs]) == nil)
        #expect(TagReplaceRequest.writing(spool: spool(rfid: nil), knownUID: nil, targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.writing(spool: held, knownUID: "a", targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.writing(spool: held, knownUID: "T", targets: [.filamanTags])?.uid == "T")
    }

    @Test func formScanAsksOnlyForASpoolThatHoldsAnotherTag() {
        let held = spool(rfid: "a")
        #expect(TagReplaceRequest.scanning(uid: "T", into: held, targets: [.filamanTags])?.existing == "A")
        #expect(TagReplaceRequest.scanning(uid: "T", into: nil, targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.scanning(uid: "T", into: held, targets: [.filamanTags, .cardUIDs]) == nil)
    }

    /// F3: an unsaved Add section in R-only asks before listing a second tag.
    @Test func unsavedSectionAsksWhenItListsAnotherTag() {
        let asked = TagReplaceRequest.scanning(uid: "T", into: nil, listed: ["B"], targets: [.filamanTags])
        #expect(asked?.existing == "B")
        #expect(asked?.uid == "T")
        #expect(asked?.spool == nil)
        #expect(asked?.spoolTitle == TagReplaceRequest.unsavedSpoolTitle)
        #expect(TagReplaceRequest.scanning(uid: "T", into: nil, listed: [], targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.scanning(uid: "t", into: nil, listed: ["T"], targets: [.filamanTags]) == nil)
        #expect(TagReplaceRequest.scanning(uid: "T", into: nil, listed: ["B"], targets: [.filamanTags, .cardUIDs]) == nil)
        #expect(TagReplaceRequest.scanning(uid: "T", into: nil, listed: ["B"], targets: [.cardUIDs]) == nil)
    }

    /// F3: an R-only create links one tag; the rest are named.
    @Test func rOnlyCreateNamesTheTagsNotLinked() {
        #expect(TagStoreText.filamanCreateUnlinkedNote(listed: ["A", "B"], targets: [.filamanTags])
            == "FilaMan keeps one tag per spool; tag B was not linked.")
        #expect(TagStoreText.filamanCreateUnlinkedNote(listed: ["A", "B", "C"], targets: [.filamanTags])
            == "FilaMan keeps one tag per spool; tags B, C were not linked.")
        #expect(TagStoreText.filamanCreateUnlinkedNote(listed: ["A"], targets: [.filamanTags]) == nil)
        #expect(TagStoreText.filamanCreateUnlinkedNote(listed: ["A", "B"], targets: [.filamanTags, .cardUIDs]) == nil)
    }
}
