//
//  FilaManMeasurementTests.swift
//  SpoolKidTests
//
//  FilaMan distinguishes a scale reading from a correction in its event
//  history: `POST /spools/{id}/measurements` records a `measurement`, while the
//  adjustment endpoint SpoolKid used for every weight write records a
//  `manual_adjust`. Owner request 2026-08-25 — a spool actually put on a scale
//  should say so in the ledger.
//

import Foundation
import Testing
@testable import SpoolKid

struct FilaManMeasurementTests {

    // MARK: - Which endpoint a save uses

    /// The Measured mode states a GROSS scale reading, which is what
    /// `measured_weight_g` is — so it goes to the measurement endpoint whole,
    /// with no arithmetic of SpoolKid's in between.
    @Test func aScaleReadingIsWrittenAsAMeasurement() {
        var draft = SpoolDraft(filamentId: 1)
        draft.measuredWeight = 1238
        draft.remainingWeight = .set(1000)
        #expect(FilaManRepository.weightWriteKind(for: draft) == .measurement(1238))
    }

    /// Remaining and Used are net statements about the filament, not readings
    /// off a scale. Posting one as a measurement would claim the whole spool
    /// weighed what only its filament does.
    @Test func aNetWeightStillGoesThroughTheAdjustmentPath() {
        var draft = SpoolDraft(filamentId: 1)
        draft.remainingWeight = .set(750)
        #expect(FilaManRepository.weightWriteKind(for: draft) == .adjustment)

        var used = SpoolDraft(filamentId: 1)
        used.usedWeight = .set(250)
        #expect(FilaManRepository.weightWriteKind(for: used) == .adjustment)
    }

    @Test func aDraftNamingNoWeightAtAllIsStillTheAdjustmentPath() {
        #expect(FilaManRepository.weightWriteKind(for: SpoolDraft(filamentId: 1)) == .adjustment)
    }

    /// `SpoolFormView` always fills `remainingWeight`, including in Measured
    /// mode, because Spoolman and the on-device Library have no measurement
    /// concept. The gross reading has to win where both are present.
    @Test func theScaleReadingWinsOverTheNetWeightDerivedFromIt() {
        var draft = SpoolDraft(filamentId: 1)
        draft.measuredWeight = 988
        draft.remainingWeight = .set(750)
        draft.usedWeight = .set(250)
        #expect(FilaManRepository.weightWriteKind(for: draft) == .measurement(988))
    }

    /// An empty spool weighed down to its bare core is a real reading.
    @Test func zeroIsAReadingLikeAnyOther() {
        var draft = SpoolDraft(filamentId: 1)
        draft.measuredWeight = 0
        #expect(FilaManRepository.weightWriteKind(for: draft) == .measurement(0))
    }

    // MARK: - The payload

    @Test func theMeasurementBodyCarriesTheGrossReadingAndNothingElse() {
        let payload = FilaManPayloadBuilder.measurementPayload(measuredWeight: 1238)
        #expect(payload["measured_weight_g"] as? Double == 1238)
        #expect(Set(payload.keys) == ["measured_weight_g"])
    }

    /// `event_at` defaults server-side to now, and stamping a client clock onto
    /// an event log is how two devices disagree about the order of prints.
    @Test func theBodyDoesNotStampAClientTimestamp() {
        let payload = FilaManPayloadBuilder.measurementPayload(measuredWeight: 500)
        #expect(payload["event_at"] == nil)
    }

    // MARK: - Draft plumbing

    /// The draft has to carry the gross figure, because the net one cannot be
    /// converted back: `remaining = measured − empty_spool_weight_g` uses the
    /// SERVER's basis, and SpoolKid's copy of it may be the very thing the
    /// same save is changing.
    @Test func theDraftCarriesTheGrossReadingSeparately() {
        var draft = SpoolDraft(filamentId: 1)
        #expect(draft.measuredWeight == nil)
        draft.measuredWeight = 1238
        #expect(draft.measuredWeight == 1238)
        #expect(draft.remainingWeight == .ignore)
    }

    // MARK: - tara_missing: a 200 that applied nothing (probed live 2026-08-25)

    private func event(meta: [String: FilaManJSONValue]?) -> FilaManMeasurementEvent {
        FilaManMeasurementEvent(meta: meta)
    }

    @Test func aMeasurementWithNoMetaIsAppliedAndSaysNothing() {
        #expect(FilaManRepository.taraMissingNote(event(meta: nil)) == nil)
        #expect(FilaManRepository.taraMissingNote(event(meta: [:])) == nil)
    }

    /// The live shape: `meta: {"tara_missing": true}`, status 200, and
    /// `remaining_weight_g` unchanged across the call.
    @Test func aTaraMissingMeasurementIsReported() {
        let note = FilaManRepository.taraMissingNote(event(meta: ["tara_missing": .bool(true)]))

        #expect(note != nil)
        #expect(note?.contains("empty-spool weight") == true)
    }

    @Test func taraMissingFalseIsNotAWarning() {
        #expect(FilaManRepository.taraMissingNote(event(meta: ["tara_missing": .bool(false)])) == nil)
    }

    /// `meta` is free-form, so an unrelated key must not read as a failure.
    @Test func anUnrelatedMetaKeyIsNotAWarning() {
        #expect(FilaManRepository.taraMissingNote(event(meta: ["source": .string("ui")])) == nil)
    }

    /// Decoded from the wire, not hand-built — the DTO has to survive the real
    /// response, which carries fourteen other keys.
    @Test func theRealResponseShapeDecodes() throws {
        let json = """
        {"id":9,"spool_id":42,"event_type":"measurement","event_at":"2026-08-25T20:00:55.804225Z",
         "user_id":2,"device_id":null,"source":"ui","delta_weight_g":null,"measured_weight_g":850.0,
         "from_status_id":null,"to_status_id":null,"from_location_id":null,"to_location_id":null,
         "note":null,"meta":{"tara_missing":true}}
        """
        let decoded = try JSONDecoder().decode(FilaManMeasurementEvent.self, from: Data(json.utf8))

        #expect(decoded.taraMissing)
        #expect(FilaManRepository.taraMissingNote(decoded) != nil)
    }

    @Test func theAppliedResponseShapeDecodesAsNoWarning() throws {
        let json = """
        {"id":11,"spool_id":43,"event_type":"measurement","measured_weight_g":850.0,"meta":null}
        """
        let decoded = try JSONDecoder().decode(FilaManMeasurementEvent.self, from: Data(json.utf8))

        #expect(!decoded.taraMissing)
        #expect(FilaManRepository.taraMissingNote(decoded) == nil)
    }
}
