//
//  MoonrakerSocket.swift
//  SpoolKid
//
//  Purpose: Moonraker's JSON-RPC over a WebSocket. Replies are matched to calls
//  by id; everything else is a notification for `onNotification`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A parsed JSON value crossing an `await`. It is only ever read on the main actor.
struct MoonrakerValue: @unchecked Sendable {
    let value: Any
}

nonisolated enum MoonrakerError: LocalizedError, Equatable {
    case notConnected
    case timedOut
    case rejected(String)
    /// JSON-RPC error 401: the printer wants a sign-in, or refused this one.
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "The printer is not connected."
        case .timedOut: "The printer did not answer."
        case .rejected(let message), .unauthorized(let message): message
        }
    }
}

/// The seam `PrinterService` is tested through.
@MainActor
protocol PrinterTransport: AnyObject {
    var onNotification: ((String, [Any]) -> Void)? { get set }
    var onClosed: (() -> Void)? { get set }
    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue
    /// As `call`, waiting up to `timeout` for the reply instead of the socket's default.
    func call(_ method: String, params: [String: Any], timeout: Duration) async throws -> MoonrakerValue
    func close()
}

extension PrinterTransport {
    /// Transports with no timeout of their own ignore it.
    func call(_ method: String, params: [String: Any], timeout: Duration) async throws -> MoonrakerValue {
        try await call(method, params: params)
    }
}

@MainActor
final class MoonrakerSocket: PrinterTransport {
    var onNotification: ((String, [Any]) -> Void)?
    var onClosed: (() -> Void)?

    private let task: URLSessionWebSocketTask
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<MoonrakerValue, Error>] = [:]
    private var isClosed = false
    /// Long enough for a `FILAMENT_DT_UPDATE` to finish reading a tag.
    private static let timeout: Duration = .seconds(20)

    init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.resume()
        receive()
    }

    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue {
        try await call(method, params: params, timeout: Self.timeout)
    }

    func call(_ method: String, params: [String: Any], timeout: Duration) async throws -> MoonrakerValue {
        guard !isClosed else { throw MoonrakerError.notConnected }
        let id = nextID
        nextID += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": id]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            task.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in self?.finish(id, .failure(error)) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(id, .failure(MoonrakerError.timedOut))
            }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
        for continuation in pending.values { continuation.resume(throwing: MoonrakerError.notConnected) }
        pending.removeAll()
    }

    private func finish(_ id: Int, _ result: Result<MoonrakerValue, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func receive() {
        task.receive { [weak self] result in
            let text: String? = switch result {
            case .success(.string(let string)): string
            case .success(.data(let data)): String(data: data, encoding: .utf8)
            default: nil
            }
            let failed = if case .failure = result { true } else { false }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if failed {
                    self.close()
                    self.onClosed?()
                    return
                }
                if let text { self.handle(text) }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        if let id = json["id"] as? Int {
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "The printer refused this."
                let failure = error["code"] as? Int == 401
                    ? MoonrakerError.unauthorized(message) : .rejected(message)
                finish(id, .failure(failure))
            } else {
                finish(id, .success(MoonrakerValue(value: json["result"] ?? NSNull())))
            }
        } else if let method = json["method"] as? String {
            onNotification?(method, json["params"] as? [Any] ?? [])
        }
    }
}
