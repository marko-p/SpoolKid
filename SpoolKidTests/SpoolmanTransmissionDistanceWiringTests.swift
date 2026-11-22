//
//  SpoolmanTransmissionDistanceWiringTests.swift
//  SpoolKidTests
//
//  Purpose: A filament save carrying TD on Spoolman, end to end through the
//  stubbed transport: the `td` field is registered only when missing, with the
//  exact body; the PATCH merges TD into a FRESH read of the filament's extra.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

/// Every request the stub answered, with its body decoded.
nonisolated final class StubRequestLog: @unchecked Sendable {
    struct Entry { let method: String; let path: String; let body: [String: Any]? }
    private let lock = NSLock()
    private var _entries: [Entry] = []
    var entries: [Entry] { lock.withLock { _entries } }

    func record(_ request: URLRequest) {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&chunk, maxLength: chunk.count)
                guard count > 0 else { break }
                buffer.append(chunk, count: count)
            }
            stream.close()
            data = buffer
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let entry = Entry(method: request.httpMethod ?? "GET", path: request.url?.path ?? "", body: body)
        lock.withLock { _entries.append(entry) }
    }
}

/// An extension of `ServerWebPageWiringTests` so it shares that suite's
/// serialization: `StubURLProtocol.handler` is one global.
extension ServerWebPageWiringTests {
    private static let json = "application/json"
    private static let filamentJSON = #"{"id":7,"name":"Silk","extra":{"variant":"\"Silk\"","td":"3.5"}}"#

    private func spoolmanStub(fields: String, log: StubRequestLog) -> SpoolmanService {
        StubURLProtocol.handler = { request in
            log.record(request)
            switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
            case ("GET", "/api/v1/field/filament"): return .init(status: 200, contentType: Self.json, body: fields)
            case ("POST", "/api/v1/field/filament/td"): return .init(status: 200, contentType: Self.json, body: "[]")
            case ("GET", "/api/v1/filament/7"):
                return .init(status: 200, contentType: Self.json, body: #"{"id":7,"name":"Silk","extra":{"variant":"\"Silk\""}}"#)
            case ("PATCH", "/api/v1/filament/7"): return .init(status: 200, contentType: Self.json, body: Self.filamentJSON)
            default: return .init(status: 404, contentType: Self.json, body: #"{"message":"unexpected"}"#)
            }
        }
        return SpoolmanService(session: StubURLProtocol.session(), authType: { "none" })
    }

    @Test func updateRegistersFieldAndMergesFreshExtra() async throws {
        let log = StubRequestLog()
        let service = spoolmanStub(fields: "[]", log: log)

        let ok = await service.updateFilament(
            id: 7, draft: FilamentDraft(transmissionDistance: .set(3.5)), baseUrl: StubURLProtocol.baseUrl
        )

        #expect(ok)
        let post = try #require(log.entries.first { $0.method == "POST" })
        #expect(post.path == "/api/v1/field/filament/td")
        #expect(post.body?["name"] as? String == "Transmission Distance (TD)")
        #expect(post.body?["field_type"] as? String == "float")
        #expect(post.body?["unit"] as? String == "mm")
        #expect(post.body?["order"] as? Int == 0)
        #expect(post.body?["default_value"] == nil)
        let patch = try #require(log.entries.first { $0.method == "PATCH" })
        #expect(patch.body?["extra"] as? [String: String] == ["variant": "\"Silk\"", "td": "3.5"])
    }

    @Test func existingFieldIsNotReRegistered() async {
        let log = StubRequestLog()
        let service = spoolmanStub(
            fields: #"[{"key":"td","entity_type":"filament","field_type":"float","name":"TD","order":1}]"#, log: log
        )

        let ok = await service.updateFilament(
            id: 7, draft: FilamentDraft(transmissionDistance: .set(3.5)), baseUrl: StubURLProtocol.baseUrl
        )

        #expect(ok)
        #expect(!log.entries.contains { $0.method == "POST" })
    }
}
