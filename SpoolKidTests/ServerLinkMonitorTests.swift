//
//  ServerLinkMonitorTests.swift
//  SpoolKidTests
//
//  The 2026-11-07 server-down lockout: probing, reports and save outcomes.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
private final class Script {
    var answers: [BackendReachability]
    var sleeps: [Duration] = []
    var beforeAnswer: (() -> Void)?
    init(_ answers: [BackendReachability]) { self.answers = answers }

    func next() -> BackendReachability {
        beforeAnswer?()
        return answers.isEmpty ? .reachable : answers.removeFirst()
    }
}

/// A scripted "unreachable" behaves like the real probe: its request failed.
@MainActor
private func monitor(_ script: Script) -> ServerLinkMonitor {
    var link: ServerLinkMonitor!
    link = ServerLinkMonitor(
        probe: {
            if script.beforeAnswer == nil, script.answers.first == .unreachable { link.report(.failed(.notSent)) }
            return script.next()
        },
        sleep: { script.sleeps.append($0) }
    )
    return link
}

@MainActor
struct ServerLinkMonitorTests {
    @Test func theFirstProbeIsTheLaunchAnswer() async {
        let script = Script([.unreachable, .reachable])
        let link = monitor(script)
        await link.probeNow()
        await link.probeNow()
        #expect(link.launchAnswer == false)
        #expect(link.link == .up)
    }

    @Test func aReportTakesItDownAndAnAnswerBringsItBack() {
        let link = monitor(Script([]))
        var recovered = 0
        link.onRecovered = { recovered += 1 }
        link.report(.failed(.notSent))
        #expect(link.link == .down)
        link.report(.answered)
        #expect(link.link == .up)
        #expect(recovered == 1)
    }

    @Test func reprobingWaitsThirtySeconds() async {
        let script = Script([.unreachable, .reachable])
        let link = monitor(script)
        link.report(.failed(.notSent))
        await link.reprobeWhileDown()
        #expect(script.sleeps == [.seconds(30), .seconds(30)])
        #expect(link.link == .up)
    }

    @Test func noReprobingWhileUp() async {
        let script = Script([])
        let link = monitor(script)
        link.report(.answered)
        await link.reprobeWhileDown()
        #expect(script.sleeps.isEmpty)
    }

    @Test func anAnsweringServerIsNotDownWhenTheProbeFails() async {
        let script = Script([.unreachable])
        let link = monitor(script)
        script.beforeAnswer = { link.report(.answered) }
        await link.probeNow()
        #expect(link.link == .up)
    }

    @Test func aProbeThatSentNothingChangesNothing() async {
        let script = Script([.unreachable])
        let link = monitor(script)
        script.beforeAnswer = {}
        await link.probeNow()
        #expect(link.link == .unknown)
    }

    @Test func aCancelledProbeChangesNothing() async {
        let script = Script([.unreachable])
        let link = monitor(script)
        script.beforeAnswer = {}  // a cancelled request reports nothing
        let probing = Task { await link.probeNow() }
        probing.cancel()
        await probing.value
        #expect(link.link == .unknown)
        #expect(link.launchAnswer == nil)
    }

    @Test func aNotConfiguredProbeStillAnswersLaunch() async {
        let link = monitor(Script([.notConfigured]))
        await link.probeNow()
        #expect(link.launchAnswer == false)
    }

    @Test func onlyTheActiveServersRequestsCount() {
        let target = "http://192.168.20.33:7912"
        #expect(ServerLinkMonitor.isActiveServer(URL(string: "http://192.168.20.33:7912/api/v1/spool"), target: target))
        #expect(!ServerLinkMonitor.isActiveServer(URL(string: "http://192.168.20.99:7912/api/v1/vendor"), target: target))
        #expect(!ServerLinkMonitor.isActiveServer(URL(string: "http://192.168.20.33:8000/api/v1/vendor"), target: target))
        #expect(!ServerLinkMonitor.isActiveServer(nil, target: target))
        #expect(ServerLinkMonitor.isActiveServer(URL(string: "http://192.168.20.33:7912/x"), target: "spoolman|" + target))
    }

    @Test func theHooksDoNotKeepTheMonitorAlive() {
        let spoolman = SpoolmanService(session: StubURLProtocol.session(), authType: { "none" })
        let filaMan = FilaManService(session: StubURLProtocol.session())
        weak var released: ServerLinkMonitor?
        do {
            // Not the scripted helper: its probe closure holds the monitor itself.
            let link = ServerLinkMonitor(probe: { .reachable })
            ServerLinkMonitor.connect(link, spoolman: spoolman, filaMan: filaMan, activeTarget: { "" })
            released = link
        }
        #expect(released == nil)
    }

    @Test func aTimeoutDuringAWriteIsUnknown() async {
        let link = monitor(Script([]))
        let outcome: WriteOutcome<Int> = await link.outcome { () async -> Int? in
            link.report(.failed(.mayHaveArrived))
            return nil
        }
        #expect(outcome.isUnknown)
    }

    @Test func aRefusedWriteIsFailed() async {
        let link = monitor(Script([]))
        let unsent = await link.outcome { () async -> Bool in
            link.report(.failed(.notSent))
            return false
        }
        #expect(unsent.isFailed)
        let refused = await link.outcome { () async -> Bool in
            link.report(.answered)
            return false
        }
        #expect(refused.isFailed)
    }

    @Test func aSavedWriteIsSaved() async {
        let link = monitor(Script([]))
        let outcome: WriteOutcome<Int> = await link.outcome { () async -> Int? in 7 }
        guard case .saved(let value) = outcome else {
            Issue.record("Expected saved, got \(outcome)")
            return
        }
        #expect(value == 7)
    }
}
