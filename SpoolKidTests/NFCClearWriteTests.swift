//
//  NFCClearWriteTests.swift
//  SpoolKidTests
//
//  Tests for the tag-erase (clear) write path's pure seams: the zero-page
//  plan built from a scan's snapshot pages, and the password-guard fixtures
//  for the two NTAG215 config reads seen in the field (an owner-cloned
//  Anycubic tag and the documented factory-AnyCubic layout).
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCClearWriteTests {
    // MARK: - The erase page plan

    @Test func clearPagePlanZeroesSnapshotPagesHighestFirst() {
        let plan = NFCManager.clearPagePlan(zeroPages: [4, 5, 6, 7, 8])

        // Highest first (`rawWriteOrder`): a chip that refuses the top page
        // refuses before anything lands, exactly like a clone.
        #expect(plan.map(\.page) == [8, 7, 6, 5, 4])
        #expect(plan.allSatisfy { $0.data == Data(repeating: 0, count: 4) })
    }

    @Test func clearPagePlanDeduplicatesPages() {
        let plan = NFCManager.clearPagePlan(zeroPages: [4, 4, 5, 5, 5])

        #expect(plan.map(\.page) == [5, 4])
    }

    @Test func clearPagePlanEmptyForNDEFScans() {
        // An NDEF scan carries no raw pages — its erase stays on the NDEF path.
        #expect(NFCManager.clearPagePlan(zeroPages: []).isEmpty)
    }

    @Test func aceSnapshotYieldsPages4Through31() {
        // The ACE scan captures pages 4-31 (`AnycubicACEPayload.totalPages`),
        // and those are the pages a clone proved writable on the owner's
        // cloned tag — the pages an erase must zero.
        var bytes = [UInt8](repeating: 0xAB, count: 32 * 4)
        let snapshot = TagSnapshot.capturingPages(
            bytes,
            firstPage: TagSnapshot.firstUserPage,
            lastPage: AnycubicACEPayload.totalPages - 1
        )
        let pages = snapshot?.pageWrites.map(\.page) ?? []

        #expect(pages.first == TagSnapshot.firstUserPage)
        #expect(pages.last == AnycubicACEPayload.totalPages - 1)
        #expect(pages.count == AnycubicACEPayload.totalPages - TagSnapshot.firstUserPage)
    }

    @Test func ndefSnapshotYieldsNoZeroPages() {
        // OpenSpool and location tags erase through the NDEF path, as before.
        let snapshot = TagSnapshot.ndef([])
        #expect(snapshot.pageWrites.isEmpty)
    }

    // MARK: - Password-guard fixtures (characterization)

    /// The READ at the CFG0 page (131) from the owner's cloned NTAG215 (tag
    /// dump 2026-09-18, pages 131-134): the NTAG215 factory configuration,
    /// untouched. AUTH0 = 0xFF protects no page, so an erase through pages
    /// 4-31 proceeds, exactly as the clone's writes did on this chip. Page 130
    /// (`000000BD`) is the dynamic lock page, not CFG0.
    @Test func clonedTagConfigReadsAsUnprotected() {
        var configRead = Data()
        configRead.append(contentsOf: [0x04, 0x00, 0x00, 0xFF]) // CFG0
        configRead.append(contentsOf: [0x00, 0x05, 0x00, 0x00]) // CFG1
        configRead.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // PWD (reads as zeros)
        configRead.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // PACK (reads as zeros)

        #expect(NFCManager.writeNeedsPassword(configRead: configRead, throughPage: 31) == false)
    }

    /// The documented factory-AnyCubic layout (nfc-formats.md): CFG0
    /// `04000004`, so the guard reads protection from page 4 and the write is
    /// refused with the password message — the behavior that keeps SpoolKid
    /// from hammering tags it cannot authenticate to.
    @Test func factoryAnyCubicConfigReadsAsProtected() {
        var configRead = Data()
        configRead.append(contentsOf: [0x04, 0x00, 0x00, 0x04]) // CFG0
        configRead.append(contentsOf: [0x47, 0x00, 0x00, 0x00]) // CFG1
        configRead.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // RFUI
        configRead.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // PWD (unreadable)

        #expect(NFCManager.writeNeedsPassword(configRead: configRead, throughPage: 31) == true)
    }

    /// A config READ that is not a full 16-byte reply answers nil, and the
    /// write path proceeds guarded by its highest page going first.
    @Test func shortConfigReadAnswersNil() {
        #expect(NFCManager.writeNeedsPassword(configRead: Data([0x00, 0x00]), throughPage: 31) == nil)
    }
}
