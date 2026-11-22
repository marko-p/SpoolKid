//
//  ChangelogService.swift
//  SpoolKid
//
//  Purpose: Resolves the release notes from three sources — the bundled file,
//  a disk cache, and the public repo — and publishes one merged list.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine

/// Small and stateful, so an `ObservableObject` rather than a static enum (A3).
///
/// The bundled copy is the floor: it always describes the version the user is
/// running, so the sheet never has to show a loading or error state. The cache
/// and the network only ever add to it.
@MainActor
final class ChangelogService: ObservableObject {

    @Published private(set) var entries: [ChangelogEntry]

    private let bundledEntries: [ChangelogEntry]
    private let cacheDirectory: URL?
    private let url: URL
    private let fetch: @Sendable (URL) async throws -> Data

    private var cacheFile: URL? {
        cacheDirectory?.appendingPathComponent("changelog.json")
    }

    /// The real file is a few KB; this is a ceiling against a compromised or
    /// misconfigured host pushing an arbitrarily large body on every launch.
    nonisolated static let maxFetchByteCount = 1_000_000

    // MARK: - Init

    /// The production initializer. Everything is injectable so no test touches
    /// the network or the real Application Support directory.
    convenience init(
        bundle: Bundle = .main,
        cacheDirectory: URL? = ChangelogService.defaultCacheDirectory(),
        url: URL = AppConfig.changelogURL,
        fetch: @escaping RemoteFile.Fetch = RemoteFile.httpFetch(maxByteCount: ChangelogService.maxFetchByteCount)
    ) {
        let bundled = bundle.url(forResource: "Changelog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        self.init(bundledData: bundled, cacheDirectory: cacheDirectory, url: url, fetch: fetch)
    }

    init(
        bundledData: Data?,
        cacheDirectory: URL?,
        url: URL,
        fetch: @escaping @Sendable (URL) async throws -> Data
    ) {
        self.bundledEntries = bundledData.flatMap(Self.decode) ?? []
        self.cacheDirectory = cacheDirectory
        self.url = url
        self.fetch = fetch

        let cached = cacheDirectory
            .map { $0.appendingPathComponent("changelog.json") }
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(Self.decode) ?? []

        self.entries = Self.merge(bundled: bundledEntries, remote: cached)
    }

    // MARK: - Refresh

    /// Fetches the public copy. Any failure — offline, a 404, a file that does
    /// not decode — is logged and changes nothing: the user keeps the notes
    /// they already had.
    func refresh() async {
        let file = RemoteFile(url: url, cacheFile: cacheFile, logCategory: "Changelog", fetch: fetch)
        guard let data = await file.refresh(accept: { Self.decode($0) != nil }),
              let remote = Self.decode(data) else { return }
        entries = Self.merge(bundled: bundledEntries, remote: remote)
    }

    // MARK: - Pure helpers

    nonisolated static func decode(_ data: Data) -> [ChangelogEntry]? {
        try? JSONDecoder().decode([ChangelogEntry].self, from: data)
    }

    /// Union by version, newest first. For a version both sources describe, the
    /// remote copy wins — that is how a typo gets fixed without a build. A
    /// remote file that omits older versions cannot erase them.
    ///
    /// Keyed on `release` (`ReleaseVersion`), not the raw `version` string:
    /// `ReleaseVersion` treats "0.17" and "0.17.0" as the same version, and
    /// keying on the string would let a remote file spelling it differently
    /// add a second section instead of correcting the bundled one.
    nonisolated static func merge(
        bundled: [ChangelogEntry],
        remote: [ChangelogEntry]
    ) -> [ChangelogEntry] {
        var byRelease: [ReleaseVersion: ChangelogEntry] = [:]
        for entry in bundled { byRelease[entry.release] = entry }
        for entry in remote { byRelease[entry.release] = entry }
        return byRelease.values.sorted { $0.release > $1.release }
    }

    /// Which entries this launch owes the user.
    ///
    /// Pure so the decision is testable without a sheet — the same shape
    /// `ContentView.needsBackendRebuild` established.
    ///
    /// - Parameter lastShown: `""` means no version has ever been shown. That
    ///   is both a fresh install and the first launch of the build that added
    ///   this feature; neither is owed a history dump.
    nonisolated static func entriesToPresent(
        installed: String,
        lastShown: String,
        autoShow: Bool,
        entries: [ChangelogEntry]
    ) -> [ChangelogEntry] {
        guard autoShow, !lastShown.isEmpty else { return [] }
        let floor = ReleaseVersion(lastShown)
        let ceiling = ReleaseVersion(installed)
        return entries
            .filter { $0.release > floor && $0.release <= ceiling }
            .sorted { $0.release > $1.release }
    }

    // MARK: - Locations

    /// `Application Support/Changelog`, following `DiagnosticCaptureStore`.
    /// `nil` if the directory cannot be resolved — the bundled copy still works.
    nonisolated static func defaultCacheDirectory() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Changelog")
    }
}
