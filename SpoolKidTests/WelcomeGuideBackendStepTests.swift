//
//  WelcomeGuideBackendStepTests.swift
//  SpoolKidTests
//
//  The welcome guide's backend step. Until 2026-08-23 step 2 was hardcoded to
//  Spoolman — title, form, and gating flag alike — so a fresh install had no
//  way to reach FilaMan at all: the picker that offers it lives in a settings
//  screen the guide has to be completed to reach. These cover the decisions
//  that step makes, stated over `BackendKind.allCases` so a fourth backend
//  inherits them.
//

import Testing
@testable import SpoolKid

struct WelcomeGuideBackendStepTests {

    // MARK: - Continue gating

    /// The on-device Library has nothing to connect to, so it is always ready.
    @Test func onDeviceLibraryNeedsNoConnection() {
        #expect(WelcomeGuideView.canLeaveBackendStep(
            capabilities: .local, connectionValid: false
        ))
    }

    /// A server backend is ready only once its connection has actually been
    /// validated. "Skip for Now" — not Continue — is the way past one that has
    /// not been, and it selects the Library instead.
    @Test func serverBackendsRequireAValidatedConnection() {
        for kind in BackendKind.allCases {
            let capabilities = BackendCapabilities.for(kind)
            guard !capabilities.isOnDeviceStorage else { continue }
            #expect(!WelcomeGuideView.canLeaveBackendStep(
                capabilities: capabilities, connectionValid: false
            ), "\(kind) let the user continue with no validated connection")
            #expect(WelcomeGuideView.canLeaveBackendStep(
                capabilities: capabilities, connectionValid: true
            ), "\(kind) blocked a validated connection")
        }
    }

    // MARK: - Backend activation note

    /// A choice made in the guide is not yet the choice in force —
    /// `ContentView.init` resolved the repository before the guide appeared.
    /// Every backend must be able to say so; the guide reporting a switch it
    /// did not perform is the epic's recurring defect in its first-run form.
    @Test func aDifferentChoiceAlwaysNamesItself() {
        for chosen in BackendKind.allCases {
            for active in BackendKind.allCases where active != chosen {
                let note = WelcomeGuideView.backendActivationNote(chosen: chosen, active: active)
                #expect(note != nil, "\(chosen) over \(active) said nothing about taking effect")
                #expect(
                    note?.contains(BackendCapabilities.for(chosen).displayName) == true,
                    "\(chosen) over \(active) did not name the backend it will switch to"
                )
            }
        }
    }

    @Test func noNoteWhenTheChoiceIsAlreadyRunning() {
        for kind in BackendKind.allCases {
            #expect(WelcomeGuideView.backendActivationNote(chosen: kind, active: kind) == nil)
        }
    }

    /// The note stopped asking for a relaunch on 2026-08-25, because one is no
    /// longer needed — `ContentView` rebuilds on the guide's dismissal. A note
    /// still telling the user to reopen the app would now be false.
    @Test func theNoteNoLongerAsksForARelaunch() {
        let note = WelcomeGuideView.backendActivationNote(chosen: .filaman, active: .local)

        let lowered = note?.lowercased()
        #expect(lowered?.contains("reopen") == false)
        #expect(lowered?.contains("relaunch") == false)
        #expect(lowered?.contains("restart") == false)
    }

    // MARK: - The rebuild that replaced the relaunch

    @Test func aBackendDifferentFromTheRunningOneTriggersARebuild() {
        #expect(ContentView.needsBackendRebuild(stored: "filaman", active: .local))
        #expect(ContentView.needsBackendRebuild(stored: "local", active: .spoolman))
    }

    @Test func choosingTheRunningBackendRebuildsNothing() {
        for kind in BackendKind.allCases {
            #expect(
                ContentView.needsBackendRebuild(stored: kind.rawValue, active: kind) == false,
                "\(kind) asked for a pointless rebuild"
            )
        }
    }

    /// `backend_kind` is deliberately unregistered ("absent = derive"), and a
    /// guide that was skipped without writing it must not trigger a rebuild.
    @Test func anAbsentOrUnparseableStoredKindRebuildsNothing() {
        #expect(ContentView.needsBackendRebuild(stored: nil, active: .local) == false)
        #expect(ContentView.needsBackendRebuild(stored: "", active: .local) == false)
        #expect(ContentView.needsBackendRebuild(stored: "nonsense", active: .local) == false)
    }

    // MARK: - Summary

    /// The completion row must not call an unconfigured server "Connected",
    /// nor describe the on-device Library in connection terms at all.
    @Test func summaryDescribesStorageForLocalAndConnectionForServers() {
        #expect(WelcomeGuideView.backendSummaryValue(
            capabilities: .local, connectionValid: false
        ) == "On this iPhone")

        for kind in BackendKind.allCases {
            let capabilities = BackendCapabilities.for(kind)
            guard !capabilities.isOnDeviceStorage else { continue }
            #expect(WelcomeGuideView.backendSummaryValue(
                capabilities: capabilities, connectionValid: true
            ) == "Connected")
            #expect(WelcomeGuideView.backendSummaryValue(
                capabilities: capabilities, connectionValid: false
            ) == "Not configured")
        }
    }

    // MARK: - The way past an unconfigured server

    /// Named for the choice it makes, not the step it leaves: it selects the
    /// on-device Library, so it says so (owner feedback, 2026-08-23).
    @Test func theEscapeHatchNamesTheLibraryItSelects() {
        #expect(WelcomeGuideView.useLocalLibraryLabel.contains(BackendCapabilities.local.displayName))
        #expect(!WelcomeGuideView.useLocalLibraryLabel.lowercased().contains("skip"))
    }

    // MARK: - Every backend is reachable from the guide

    /// The defect itself: the guide offers a card per `BackendKind`, so a
    /// backend the app supports can never again be unreachable on a fresh
    /// install. Stated as the copy contract — every kind produces its own
    /// title, subtitle, and hint.
    @Test func everyBackendKindHasItsOwnCardCopy() {
        var titles: Set<String> = []
        var hints: Set<String> = []
        for kind in BackendKind.allCases {
            let capabilities = BackendCapabilities.for(kind)
            titles.insert(WelcomeGuideView.backendStepTitle(capabilities))
            hints.insert(WelcomeGuideView.backendCardHint(capabilities))
        }
        #expect(titles.count == BackendKind.allCases.count)
        #expect(hints.count == BackendKind.allCases.count)
    }

    // MARK: - Which tab a rebuild lands on (2026-09-24)
    //
    // Switching backend rebuilds ContentView. It used to land on Tags every
    // time, so switching from Library → Library Mode threw you out of Library.

    @Test func aRebuildReturnsToTheTabItLeft() {
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: .spoolman, printerConfigured: true) == .spoolman)
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: .home, printerConfigured: true) == .home)
    }

    @Test func aColdLaunchStartsOnTags() {
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: nil, printerConfigured: true) == .tags)
    }

    @Test func theUITestLaunchArgumentStillWins() {
        #expect(ContentView.startTab(uiStartOnSpoolman: true, restored: .home, printerConfigured: true) == .spoolman)
    }

    @Test func thePrinterStepSaysNothingBeforeAConnectionIsTried() {
        #expect(WelcomeGuideView.printerStatusText(.notConfigured) == nil)
        #expect(WelcomeGuideView.printerStatusText(.online) != nil)
        #expect(WelcomeGuideView.printerStatusText(.offline("Can't reach it.")) == "Can't reach it.")
    }
}
