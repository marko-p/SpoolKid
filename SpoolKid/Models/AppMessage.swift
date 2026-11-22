//
//  AppMessage.swift
//  SpoolKid
//
//  Purpose: One owner-to-user message from the public messages feed.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A message the owner publishes in `messages/messages.json`. Dates are full
/// ISO-8601 timestamps with an offset; `end` is exclusive.
nonisolated struct AppMessage: Codable, Equatable, Identifiable, Sendable {

    nonisolated struct Action: Codable, Equatable, Sendable {
        let label: String
        let url: URL
    }

    let id: String
    let title: String
    let body: String
    /// A path in the public repo, relative to its root.
    let image: String?
    let action: Action?
    let start: Date
    let end: Date
    /// Whether closing without acting leaves a Home card. Absent means yes.
    let reminder: Bool?

    var showsReminder: Bool {
        action != nil && reminder != false
    }

    /// Bold, italic and links; blank lines stay paragraph breaks. A body that
    /// does not parse is shown as plain text rather than not at all.
    var formattedBody: AttributedString {
        (try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(body)
    }

    /// The feed, entry by entry: an entry that does not decode, whose action is
    /// not https, or whose start is not before its end is dropped on its own.
    /// Nil only when the data is not a JSON array at all.
    static func decodeFeed(_ data: Data) -> [AppMessage]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([Lenient].self, from: data) else { return nil }
        return entries.compactMap(\.message).filter { message in
            message.start < message.end && (message.action.map { $0.url.scheme == "https" } ?? true)
        }
    }

    /// Decodes whatever it is given, keeping the message only if it decoded.
    private struct Lenient: Decodable {
        let message: AppMessage?
        init(from decoder: Decoder) throws {
            message = try? AppMessage(from: decoder)
        }
    }
}
