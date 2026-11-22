//
//  AppMessageTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the message feed format — lenient per entry, strict about
//  dates with an offset and https actions — and the reminder rule.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct AppMessageTests {

    private static func feed(_ json: String) -> [AppMessage]? {
        AppMessage.decodeFeed(Data(json.utf8))
    }

    private static func message(action: String? = nil, reminder: String? = nil) -> AppMessage {
        let actionField = action.map { ", \"action\": \($0)" } ?? ""
        let reminderField = reminder.map { ", \"reminder\": \($0)" } ?? ""
        let json = """
        [{"id": "m", "title": "T", "body": "B",
          "start": "2026-12-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"\(actionField)\(reminderField)}]
        """
        return feed(json)![0]
    }

    @Test func decodesFullMessage() throws {
        let messages = try #require(Self.feed("""
        [{"id": "vote", "title": "Vote for SpoolKid", "body": "Please vote.",
          "image": "messages/vote.png",
          "action": {"label": "Vote on the Forum", "url": "https://forum.snapmaker.com/t/1"},
          "start": "2026-12-01T00:00:00+01:00", "end": "2026-12-15T23:59:00+01:00",
          "reminder": true, "futureField": 42}]
        """))
        #expect(messages.count == 1)
        let message = messages[0]
        #expect(message.id == "vote")
        #expect(message.title == "Vote for SpoolKid")
        #expect(message.image == "messages/vote.png")
        #expect(message.action?.label == "Vote on the Forum")
        #expect(message.action?.url == URL(string: "https://forum.snapmaker.com/t/1"))
        #expect(message.start == ISO8601DateFormatter().date(from: "2026-11-30T23:00:00Z"))
        #expect(message.reminder == true)
    }

    @Test func dropsOnlyTheMalformedEntry() {
        let messages = Self.feed("""
        [{"id": "good", "title": "T", "body": "B",
          "start": "2026-12-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"},
         {"id": "noTitle", "body": "B",
          "start": "2026-12-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"},
         {"id": "dateOnly", "title": "T", "body": "B",
          "start": "2026-12-01", "end": "2026-12-31T00:00:00Z"},
         {"id": "httpAction", "title": "T", "body": "B",
          "action": {"label": "Go", "url": "http://example.com"},
          "start": "2026-12-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"}]
        """)
        #expect(messages?.map(\.id) == ["good"])
    }

    @Test func dropsEntryWhoseStartIsNotBeforeEnd() {
        let messages = Self.feed("""
        [{"id": "m", "title": "T", "body": "B",
          "start": "2026-12-31T00:00:00Z", "end": "2026-12-31T00:00:00Z"}]
        """)
        #expect(messages == [])
    }

    @Test func nonArrayIsNil() {
        #expect(Self.feed("{}") == nil)
        #expect(Self.feed("nope") == nil)
    }

    @Test func emptyArrayIsEmpty() {
        #expect(Self.feed("[]") == [])
    }

    @Test func showsReminderRules() {
        let action = #"{"label": "Go", "url": "https://example.com"}"#
        #expect(Self.message(action: action).showsReminder)
        #expect(!Self.message(action: action, reminder: "false").showsReminder)
        #expect(!Self.message().showsReminder)
    }

    @Test func formattedBodyKeepsBoldAndLink() throws {
        let messages = try #require(Self.feed("""
        [{"id": "m", "title": "T", "body": "**Vote** at [forum](https://forum.snapmaker.com)",
          "start": "2026-12-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"}]
        """))
        let body = messages[0].formattedBody
        let bold = body.runs.first { String(body[$0.range].characters) == "Vote" }
        #expect(bold?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(body.runs.contains { $0.link == URL(string: "https://forum.snapmaker.com") })
    }
}
