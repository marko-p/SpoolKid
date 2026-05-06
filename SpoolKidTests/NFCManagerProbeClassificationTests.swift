import Testing
@testable import SpoolKid

struct NFCManagerProbeClassificationTests {

    @Test func showsBambuLabelOnlyWhenEvidenceIsStrong() {
        let probe = BambuTagProbeResult(
            couldBeBambu: true,
            dataEncrypted: true,
            normalizedUID: "045d7774ce2a81",
            displayLabel: "Bambu Lab (encrypted)"
        )

        let surfaced = NFCManager.surfacedProbeResult(for: probe, strongBambuEvidence: true)
        #expect(surfaced.displayLabel == "Bambu Lab (encrypted)")
    }

    @Test func usesConservativeLabelWhenEvidenceIsWeak() {
        let probe = BambuTagProbeResult(
            couldBeBambu: true,
            dataEncrypted: true,
            normalizedUID: "045d7774ce2a81",
            displayLabel: "Bambu Lab (encrypted)"
        )

        let surfaced = NFCManager.surfacedProbeResult(for: probe, strongBambuEvidence: false)
        #expect(surfaced.displayLabel == "Unknown or encrypted tag")
    }

    @Test func neverShowsBambuLabelForNonBambuProbe() {
        let probe = BambuTagProbeResult(
            couldBeBambu: false,
            dataEncrypted: true,
            normalizedUID: "deadbeef",
            displayLabel: "Encrypted MIFARE Classic"
        )

        let surfaced = NFCManager.surfacedProbeResult(for: probe, strongBambuEvidence: true)
        #expect(surfaced.displayLabel == "Unknown or encrypted tag")
    }

    @Test func readableUnknownProbeIsMarkedAsNotEncrypted() {
        let probe = BambuTagProbeResult(
            couldBeBambu: true,
            dataEncrypted: true,
            normalizedUID: "045d7774ce2a81",
            displayLabel: "Bambu Lab (encrypted)"
        )

        let surfaced = NFCManager.unknownReadableProbeResult(for: probe)
        #expect(surfaced.dataEncrypted == false)
        #expect(surfaced.displayLabel == "Unknown tag format")
    }
}
