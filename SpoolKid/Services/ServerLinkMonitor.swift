//
//  ServerLinkMonitor.swift
//  SpoolKid
//
//  Purpose: The one live answer to "can the filament server be reached?" Fed
//  by probes (launch, foreground, every 30 s while down) and by every request
//  the two HTTP services make. Views read it through `\.serverLink`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "ServerLink")

/// A write's result when the server may have stored it without answering.
nonisolated enum WriteOutcome<T> {
    case saved(T)
    case failed
    /// The request may have arrived; nobody knows whether it saved.
    case unknown

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
final class ServerLinkMonitor: ObservableObject {
    static let reprobeInterval = Duration.seconds(30)

    @Published private(set) var link: ServerLink = .initial
    /// The first probe's answer since launch or a backend change.
    @Published private(set) var launchAnswer: Bool?
    /// Every down → up change. Starts its own work.
    var onRecovered: (@MainActor () -> Void)?

    private let probe: () async -> BackendReachability
    private let sleep: (Duration) async -> Void
    private var answeredSerial = 0
    private var mayHaveArrivedSerial = 0
    private var failedSerial = 0

    init(
        probe: @escaping () async -> BackendReachability,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.probe = probe
        self.sleep = sleep
    }

    func probeNow() async {
        let answeredBefore = answeredSerial
        let failedBefore = failedSerial
        let answer = await probe()
        // A cancelled probe fails as "unreachable" without having asked.
        guard !Task.isCancelled else { return }
        // Every answer settles it, or the migration offer (and the launch
        // sheets it holds back) would wait forever on an unconfigured server.
        if launchAnswer == nil { launchAnswer = answer == .reachable }
        guard answer == .unreachable else { return set(link.after(probe: answer), because: "probe \(answer)") }
        // The probe folds "answered with an error" and "no sign-in, nothing
        // sent" into unreachable. Only a request that failed to get through
        // makes it down; the reports already set the link.
        if answeredSerial != answeredBefore {
            set(.up, because: "probe answered with an error")
        } else if failedSerial == failedBefore {
            logger.notice("Probe sent nothing; server link unchanged")
        }
    }

    func report(_ report: TransportReport) {
        switch report {
        case .answered: answeredSerial += 1
        case .failed(.mayHaveArrived): mayHaveArrivedSerial += 1; failedSerial += 1
        case .failed(.notSent): failedSerial += 1
        }
        set(link.after(report), because: "\(report)")
    }

    func reprobeWhileDown() async {
        while link.isDown, !Task.isCancelled {
            await sleep(Self.reprobeInterval)
            guard !Task.isCancelled else { return }
            await probeNow()
        }
    }

    /// Wires both services' request reports to `monitor`, weakly: the
    /// services, the store and the monitor would otherwise keep each other
    /// alive. Only requests to the active server count, so a connection
    /// test against another address moves nothing.
    static func connect(
        _ monitor: ServerLinkMonitor, spoolman: SpoolmanService, filaMan: FilaManService,
        activeTarget: @escaping @MainActor () -> String
    ) {
        let hook: @MainActor (TransportReport, URL?) -> Void = { [weak monitor] report, url in
            guard let monitor, isActiveServer(url, target: activeTarget()) else { return }
            monitor.report(report)
        }
        spoolman.transportReport = hook
        filaMan.transportReport = hook
    }

    /// Same host and port as the active server's address. `target` may be a
    /// store's `connectionTarget` ("spoolman|http://host:port").
    nonisolated static func isActiveServer(_ url: URL?, target: String) -> Bool {
        let trimmed = (target.split(separator: "|").last.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url, let host = url.host?.lowercased(), let active = URL(string: address),
              host == active.host?.lowercased() else { return false }
        return port(of: url) == port(of: active)
    }

    private nonisolated static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    func outcome<T>(of write: () async -> T?) async -> WriteOutcome<T> {
        let before = mayHaveArrivedSerial
        if let value = await write() { return .saved(value) }
        return mayHaveArrivedSerial != before ? .unknown : .failed
    }

    func outcome(of write: () async -> Bool) async -> WriteOutcome<Void> {
        await outcome { await write() ? () : nil }
    }

    private func set(_ next: ServerLink, because reason: String) {
        if next != link { logger.notice("Server link \(String(describing: next), privacy: .public) after \(reason, privacy: .public)") }
        let recovered = link.isDown && !next.isDown
        link = next
        if recovered { onRecovered?() }
    }
}
