//
//  PrinterLocationMatchTests.swift
//  SpoolKidTests
//
//  Purpose: A spool added from a printer tag goes to an existing location
//  whose whole name says "printer"; none is ever created.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct PrinterLocationMatchTests {
    @Test func theWordsAreTheSpecs() {
        #expect(PrinterLocationMatch.printerWords == [
            "Printer", "Snapmaker", "U1", "Drucker", "tiskalnik", "imprimante", "stampante",
            "impresora", "impressora", "drukarka", "tiskárna", "nyomtató"
        ])
    }

    @Test func aPrinterLocationIsFound() {
        #expect(PrinterLocationMatch.location(in: ["Shelf", "printer"], printerName: "Snapmaker U1") == "printer")
    }

    @Test func thePrintersOwnNameCounts() {
        #expect(PrinterLocationMatch.location(in: ["Workshop U1 Left"], printerName: "Workshop U1 Left") == "Workshop U1 Left")
    }

    @Test func aPartialNameDoesNotCount() {
        #expect(PrinterLocationMatch.location(in: ["Printer shelf"], printerName: "Snapmaker U1") == nil)
    }

    @Test func aTranslationCounts() {
        #expect(PrinterLocationMatch.location(in: ["Tiskalnik"], printerName: "Snapmaker U1") == "Tiskalnik")
    }

    @Test func accentsAndSpacesDoNotMatter() {
        #expect(PrinterLocationMatch.location(in: [" tiskarna "], printerName: "") == " tiskarna ")
    }

    @Test func noFitNoLocation() {
        #expect(PrinterLocationMatch.location(in: ["Shelf"], printerName: "Snapmaker U1") == nil)
    }

    @Test func thePrintersNameWinsThenTheWordOrder() {
        #expect(PrinterLocationMatch.location(in: ["U1", "Printer", "Bench"], printerName: "Bench") == "Bench")
        #expect(PrinterLocationMatch.location(in: ["U1", "Printer", "Bench"], printerName: "Other") == "Printer")
    }
}
