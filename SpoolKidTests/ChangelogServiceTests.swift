//
//  ChangelogServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the three-source resolution — bundled floor, disk cache,
//  network overlay — and the rule that a failed fetch changes nothing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct ChangelogServiceTests {

    // MARK: - Fixtures

    private static func entry(_ version: String, _ text: String) -> ChangelogEntry {
        ChangelogEntry(
            version: version,
            date: nil,
            headline: nil,
            changes: [ChangelogChange(kind: .added, text: text)]
        )
    }

    private static func data(_ entries: [ChangelogEntry]) -> Data {
        try! JSONEncoder().encode(entries)
    }

    /// A fresh empty directory per test, so no test sees another's cache.
    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("changelog-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let feedURL = URL(string: "https://example.invalid/changelog.json")!

    // MARK: - Merge

    @Test func mergeKeepsVersionsOnlyTheBundleKnows() {
        let merged = ChangelogService.merge(
            bundled: [Self.entry("0.16", "bundled sixteen")],
            remote: [Self.entry("0.17", "remote seventeen")]
        )
        #expect(merged.map(\.version) == ["0.17", "0.16"])
    }

    @Test func theRemoteCopyWinsForAVersionBothDescribe() {
        let merged = ChangelogService.merge(
            bundled: [Self.entry("0.17", "typo")],
            remote: [Self.entry("0.17", "corrected")]
        )
        #expect(merged.count == 1)
        #expect(merged[0].changes[0].text == "corrected")
    }

    @Test func theRemoteCopyWinsEvenWhenItSpellsTheVersionDifferently() {
        // ReleaseVersion treats 0.17 and 0.17.0 as one version. Keying the
        // merge on the raw string would show both, in arbitrary order,
        // instead of letting the remote copy correct the bundled one.
        let merged = ChangelogService.merge(
            bundled: [Self.entry("0.17", "typo")],
            remote: [Self.entry("0.17.0", "corrected")]
        )
        #expect(merged.count == 1)
        #expect(merged[0].changes[0].text == "corrected")
    }

    @Test func mergeSortsNumericallyNotAlphabetically() {
        let merged = ChangelogService.merge(
            bundled: [Self.entry("0.9", "nine"), Self.entry("0.17", "seventeen")],
            remote: []
        )
        #expect(merged.map(\.version) == ["0.17", "0.9"])
    }

    // MARK: - Loading

    @Test @MainActor func withNoCacheTheBundledCopyIsWhatIsPublished() {
        let service = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: Self.temporaryDirectory(),
            url: Self.feedURL,
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )
        #expect(service.entries.map(\.version) == ["0.17"])
    }

    @Test @MainActor func aFailedFetchLeavesTheEntriesUntouched() async {
        let service = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: Self.temporaryDirectory(),
            url: Self.feedURL,
            fetch: { _ in throw URLError(.timedOut) }
        )
        await service.refresh()
        #expect(service.entries.map(\.version) == ["0.17"])
        #expect(service.entries[0].changes[0].text == "bundled")
    }

    @Test @MainActor func undecodableRemoteDataIsIgnoredRatherThanPublished() async {
        let service = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: Self.temporaryDirectory(),
            url: Self.feedURL,
            fetch: { _ in Data("not json".utf8) }
        )
        await service.refresh()
        #expect(service.entries.map(\.version) == ["0.17"])
    }

    @Test @MainActor func aSuccessfulFetchIsPublishedAndSurvivesIntoTheNextLaunch() async {
        let directory = Self.temporaryDirectory()
        let remote = Self.data([Self.entry("0.18", "remote eighteen")])

        let first = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: directory,
            url: Self.feedURL,
            fetch: { _ in remote }
        )
        await first.refresh()
        #expect(first.entries.map(\.version) == ["0.18", "0.17"])

        // A second instance over the same directory, with the network gone.
        let second = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: directory,
            url: Self.feedURL,
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )
        #expect(second.entries.map(\.version) == ["0.18", "0.17"])
    }

    @Test @MainActor func aCorruptCacheFallsBackToTheBundledCopy() {
        let directory = Self.temporaryDirectory()
        try! Data("garbage".utf8).write(to: directory.appendingPathComponent("changelog.json"))

        let service = ChangelogService(
            bundledData: Self.data([Self.entry("0.17", "bundled")]),
            cacheDirectory: directory,
            url: Self.feedURL,
            fetch: { _ in throw URLError(.timedOut) }
        )
        #expect(service.entries.map(\.version) == ["0.17"])
    }
}
