//
//  RemoteFileTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the shared fetch → accept → cache contract: only accepted
//  data reaches the cache, and any failure leaves the cache as it was.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct RemoteFileTests {

    private static let url = URL(string: "https://example.invalid/file.json")!

    /// A cache file inside a directory that does not exist yet, so the
    /// helper's own directory creation is exercised too.
    private static func cacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-file-tests-\(UUID().uuidString)")
            .appendingPathComponent("file.json")
    }

    private static func write(_ text: String, to file: URL) {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(text.utf8).write(to: file)
    }

    @Test func refreshWritesAcceptedDataToCache() async {
        let file = RemoteFile(
            url: Self.url, cacheFile: Self.cacheFile(), logCategory: "Test",
            fetch: { _ in Data("ok".utf8) }
        )
        let result = await file.refresh(accept: { _ in true })
        #expect(result == Data("ok".utf8))
        #expect(file.cachedData() == Data("ok".utf8))
    }

    @Test func refreshRejectedByAcceptLeavesCache() async {
        let cache = Self.cacheFile()
        Self.write("old", to: cache)
        let file = RemoteFile(
            url: Self.url, cacheFile: cache, logCategory: "Test",
            fetch: { _ in Data("new".utf8) }
        )
        let result = await file.refresh(accept: { _ in false })
        #expect(result == nil)
        #expect(file.cachedData() == Data("old".utf8))
    }

    @Test func refreshFailureLeavesCache() async {
        let cache = Self.cacheFile()
        Self.write("old", to: cache)
        let file = RemoteFile(
            url: Self.url, cacheFile: cache, logCategory: "Test",
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )
        let result = await file.refresh(accept: { _ in true })
        #expect(result == nil)
        #expect(file.cachedData() == Data("old".utf8))
    }

    @Test func nilCacheFileStillReturnsData() async {
        let file = RemoteFile(
            url: Self.url, cacheFile: nil, logCategory: "Test",
            fetch: { _ in Data("ok".utf8) }
        )
        let result = await file.refresh(accept: { _ in true })
        #expect(result == Data("ok".utf8))
        #expect(file.cachedData() == nil)
    }
}
