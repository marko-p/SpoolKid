//
//  RemoteFile.swift
//  SpoolKid
//
//  Purpose: One small file fetched from the public repo and cached on disk —
//  the shared plumbing behind the release notes and the in-app messages.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

/// Fetch → accept → cache. Only data the caller accepts reaches the cache, and
/// any failure — offline, a non-200, a body over the ceiling, data the caller
/// rejects, a cache write that fails — is logged and leaves the cache as it was.
nonisolated struct RemoteFile: Sendable {

    typealias Fetch = @Sendable (URL) async throws -> Data

    let url: URL
    let cacheFile: URL?
    let logCategory: String
    let fetch: Fetch

    /// A plain GET that accepts only HTTP 200 and a body no larger than
    /// `maxByteCount` — a ceiling against a compromised or misconfigured host
    /// pushing an arbitrarily large body on every launch.
    static func httpFetch(maxByteCount: Int) -> Fetch {
        { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard data.count <= maxByteCount else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            return data
        }
    }

    func cachedData() -> Data? {
        cacheFile.flatMap { try? Data(contentsOf: $0) }
    }

    /// The fetched data when `accept` takes it, else nil. Accepted data is
    /// cached even if returning it is all the caller does with it.
    func refresh(accept: (Data) -> Bool) async -> Data? {
        let logger = Logger(subsystem: "com.spoolkid", category: logCategory)
        let data: Data
        do {
            data = try await fetch(url)
        } catch {
            logger.error("Fetch of \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard accept(data) else {
            logger.error("\(url.lastPathComponent, privacy: .public) did not validate; keeping what we have")
            return nil
        }
        if let cacheFile {
            do {
                try FileManager.default.createDirectory(
                    at: cacheFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: cacheFile, options: .atomic)
            } catch {
                logger.error("Cache write for \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return data
    }
}
