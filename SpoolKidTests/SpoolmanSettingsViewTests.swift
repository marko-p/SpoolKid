import Testing
@testable import SpoolKid

@MainActor
struct SpoolmanSettingsViewTests {
    @Test func settingsViewTypeExists() async throws {
        // Smoke test: the new in-app Spoolman settings type exists.
        let typeName = String(describing: SpoolmanSettingsView.self)
        #expect(typeName == "SpoolmanSettingsView")
    }

    // MARK: - Backend picker footer (F37)
    //
    // The picker writes `AppConfig.backendKindKey` on the FIRST tap, before
    // anything is validated — it must, because a backend cannot be tested
    // before it is selected, and the connection form only appears once its
    // backend is picked. So the footer has to say what that leaves: the choice
    // goes live on leaving the screen whether or not the server ever answered.

    @Test func footerSaysOnlyWhenTheChoiceAppliesForAConnectedBackend() {
        let footer = SpoolmanSettingsView.pickerFooter(for: .spoolman, isConnected: true)

        #expect(footer == "Takes effect as soon as you leave this screen.")
    }

    @Test func theOnDeviceLibraryNeverWarnsAboutAConnection() {
        // `.local` declares no connection flag, so `BackendAvailability` always
        // reads it as available — the footer must not invent a warning for it.
        #expect(SpoolmanSettingsView.pickerFooter(for: .local, isConnected: true)
                == "Takes effect as soon as you leave this screen.")
    }

    @Test func footerWarnsAndOffersTheLibraryWhenTheChosenBackendIsNotConnected() {
        for kind in [BackendKind.spoolman, BackendKind.filaman] {
            let footer = SpoolmanSettingsView.pickerFooter(for: kind, isConnected: false)

            #expect(footer.hasPrefix("Takes effect as soon as you leave this screen."))
            #expect(footer.contains(BackendCapabilities.for(kind).displayName))
            #expect(footer.contains(BackendCapabilities.local.displayName))
        }
    }

    // MARK: - Tag Identity store switches

    /// SpoolKid needs somewhere to keep a new link, so the switch that is on
    /// while the other is off cannot be turned off.
    @Test func theLastStoreOnCannotBeSwitchedOff() {
        #expect(SpoolmanSettingsView.isLastStoreOn(true, other: false))
        #expect(SpoolmanSettingsView.isLastStoreOn(true, other: true) == false)
        #expect(SpoolmanSettingsView.isLastStoreOn(false, other: false) == false)
    }
}
