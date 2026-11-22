//
//  TagDumpArchiveBuilder.swift
//  SpoolKid
//
//  Purpose: Turn a finished dump into a kept capture directory.
//
//  Mirrors OCRArchiveBuilder: build under tmp, then hand the directory to
//  DiagnosticCaptureStore, which moves it into Application Support. iOS
//  reclaims tmp without warning, and a dump that vanishes before the tester
//  gets to a computer is a scan they will not repeat.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagDumpArchiveBuilder {

    @discardableResult
    static func build(_ dump: TagDump, at now: Date = Date()) throws -> URL {
        let workDir = try DiagnosticBundle.makeWorkDirectory(kind: DiagnosticCaptureKind.tagDump.rawValue, at: now)
        let manifest = workDir.appendingPathComponent(DiagnosticCaptureKind.tagDump.manifestFilename)
        try TagDump.encoder.encode(dump).write(to: manifest)
        return try DiagnosticCaptureStore.keep(workDir)
    }
}
