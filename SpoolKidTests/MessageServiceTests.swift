//
//  MessageServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Locks which message is owed and which leave a Home card, that
//  seen and acted survive a relaunch, that images gate a message, and that a
//  failed fetch changes nothing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
import UIKit
import Combine
@testable import SpoolKid

@MainActor
struct MessageServiceTests {

    // MARK: - Fixtures

    nonisolated private static let now = ISO8601DateFormatter().date(from: "2026-12-10T12:00:00Z")!
    nonisolated private static let day: TimeInterval = 86_400
    nonisolated private static let feedURL = URL(string: "https://example.invalid/messages/messages.json")!
    nonisolated private static let base = URL(string: "https://example.invalid/")!
    private static let action = AppMessage.Action(label: "Vote", url: URL(string: "https://forum.example/vote")!)

    private static func message(
        _ id: String,
        startDaysAgo: Double = 1,
        endDaysAhead: Double = 5,
        image: String? = nil,
        action: AppMessage.Action? = nil,
        reminder: Bool? = nil
    ) -> AppMessage {
        AppMessage(
            id: id, title: "Title \(id)", body: "Body", image: image, action: action,
            start: now.addingTimeInterval(-startDaysAgo * day),
            end: now.addingTimeInterval(endDaysAhead * day),
            reminder: reminder
        )
    }

    private static func feed(_ messages: [AppMessage]) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(messages)
    }

    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }

    nonisolated private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("message-tests-\(UUID().uuidString)")
    }

    nonisolated private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "message-tests-\(UUID().uuidString)")!
    }

    /// The network, as a table of responses, recording every request.
    nonisolated final class Network: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [URL: Data] = [:]
        private var log: [URL] = []

        func serve(_ data: Data?, at url: URL) {
            lock.withLock { responses[url] = data }
        }

        var requests: [URL] { lock.withLock { log } }

        var fetch: RemoteFile.Fetch {
            { [self] url in
                try lock.withLock {
                    log.append(url)
                    guard let data = responses[url] else { throw URLError(.notConnectedToInternet) }
                    return data
                }
            }
        }
    }

    nonisolated final class Clock: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private static func service(
        directory: URL? = temporaryDirectory(),
        defaults: UserDefaults = defaults(),
        network: Network = Network(),
        clock: Clock = Clock(now)
    ) -> MessageService {
        MessageService(
            cacheDirectory: directory, feedURL: feedURL, imageBaseURL: base,
            defaults: defaults, now: { clock.date }, fetch: network.fetch, isEnabled: true
        )
    }

    // MARK: - Owed

    @Test func owedPicksEarliestStartAmongLive() {
        let messages = [
            Self.message("b", startDaysAgo: 1),
            Self.message("a", startDaysAgo: 3),
            Self.message("c", startDaysAgo: 2),
        ]
        let owed = MessageService.owed(messages, seen: [], ready: ["a", "b", "c"], now: Self.now)
        #expect(owed?.id == "a")
    }

    @Test func owedSkipsSeenNotReadyFutureAndEnded() {
        let messages = [
            Self.message("seen"),
            Self.message("notReady"),
            Self.message("future", startDaysAgo: -1),
            Self.message("ended", startDaysAgo: 5, endDaysAhead: -1),
        ]
        let owed = MessageService.owed(
            messages, seen: ["seen"], ready: ["seen", "future", "ended"], now: Self.now
        )
        #expect(owed == nil)
    }

    @Test func owedEndIsExclusive() {
        let atEnd = Self.message("m", startDaysAgo: 1, endDaysAhead: 0)
        #expect(MessageService.owed([atEnd], seen: [], ready: ["m"], now: Self.now) == nil)
        let atStart = Self.message("m", startDaysAgo: 0, endDaysAhead: 1)
        #expect(MessageService.owed([atStart], seen: [], ready: ["m"], now: Self.now)?.id == "m")
    }

    @Test func owedStaysOwedUntilMarkedSeen() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m")]), at: Self.feedURL)
        let directory = Self.temporaryDirectory()
        let defaults = Self.defaults()
        await Self.service(directory: directory, defaults: defaults, network: network).refresh()

        let service = Self.service(directory: directory, defaults: defaults)  // network gone
        #expect(service.owedMessage?.id == "m")
        await service.refresh()
        #expect(service.owedMessage?.id == "m")
        service.markSeen("m")
        #expect(service.owedMessage == nil)
    }

    // MARK: - Reminders

    @Test func remindersEndExclusive() {
        let message = Self.message("m", startDaysAgo: 1, endDaysAhead: 1, action: Self.action)
        let justBefore = message.end.addingTimeInterval(-1)
        #expect(MessageService.reminders([message], seen: ["m"], acted: [], now: justBefore).map(\.id) == ["m"])
        #expect(MessageService.reminders([message], seen: ["m"], acted: [], now: message.end).isEmpty)
    }

    @Test func remindersExcludeActedUnseenAndNoReminder() {
        let messages = [
            Self.message("acted", action: Self.action),
            Self.message("unseen", action: Self.action),
            Self.message("off", action: Self.action, reminder: false),
            Self.message("noAction"),
        ]
        let reminders = MessageService.reminders(
            messages, seen: ["acted", "off", "noAction"], acted: ["acted"], now: Self.now
        )
        #expect(reminders.isEmpty)
    }

    @Test func removedMessageLosesItsCard() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", action: Self.action)]), at: Self.feedURL)
        let service = Self.service(network: network)
        await service.refresh()
        service.markSeen("m")
        #expect(service.reminders.map(\.id) == ["m"])

        network.serve(Self.feed([]), at: Self.feedURL)
        await service.refresh()
        #expect(service.reminders.isEmpty)
        #expect(service.seenIDs.contains("m"))
    }

    // MARK: - Image paths

    @Test func imageURLRejectsEscapes() {
        let base = AppConfig.publicRawBaseURL
        #expect(MessageService.imageURL(for: "https://evil.example/x.png", base: base) == nil)
        #expect(MessageService.imageURL(for: "/x.png", base: base) == nil)
        #expect(MessageService.imageURL(for: "messages/../x.png", base: base) == nil)
        #expect(MessageService.imageURL(for: "", base: base) == nil)
        #expect(
            MessageService.imageURL(for: "messages/vote.png", base: base)
                == URL(string: "https://raw.githubusercontent.com/marko-p/SpoolKid/main/messages/vote.png")
        )
    }

    // MARK: - Fetching

    @Test func refreshLoadsFeedAndImage() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", image: "messages/m.png")]), at: Self.feedURL)
        network.serve(Self.png, at: Self.base.appending(path: "messages/m.png"))
        let directory = Self.temporaryDirectory()
        let service = Self.service(directory: directory, network: network)
        await service.refresh()
        #expect(service.messages.count == 1)
        #expect(service.readyIDs == ["m"])
        #expect(service.image(for: service.messages[0]) != nil)

        let relaunched = Self.service(directory: directory)
        #expect(relaunched.messages.map(\.id) == ["m"])
        #expect(relaunched.readyIDs == ["m"])
    }

    @Test func failedFetchKeepsCachedMessages() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", image: "messages/m.png")]), at: Self.feedURL)
        network.serve(Self.png, at: Self.base.appending(path: "messages/m.png"))
        let service = Self.service(network: network)
        await service.refresh()

        network.serve(nil, at: Self.feedURL)
        network.serve(nil, at: Self.base.appending(path: "messages/m.png"))
        await service.refresh()
        #expect(service.messages.map(\.id) == ["m"])
        #expect(service.readyIDs == ["m"])
    }

    @Test func oversizeOrInvalidImageIsNotReady() async {
        let network = Network()
        network.serve(
            Self.feed([Self.message("big", image: "big.png"), Self.message("junk", image: "junk.png")]),
            at: Self.feedURL
        )
        network.serve(Data(count: MessageService.maxImageByteCount + 1), at: Self.base.appending(path: "big.png"))
        network.serve(Data("x".utf8), at: Self.base.appending(path: "junk.png"))
        let service = Self.service(network: network)
        await service.refresh()
        #expect(service.readyIDs.isEmpty)
        #expect(service.owedMessage == nil)
    }

    @Test func messageWithBadImagePathIsNeverReady() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", image: "https://evil.example/x.png")]), at: Self.feedURL)
        let service = Self.service(network: network)
        await service.refresh()
        #expect(!network.requests.contains { $0.host == "evil.example" })
        #expect(service.readyIDs.isEmpty)
    }

    @Test func endedMessageImageIsNotFetched() async {
        let network = Network()
        network.serve(
            Self.feed([Self.message("m", startDaysAgo: 5, endDaysAhead: -1, image: "m.png")]),
            at: Self.feedURL
        )
        let service = Self.service(network: network)
        await service.refresh()
        #expect(network.requests == [Self.feedURL])
    }

    @Test func cachedImageIsNotRefetched() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", image: "m.png")]), at: Self.feedURL)
        network.serve(Self.png, at: Self.base.appending(path: "m.png"))
        let service = Self.service(network: network)
        await service.refresh()
        await service.refresh()
        #expect(network.requests.filter { $0.lastPathComponent == "m.png" }.count == 1)
    }

    // MARK: - Launch sheet gate

    @Test func launchSheetWaitsUntilLaunchSheetsSettle() {
        let owed = Self.message("a")
        #expect(MessageService.launchSheet(owed: owed, shownThisLaunch: nil, settled: false) == nil)
        #expect(MessageService.launchSheet(owed: owed, shownThisLaunch: nil, settled: true)?.id == "a")
    }

    @Test func launchSheetShowsOnlyOneMessagePerLaunch() {
        let next = Self.message("b")
        #expect(MessageService.launchSheet(owed: next, shownThisLaunch: "a", settled: true) == nil)
    }

    @Test func launchSheetKeepsTheMessageAlreadyOnScreen() {
        let shown = Self.message("a")
        #expect(MessageService.launchSheet(owed: shown, shownThisLaunch: "a", settled: true)?.id == "a")
    }

    @Test func didPresentRecordsTheLaunchMessage() async {
        let network = Network()
        network.serve(Self.feed([Self.message("a", startDaysAgo: 2), Self.message("b")]), at: Self.feedURL)
        let service = Self.service(network: network)
        await service.refresh()
        #expect(service.launchSheetMessage(settled: true)?.id == "a")
        service.didPresent("a")
        service.markSeen("a")
        #expect(service.owedMessage?.id == "b")
        #expect(service.launchSheetMessage(settled: true) == nil)
    }

    // MARK: - Time passing

    @Test func throttledRefreshStillRepublishes() async {
        let network = Network()
        network.serve(Self.feed([]), at: Self.feedURL)
        let service = Self.service(network: network)
        await service.refresh()
        var changes = 0
        let subscription = service.objectWillChange.sink { changes += 1 }
        await service.refreshIfDue()   // throttled: no fetch
        #expect(network.requests.count == 1)
        #expect(changes == 1)
        subscription.cancel()
    }

    // MARK: - Tests and UI tests

    @Test func isEnabledRules() {
        #expect(MessageService.isEnabled(environment: [:], arguments: []))
        #expect(!MessageService.isEnabled(environment: ["XCTestConfigurationFilePath": "/x"], arguments: []))
        #expect(!MessageService.isEnabled(environment: [:], arguments: ["-disableMessages", "YES"]))
    }

    @Test func disabledServiceShowsAndFetchesNothing() async {
        let network = Network()
        network.serve(Self.feed([Self.message("m", action: Self.action)]), at: Self.feedURL)
        let directory = Self.temporaryDirectory()
        await Self.service(directory: directory, network: network).refresh()  // cache it

        let disabled = MessageService(
            cacheDirectory: directory, feedURL: Self.feedURL, imageBaseURL: Self.base,
            defaults: Self.defaults(), now: { Self.now }, fetch: network.fetch, isEnabled: false
        )
        let requestsBefore = network.requests.count
        await disabled.refresh()
        #expect(disabled.messages.isEmpty)
        #expect(disabled.owedMessage == nil)
        #expect(network.requests.count == requestsBefore)
    }

    // MARK: - Persistence and throttle

    @Test func seenAndActedPersist() {
        let defaults = Self.defaults()
        Self.service(defaults: defaults).markActed("a")
        let relaunched = Self.service(defaults: defaults)
        #expect(relaunched.actedIDs == ["a"])
        #expect(relaunched.seenIDs.contains("a"))
    }

    @Test func refreshIfDueThrottles() async {
        let network = Network()
        network.serve(Self.feed([]), at: Self.feedURL)
        let clock = Clock(Self.now)
        let service = Self.service(network: network, clock: clock)
        await service.refresh()

        clock.date = Self.now.addingTimeInterval(MessageService.refreshInterval - 1)
        await service.refreshIfDue()
        #expect(network.requests.count == 1)

        clock.date = Self.now.addingTimeInterval(MessageService.refreshInterval)
        await service.refreshIfDue()
        #expect(network.requests.count == 2)
    }
}
