//
//  DiagnosticBundle.swift
//  SpoolKid
//
//  Purpose: Turn a directory of captured files into one zip a user can share.
//  Extracted when the Bluetooth capture became the second thing that needed
//  it — `NSFileCoordinator`'s `.forUploading` option is the only zip in the
//  system frameworks, and it is the reason SpoolKid needs no archiving
//  dependency. One implementation, two callers.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum DiagnosticBundle {

    /// A working directory under `tmp`, named for when it was made.
    ///
    /// The name is what a tester sees in the Share sheet and what arrives at
    /// the other end, so it has to say what the file is without being opened:
    /// kind, UTC timestamp, and enough randomness that two captures a second
    /// apart do not collide.
    static func makeWorkDirectory(kind: String, at now: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let name = "\(kind)-\(formatter.string(from: now))-\(UUID().uuidString.prefix(8).lowercased())"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Zips `directory` beside itself and returns the archive.
    ///
    /// `NSFileCoordinator` hands its callback a zip in a location it owns and
    /// reclaims, so the file is copied out before the block returns. An error
    /// raised inside the block cannot be thrown through it either, which is
    /// why it is captured and rethrown afterwards — swallowing it would hand
    /// back a URL pointing at nothing.
    static func zip(directory: URL) throws -> URL {
        let zipURL = directory.deletingLastPathComponent()
            .appendingPathComponent("\(directory.lastPathComponent).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: .forUploading,
            error: &coordinationError
        ) { temporaryZip in
            do {
                if FileManager.default.fileExists(atPath: zipURL.path) {
                    try FileManager.default.removeItem(at: zipURL)
                }
                try FileManager.default.copyItem(at: temporaryZip, to: zipURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return zipURL
    }
}
