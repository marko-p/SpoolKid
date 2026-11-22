//
//  CardUIDsFieldProvisioningTests.swift
//  SpoolKidTests
//
//  SpoolLink's `card_uids` must be a system-wide spool field on every backend
//  that has a registry — not just on the records SpoolKid happens to have
//  mapped. Owner decision, 2026-08-24, after finding FilaMan's Admin Panel
//  "System Extra Fields" empty while spool #40 carried the key.
//

import Foundation
import Testing
@testable import SpoolKid

struct CardUIDsFieldProvisioningTests {

    // MARK: - Which backends declare the field

    /// The epic's original reading — "FilaMan's `custom_fields` is free-form,
    /// so there is nothing to provision" — was true about writes and wrong
    /// about registries. FilaMan has one; a mapping just doesn't need it.
    /// Every server that maps tags declares `card_uids`; the Library maps
    /// them too since spec 2 but has no field registry to declare it in.
    @Test func everyServerThatCanMapTagsAlsoRegistersTheField() {
        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)
            #expect(
                caps.requiresCardUIDsFieldRegistration == (caps.supportsTagMapping && !caps.isOnDeviceStorage),
                "\(kind) maps tags but does not declare card_uids"
            )
        }
    }

    @Test func theLibraryMapsTags() {
        #expect(BackendCapabilities.local.supportsTagMapping)
    }

    @Test func onDeviceStorageHasNoRegistry() {
        #expect(BackendCapabilities.local.requiresCardUIDsFieldRegistration == false)
    }

    // MARK: - Idempotency

    private static func field(
        id: Int, key: String, target: String, source: String? = nil
    ) -> FilaManSystemExtraField {
        FilaManSystemExtraField(id: id, targetType: target, key: key, label: "Card UIDs", source: source)
    }

    @Test func anEmptyRegistryNeedsTheField() {
        #expect(FilaManService.needsCardUIDsFieldCreation(existing: []))
    }

    /// The whole value of the bootstrap is that the second call writes nothing:
    /// it runs on every foreground.
    @Test func aRegistryThatAlreadyDeclaresItNeedsNothing() {
        let existing = [Self.field(id: 3, key: "card_uids", target: "spool")]
        #expect(FilaManService.needsCardUIDsFieldCreation(existing: existing) == false)
    }

    /// The registry is shared by spools and filaments, so the target type is
    /// half the identity of a row.
    @Test func theSameKeyOnFilamentsIsADifferentField() {
        let existing = [Self.field(id: 3, key: "card_uids", target: "filament")]
        #expect(FilaManService.needsCardUIDsFieldCreation(existing: existing))
    }

    @Test func otherFieldsAreNotMistakenForIt() {
        let existing = [
            Self.field(id: 1, key: "spoolman_id", target: "spool"),
            Self.field(id: 2, key: "card_uid", target: "spool")
        ]
        #expect(FilaManService.needsCardUIDsFieldCreation(existing: existing))
    }

    /// The registered key has to be the one every reader already uses; a
    /// near-miss would declare a field nothing looks at.
    @Test func theRegisteredKeyIsTheKeyTheAppReads() {
        let payload = FilaManPayloadBuilder.systemExtraFieldPayload(
            targetType: "spool",
            key: CardUIDsCodec.fieldKey,
            label: FilaManService.cardUIDsFieldLabel
        )
        #expect(payload["key"] as? String == "card_uids")
        #expect(payload["target_type"] as? String == "spool")
    }

    // MARK: - The payload

    /// `card_uids` is a comma-separated list, so it must be a text field —
    /// never a number, never a dropdown.
    @Test func theFieldIsText() {
        let payload = FilaManPayloadBuilder.systemExtraFieldPayload(
            targetType: "spool", key: "card_uids", label: "Card UIDs"
        )
        #expect(payload["field_type"] as? String == "text")
    }

    /// A default would put an empty value into `custom_fields` on spools that
    /// have no mapping, and "" is not the same as absent. `source` marks a row
    /// undeletable, so SpoolKid must not claim it.
    @Test func thePayloadClaimsNoDefaultAndNoPluginOwnership() {
        let payload = FilaManPayloadBuilder.systemExtraFieldPayload(
            targetType: "spool", key: "card_uids", label: "Card UIDs"
        )
        #expect(payload["default_value"] == nil)
        #expect(payload["source"] == nil)
        #expect(Set(payload.keys) == ["target_type", "key", "label", "field_type"])
    }

    // MARK: - Decoding the registry

    @Test func aRegistryRowDecodesFromFilaMansOwnShape() throws {
        let json = """
        {"id": 7, "target_type": "spool", "key": "card_uids", "label": "Card UIDs",
         "default_value": null, "field_type": "text", "options": null, "source": null}
        """
        let row = try JSONDecoder().decode(FilaManSystemExtraField.self, from: Data(json.utf8))
        #expect(row.id == 7)
        #expect(row.key == "card_uids")
        #expect(row.targetType == "spool")
        #expect(row.source == nil)
    }

    @Test func aPluginOwnedRowKeepsItsSource() throws {
        let json = """
        {"id": 9, "target_type": "spool", "key": "bambu_tray", "label": "Tray",
         "field_type": "text", "source": "bambulab"}
        """
        let row = try JSONDecoder().decode(FilaManSystemExtraField.self, from: Data(json.utf8))
        #expect(row.source == "bambulab")
    }
}
