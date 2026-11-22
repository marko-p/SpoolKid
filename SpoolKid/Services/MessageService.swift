//
//  MessageService.swift
//  SpoolKid
//
//  Purpose: Fetches the owner's messages and their images from the public
//  repo, remembers which ones this person has seen and acted on, and decides
//  which message is owed and which leave a card on Home.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import UIKit
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "Messages")

/// Messages are independent of the support prompts: nothing here reads or
/// writes a `support_*` key, and there is no opt-out (owner, 2026-11-21).
@MainActor
final class MessageService: ObservableObject {

    /// Also the ceiling for the feed itself, which is a few KB.
    nonisolated static let maxImageByteCount = 2_000_000
    /// How often a return to the foreground may refetch.
    nonisolated static let refreshInterval: TimeInterval = 3_600

    /// From the cache at launch, replaced by every fetch that decodes.
    @Published private(set) var messages: [AppMessage]
    @Published private(set) var seenIDs: Set<String>
    @Published private(set) var actedIDs: Set<String>
    /// Messages with no image, or whose image is cached. Only these can be owed:
    /// a sheet must never appear with its picture missing.
    @Published private(set) var readyIDs: Set<String> = []
    /// The message the launch sheet showed in this run of the app. In memory
    /// only: one message per launch, and the next waits for the next launch.
    @Published private(set) var shownThisLaunch: String?

    private let feed: RemoteFile
    private let imageBaseURL: URL
    private let imageDirectory: URL?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let fetch: RemoteFile.Fetch
    private let isEnabled: Bool
    private var lastRefresh: Date?

    init(
        cacheDirectory: URL? = MessageService.defaultCacheDirectory(),
        feedURL: URL = AppConfig.messagesURL,
        imageBaseURL: URL = AppConfig.publicRawBaseURL,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping RemoteFile.Fetch = RemoteFile.httpFetch(maxByteCount: MessageService.maxImageByteCount),
        isEnabled: Bool = MessageService.isEnabled(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    ) {
        self.feed = RemoteFile(
            url: feedURL,
            cacheFile: cacheDirectory?.appendingPathComponent("messages.json"),
            logCategory: "Messages",
            fetch: fetch
        )
        self.imageBaseURL = imageBaseURL
        self.imageDirectory = cacheDirectory?.appendingPathComponent("images")
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        self.isEnabled = isEnabled
        self.messages = isEnabled ? feed.cachedData().flatMap(AppMessage.decodeFeed) ?? [] : []
        self.seenIDs = Set(defaults.stringArray(forKey: AppConfig.messagesSeenIDsKey) ?? [])
        self.actedIDs = Set(defaults.stringArray(forKey: AppConfig.messagesActedIDsKey) ?? [])
        self.readyIDs = computeReadyIDs()
    }

    // MARK: - What to show

    var owedMessage: AppMessage? {
        Self.owed(messages, seen: seenIDs, ready: readyIDs, now: now())
    }

    var reminders: [AppMessage] {
        Self.reminders(messages, seen: seenIDs, acted: actedIDs, now: now())
    }

    /// What the root's launch sheet shows, given whether every other launch
    /// sheet has had its turn (`settled`).
    func launchSheetMessage(settled: Bool) -> AppMessage? {
        Self.launchSheet(owed: owedMessage, shownThisLaunch: shownThisLaunch, settled: settled)
    }

    /// Called when the launch sheet is actually on screen.
    func didPresent(_ id: String) {
        shownThisLaunch = id
    }

    func image(for message: AppMessage) -> UIImage? {
        imageFile(for: message).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    // MARK: - Answers

    func markSeen(_ id: String) {
        seenIDs.insert(id)
        defaults.set(Array(seenIDs).sorted(), forKey: AppConfig.messagesSeenIDsKey)
    }

    /// Tapping the action also counts as having seen the message.
    func markActed(_ id: String) {
        actedIDs.insert(id)
        defaults.set(Array(actedIDs).sorted(), forKey: AppConfig.messagesActedIDsKey)
        markSeen(id)
    }

    // MARK: - Fetching

    /// The feed, then the missing image of every message that has not ended.
    /// Any failure is logged and changes nothing the user can see.
    func refresh() async {
        guard isEnabled else { return }
        lastRefresh = now()
        if let data = await feed.refresh(accept: { AppMessage.decodeFeed($0) != nil }),
           let fetched = AppMessage.decodeFeed(data) {
            messages = fetched
        }
        let current = now()
        for message in messages where current < message.end && imageFile(for: message) == nil {
            await fetchImage(for: message)
        }
        readyIDs = computeReadyIDs()
    }

    /// `refresh()`, unless the last one was under `refreshInterval` ago. A
    /// throttled call still republishes: what is owed and which cards show
    /// depend on the clock, and a card must not outlive its message's end
    /// just because nothing was fetched.
    func refreshIfDue() async {
        if let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.refreshInterval {
            objectWillChange.send()
            return
        }
        await refresh()
    }

    private func fetchImage(for message: AppMessage) async {
        guard let path = message.image,
              let url = Self.imageURL(for: path, base: imageBaseURL),
              let file = imageCacheFile(for: path) else { return }
        do {
            let data = try await fetch(url)
            guard data.count <= Self.maxImageByteCount, UIImage(data: data) != nil else {
                logger.error("Image for message \(message.id, privacy: .public) is too large or not an image")
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Image for message \(message.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Image files

    private func computeReadyIDs() -> Set<String> {
        Set(messages.filter { $0.image == nil || imageFile(for: $0) != nil }.map(\.id))
    }

    /// The cached image, if it is on disk.
    private func imageFile(for message: AppMessage) -> URL? {
        guard let path = message.image, let file = imageCacheFile(for: path),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// Where an image is cached; nil for a path `imageURL` would refuse.
    private func imageCacheFile(for path: String) -> URL? {
        guard Self.imageURL(for: path, base: imageBaseURL) != nil else { return nil }
        return imageDirectory?.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    // MARK: - Rules

    /// Nothing until the other launch sheets have settled, and only one message
    /// per launch: once one has been shown, a different owed message waits for
    /// the next launch. The one already on screen keeps its sheet.
    nonisolated static func launchSheet(
        owed: AppMessage?,
        shownThisLaunch: String?,
        settled: Bool
    ) -> AppMessage? {
        guard settled, let owed else { return nil }
        if let shownThisLaunch, shownThisLaunch != owed.id { return nil }
        return owed
    }

    /// False in the unit-test host and when UI tests pass `-disableMessages`:
    /// a live message would otherwise cover the app in every test run.
    nonisolated static func isEnabled(environment: [String: String], arguments: [String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        return !arguments.contains(AppConfig.disableMessagesArgument)
    }

    /// The live, unseen, ready message with the earliest start; ties keep feed order.
    nonisolated static func owed(
        _ messages: [AppMessage],
        seen: Set<String>,
        ready: Set<String>,
        now: Date
    ) -> AppMessage? {
        messages
            .filter { $0.start <= now && now < $0.end && !seen.contains($0.id) && ready.contains($0.id) }
            .min { $0.start < $1.start }
    }

    /// Seen but not acted on, still live, with an action and its reminder on.
    nonisolated static func reminders(
        _ messages: [AppMessage],
        seen: Set<String>,
        acted: Set<String>,
        now: Date
    ) -> [AppMessage] {
        messages.filter {
            $0.showsReminder && seen.contains($0.id) && !acted.contains($0.id)
                && $0.start <= now && now < $0.end
        }
    }

    /// An image path resolves only inside the public repo: never another host,
    /// an absolute path, or a `..` that climbs out of it.
    nonisolated static func imageURL(for path: String, base: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(":"),
              !path.split(separator: "/").contains("..") else { return nil }
        return base.appending(path: path)
    }

    /// `Application Support/Messages`, beside the changelog's cache.
    nonisolated static func defaultCacheDirectory() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Messages")
    }
}
