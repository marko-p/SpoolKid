//
//  ServerTagWriteRuleTests.swift
//  SpoolKidTests
//
//  The 2026-11-07 server-down lockout: which tag writes still work.
//

import Testing
@testable import SpoolKid

struct ServerTagWriteRuleTests {
    @Test func upAllows() {
        #expect(ServerTagWriteRule.gate(isDown: false, links: true, isOwned: true, ownerName: "Elegoo Red") == .allowed)
    }

    @Test func aLinkIsLockedWhenDown() {
        #expect(ServerTagWriteRule.gate(isDown: true, links: true, isOwned: false, ownerName: nil) == .locked)
    }

    @Test func anOwnedTagIsRefusedWhenDown() {
        #expect(ServerTagWriteRule.gate(isDown: true, links: false, isOwned: true, ownerName: "Elegoo Red")
                == .refused("This tag is linked to Elegoo Red. Try again when the server is back."))
    }

    @Test func anUnownedTagIsAllowedWhenDown() {
        #expect(ServerTagWriteRule.gate(isDown: true, links: false, isOwned: false, ownerName: nil) == .allowed)
    }

    @Test func hubTilesThatWriteNeedTheServer() {
        let needing: Set<HubTileID> = [.weigh, .transferTag, .unlink, .addAnotherTag, .linkTag, .createNewSpool, .writeTag, .setLocation]
        let free: Set<HubTileID> = [.spoolsWithFilament, .searchSpoolmanDB, .revertToTagData]
        #expect(needing.allSatisfy { $0.needsServer })
        #expect(!free.contains { $0.needsServer })
    }

    @Test func hubMenuItemsThatWriteLinksNeedTheServer() {
        #expect(HubMenuItemID.cloneTag.needsServer && HubMenuItemID.emptyTag.needsServer)
        let others: [HubMenuItemID] = [.writeSpoolID, .writeSpoolDataOntoTag, .inspectTag, .reviewScannedData]
        #expect(!others.contains { $0.needsServer })
    }

    @Test func theHubSaysWhyNothingWasLookedUp() {
        #expect(ServerTagWriteRule.lookupNote(backendName: "Spoolman")
                == "Spoolman can't be reached, so this spool can't be looked up right now.")
    }
}
