//
//  BackendNotConnectedViewTests.swift
//  SpoolKidTests
//
//  Purpose: F37 — the "this backend isn't connected" screen is the ONLY thing
//  a stranded user can see, so its copy is behaviour, not decoration.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct BackendNotConnectedViewTests {
    private let servers = [BackendCapabilities.spoolman, BackendCapabilities.filaman]

    @Test func titleNamesTheBackendThatIsNotConnected() {
        #expect(BackendNotConnectedView.title(for: .spoolman) == "No Spoolman Connection")
        #expect(BackendNotConnectedView.title(for: .filaman) == "No FilaMan Connection")
    }

    /// The three facts a stranded user needs, and none of which the old copy
    /// carried: which backend is selected, that the choice can be reversed, and
    /// that the rows on the device are still there. A Local user who taps the
    /// Backend picker to reach the connection form and abandons before Test
    /// Connection succeeds lands here on the next launch, with an on-device
    /// library that is intact and completely invisible.
    @Test func descriptionNamesTheBackendTheLibraryAndTheDevicesRows() {
        for caps in servers {
            let text = BackendNotConnectedView.description(for: caps)

            #expect(text.contains(caps.displayName))
            #expect(text.contains(BackendCapabilities.local.displayName))
            #expect(text.localizedCaseInsensitiveContains("iPhone"))
            #expect(text.localizedCaseInsensitiveContains("delete"))
        }
    }

    @Test func descriptionNeverDescribesOneServerAsAnother() {
        #expect(BackendNotConnectedView.description(for: .filaman).contains("Spoolman") == false)
        #expect(BackendNotConnectedView.description(for: .spoolman).contains("FilaMan") == false)
    }
}
