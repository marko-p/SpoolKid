//
//  ServerLink.swift
//  SpoolKid
//
//  Purpose: Whether the active filament server can be reached right now, and
//  which failures count. Down means "couldn't reach it": a server that
//  answers, even with an error or a bad certificate, is up.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A request that never reached an answer.
nonisolated enum ServerFailure: Equatable, Sendable {
    /// The request never left: no route, no host, no network.
    case notSent
    /// The request may have arrived; the answer did not. A write may have saved.
    case mayHaveArrived

    /// Nil for anything that is not a reachability failure, including TLS and
    /// certificate errors and cancellation.
    static func classify(_ error: Error) -> ServerFailure? {
        guard let error = error as? URLError else { return nil }
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return .notSent
        case .timedOut, .networkConnectionLost:
            return .mayHaveArrived
        default:
            return nil
        }
    }
}

/// What one request to the server came to.
nonisolated enum TransportReport: Equatable, Sendable {
    case answered
    case failed(ServerFailure)
}

nonisolated enum ServerLink: Equatable, Sendable {
    /// No answer yet. Acts as up.
    case unknown
    case up
    case down

    /// Also what a backend change resets to.
    static let initial = ServerLink.unknown

    var isDown: Bool { self == .down }

    /// An unconfigured backend is not down: it already shows its own
    /// not-connected screen.
    func after(probe: BackendReachability) -> ServerLink {
        probe == .unreachable ? .down : .up
    }

    func after(_ report: TransportReport) -> ServerLink {
        report == .answered ? .up : .down
    }
}
