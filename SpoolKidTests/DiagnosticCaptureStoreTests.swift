//
//  DiagnosticCaptureStoreTests.swift
//  SpoolKidTests
//
//  Captures used to be built and shared in one gesture, so nothing could be
//  lost between the two. Now they are kept and shared later, which puts a
//  filesystem between a tester's scan and the sample that reaches anyone —
//  and every way that can go wrong is silent.
//

import Testing
import Foundation
@testable import SpoolKid

struct DiagnosticCaptureSummaryTests {

    @Test func allThreePartsAreJoined() {
        #expect(
            DiagnosticCaptureStore.describe(brand: "Prusament", material: "PLA", name: "Galaxy Black")
                == "Prusament · PLA · Galaxy Black"
        )
    }

    @Test func missingPartsAreOmittedRatherThanLeavingGaps() {
        #expect(DiagnosticCaptureStore.describe(brand: nil, material: "PETG", name: nil) == "PETG")
        #expect(DiagnosticCaptureStore.describe(brand: "AzureFilm", material: nil, name: "Mint") == "AzureFilm · Mint")
    }

    @Test func whitespaceOnlyCountsAsMissing() {
        #expect(DiagnosticCaptureStore.describe(brand: "  ", material: "\n", name: "ASA") == "ASA")
    }

    /// A label nothing could be read from is the most interesting sample there
    /// is. The row has to invite sending it, not look like a broken entry.
    @Test func nothingReadableStillDescribesItself() {
        let summary = DiagnosticCaptureStore.describe(brand: nil, material: nil, name: nil)
        #expect(summary == "Nothing read from this label")
    }
}

/// Serialized because the store is genuinely global — one directory in
/// Application Support, shared by every test in here. Swift Testing runs
/// tests in parallel by default, and these clear the folder around each case,
/// so unserialized they delete each other's captures.
@Suite(.serialized)
struct DiagnosticCaptureStoreTests {

    /// A capture directory shaped the way `OCRArchiveBuilder` writes one —
    /// including the `ocr-scan-` prefix `DiagnosticCaptureKind` reads back to
    /// tell a label scan from any other kind of capture.
    private func makeCapture(name: String, at date: Date, brand: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-scan-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let brandJSON = brand.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"capturedAt":"\(formatter.string(from: date))","final":{"brand":\(brandJSON),"material":"PLA","filamentName":"Test"}}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("workflow.json"))
        try Data("photo".utf8).write(to: root.appendingPathComponent("label.jpg"))
        return root
    }

    private func withCleanStore(_ body: () throws -> Void) rethrows {
        DiagnosticCaptureStore.clear()
        defer { DiagnosticCaptureStore.clear() }
        try body()
    }

    @Test func aKeptCaptureIsListedWithItsSummary() throws {
        try withCleanStore {
            let built = try makeCapture(name: "cap-a", at: Date(timeIntervalSince1970: 1_000), brand: "Prusament")
            try DiagnosticCaptureStore.keep(built)
            let listed = DiagnosticCaptureStore.list()
            #expect(listed.count == 1)
            #expect(listed.first?.summary == "Prusament · PLA · Test")
            // Moved, not copied: two copies of every label photo is the kind
            // of thing nobody notices until the phone is full.
            #expect(!FileManager.default.fileExists(atPath: built.path))
        }
    }

    @Test func newestIsListedFirst() throws {
        try withCleanStore {
            try DiagnosticCaptureStore.keep(makeCapture(name: "old", at: Date(timeIntervalSince1970: 1_000), brand: "Old"))
            try DiagnosticCaptureStore.keep(makeCapture(name: "new", at: Date(timeIntervalSince1970: 9_000), brand: "New"))
            #expect(DiagnosticCaptureStore.list().first?.summary.hasPrefix("New") == true)
        }
    }

    /// The cap exists so the folder cannot become a photo library. What it
    /// drops must be the OLDEST — a tester who keeps scanning is contributing
    /// the newest labels.
    @Test func theOldestDropOffPastTheCap() throws {
        try withCleanStore {
            for i in 0..<(DiagnosticCaptureStore.capacity + 3) {
                try DiagnosticCaptureStore.keep(
                    makeCapture(name: "cap-\(i)", at: Date(timeIntervalSince1970: Double(1_000 + i)), brand: "B\(i)")
                )
            }
            let listed = DiagnosticCaptureStore.list()
            #expect(listed.count == DiagnosticCaptureStore.capacity)
            #expect(listed.contains { $0.summary.hasPrefix("B\(DiagnosticCaptureStore.capacity + 2)") })
            #expect(!listed.contains { $0.summary.hasPrefix("B0 ") })
        }
    }

    @Test func removingOneLeavesTheRest() throws {
        try withCleanStore {
            try DiagnosticCaptureStore.keep(makeCapture(name: "keep-me", at: Date(timeIntervalSince1970: 2_000), brand: "Keep"))
            try DiagnosticCaptureStore.keep(makeCapture(name: "drop-me", at: Date(timeIntervalSince1970: 3_000), brand: "Drop"))
            let doomed = try #require(DiagnosticCaptureStore.list().first { $0.summary.hasPrefix("Drop") })
            DiagnosticCaptureStore.remove(doomed)
            let remaining = DiagnosticCaptureStore.list()
            #expect(remaining.count == 1)
            #expect(remaining.first?.summary.hasPrefix("Keep") == true)
        }
    }

    /// Sharing must not consume the capture: a tester who sends one to the
    /// wrong place has to be able to send it again.
    @Test func packagingLeavesTheCaptureInPlace() throws {
        try withCleanStore {
            try DiagnosticCaptureStore.keep(makeCapture(name: "zip-me", at: Date(timeIntervalSince1970: 4_000), brand: "Zip"))
            let capture = try #require(DiagnosticCaptureStore.list().first)
            let zip = try DiagnosticCaptureStore.package(capture)
            #expect(FileManager.default.fileExists(atPath: zip.path))
            #expect(DiagnosticCaptureStore.list().count == 1)
            try? FileManager.default.removeItem(at: zip)
        }
    }

    /// One unreadable directory must not take the list down with it — the
    /// other captures are still worth sending.
    @Test func anUnreadableCaptureIsSkippedNotFatal() throws {
        try withCleanStore {
            try DiagnosticCaptureStore.keep(makeCapture(name: "good", at: Date(timeIntervalSince1970: 5_000), brand: "Good"))
            let junk = try DiagnosticCaptureStore.directory().appendingPathComponent("junk", isDirectory: true)
            try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: junk.appendingPathComponent("workflow.json"))
            let listed = DiagnosticCaptureStore.list()
            #expect(listed.count == 1)
            #expect(listed.first?.summary.hasPrefix("Good") == true)
        }
    }

    // MARK: - Tag dump archiving
    //
    // These moved here from a standalone TagDumpArchiveBuilderTests suite:
    // TagDumpArchiveBuilder.build(_:) calls DiagnosticCaptureStore.keep(_:)
    // internally, so these tests touch the same process-global store as
    // everything above. The store has exactly one serialized suite; a second
    // top-level suite touching it cannot be made safe without serializing the
    // whole target, so it lives here instead.

    private func sample(note: String) -> TagDump {
        TagDump(
            capturedAt: Date(timeIntervalSince1970: 1_788_000_000),
            uid: "04A1B2C3D4E580",
            tagType: "MIFARE Ultralight",
            chipVersion: "NTAG215",
            pagesRead: 2,
            endedBy: .wrap,
            pages: ["04A1B2C3", "D4E58000"],
            decodedAs: nil,
            note: note,
            appVersion: "0.18 (42)"
        )
    }

    @Test func theBuiltDirectoryIsNamedAsATagDump() throws {
        try withCleanStore {
            let url = try TagDumpArchiveBuilder.build(sample(note: "factory PLA+"))
            #expect(DiagnosticCaptureKind.from(directoryName: url.lastPathComponent) == .tagDump)
        }
    }

    @Test func theManifestIsWrittenWhereTheStoreLooksForIt() throws {
        try withCleanStore {
            let url = try TagDumpArchiveBuilder.build(sample(note: "factory PLA+"))
            let manifest = url.appendingPathComponent("dump.json")
            let restored = try TagDump.decoder.decode(TagDump.self, from: Data(contentsOf: manifest))
            #expect(restored.note == "factory PLA+")
            #expect(restored.pages == ["04A1B2C3", "D4E58000"])
        }
    }

    /// The hub's "Delete All" sits under a heading that says "label scans" and
    /// a count of label scans. A tag dump needs the tester's spool, their
    /// printer and a print cycle to re-take, so it must survive that button.
    @Test func clearingOneKindLeavesTheOtherKindAlone() throws {
        try withCleanStore {
            try DiagnosticCaptureStore.keep(makeCapture(name: "label", at: Date(timeIntervalSince1970: 6_000), brand: "Label"))
            _ = try TagDumpArchiveBuilder.build(sample(note: "factory PLA+"))

            DiagnosticCaptureStore.clear(kind: .labelScan)

            #expect(DiagnosticCaptureStore.list(kind: .labelScan).isEmpty)
            let dumps = DiagnosticCaptureStore.list(kind: .tagDump)
            #expect(dumps.count == 1)
            #expect(dumps.first?.summary == "factory PLA+")

            // And the other way round, so neither kind is merely lucky.
            DiagnosticCaptureStore.clear(kind: .tagDump)
            #expect(DiagnosticCaptureStore.list().isEmpty)
        }
    }

    /// The store is what the hub lists, so a built dump has to arrive there.
    @Test func theDumpIsListedByTheStoreAfterwards() throws {
        try withCleanStore {
            let url = try TagDumpArchiveBuilder.build(sample(note: "factory PLA+"))
            let listed = DiagnosticCaptureStore.list(kind: .tagDump)
            #expect(listed.contains { $0.id == url.lastPathComponent })
            #expect(listed.first { $0.id == url.lastPathComponent }?.summary == "factory PLA+")
        }
    }
}

/// A tag dump's row has to say which spool it is without being opened —
/// a tester will have several, and hex tells them apart for nobody.
struct TagDumpSummaryTests {

    @Test func theNoteIsTheSummaryWhenThereIsOne() {
        #expect(
            DiagnosticCaptureStore.describeTagDump(
                note: "Anycubic PLA+ black, factory",
                uid: "04A1B2C3D4E580",
                pages: 135
            ) == "Anycubic PLA+ black, factory"
        )
    }

    /// An unannotated dump is still worth sending, so the row identifies it
    /// rather than sitting blank.
    @Test func anUnannotatedDumpFallsBackToUIDAndSize() {
        #expect(
            DiagnosticCaptureStore.describeTagDump(note: "", uid: "04A1B2C3D4E580", pages: 135)
                == "04A1B2C3D4E580 · 135 pages"
        )
    }

    @Test func whitespaceOnlyCountsAsUnannotated() {
        #expect(
            DiagnosticCaptureStore.describeTagDump(note: "  \n ", uid: "04A1B2C3D4E580", pages: 45)
                == "04A1B2C3D4E580 · 45 pages"
        )
    }

    @Test func aSinglePageIsNotPluralised() {
        #expect(
            DiagnosticCaptureStore.describeTagDump(note: "", uid: "04A1B2C3D4E580", pages: 1)
                == "04A1B2C3D4E580 · 1 page"
        )
    }
}
