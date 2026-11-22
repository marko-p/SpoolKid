//
//  DiagnosticCaptureKind.swift
//  SpoolKid
//
//  Purpose: Tell one kept capture from another.
//
//  `DiagnosticBundle.makeWorkDirectory(kind:)` already prefixes every capture
//  directory with its kind, so the kind is recoverable from the name and no
//  stored capture needs migrating. Slugs contain hyphens and so does the
//  timestamp after them, which is why this matches whole prefixes rather than
//  splitting on the separator.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum DiagnosticCaptureKind: String, CaseIterable {
    case labelScan = "ocr-scan"
    case scaleCapture = "scale-capture"
    case scalePhotos = "scale-photos"
    case tagDump = "tag-dump"
    case td1sCapture = "td1s-capture"

    /// The file the store reads to summarise a capture of this kind.
    var manifestFilename: String {
        switch self {
        case .labelScan: "workflow.json"
        case .scaleCapture, .scalePhotos: "transcript.txt"
        case .tagDump: "dump.json"
        case .td1sCapture: "capture.json"
        }
    }

    /// The kind a capture directory belongs to, or nil if the name is not one
    /// this app wrote. The trailing separator is required so a directory named
    /// exactly after a slug — with no timestamp — is rejected rather than
    /// treated as a capture.
    static func from(directoryName: String) -> DiagnosticCaptureKind? {
        allCases.first { directoryName.hasPrefix("\($0.rawValue)-") }
    }
}
