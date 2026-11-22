//
//  DiagnosticCaptureKindTests.swift
//  SpoolKidTests
//
//  Kind slugs and the timestamp that follows them both contain hyphens, so
//  the obvious split-on-dash is wrong in a way that only shows up as captures
//  quietly missing from the list.
//

import Testing
import Foundation
@testable import SpoolKid

struct DiagnosticCaptureKindTests {

    @Test func eachKindIsRecognisedFromItsDirectoryName() {
        #expect(DiagnosticCaptureKind.from(directoryName: "ocr-scan-2026-09-07T14-22-31-a1b2c3d4") == .labelScan)
        #expect(DiagnosticCaptureKind.from(directoryName: "tag-dump-2026-09-07T14-22-31-a1b2c3d4") == .tagDump)
        #expect(DiagnosticCaptureKind.from(directoryName: "scale-capture-2026-09-07T14-22-31-a1b2c3d4") == .scaleCapture)
        #expect(DiagnosticCaptureKind.from(directoryName: "scale-photos-2026-09-07T14-22-31-a1b2c3d4") == .scalePhotos)
    }

    /// `scale-capture` and `scale-photos` share a first dash-separated word,
    /// and `ocr-scan` and `tag-dump` are two words each. Prefix matching has
    /// to be on the whole slug.
    @Test func kindsSharingAWordAreNotConfused() {
        #expect(DiagnosticCaptureKind.from(directoryName: "scale-photos-2026-01-01T00-00-00-deadbeef") != .scaleCapture)
    }

    @Test func anUnknownPrefixIsNotAKind() {
        #expect(DiagnosticCaptureKind.from(directoryName: "mystery-2026-09-07T14-22-31-a1b2c3d4") == nil)
        #expect(DiagnosticCaptureKind.from(directoryName: "") == nil)
    }

    /// A bare slug with no timestamp is not a capture directory.
    @Test func theSlugAloneIsNotACaptureDirectory() {
        #expect(DiagnosticCaptureKind.from(directoryName: "tag-dump") == nil)
    }

    @Test func eachKindNamesItsOwnManifest() {
        #expect(DiagnosticCaptureKind.labelScan.manifestFilename == "workflow.json")
        #expect(DiagnosticCaptureKind.tagDump.manifestFilename == "dump.json")
    }
}
