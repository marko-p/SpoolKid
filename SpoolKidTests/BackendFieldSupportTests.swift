import Testing
@testable import SpoolKid

struct BackendFieldSupportTests {
    /// A support table naming an ID the catalogue does not have is a typo that
    /// would silently hide nothing; a catalogue field no table names is a field
    /// no backend can ever show. Both are caught here rather than on a device.
    @Test func everySupportedIDExistsInTheCatalog() {
        for support in [BackendFieldSupport.spoolmanShaped, BackendFieldSupport.filaman] {
            for entity in LibraryEntity.allCases {
                let catalog = Set(FieldCatalog.fields(for: entity).map(\.id))
                let declared = support.supportedIDs(in: entity)
                #expect(declared.subtracting(catalog).isEmpty,
                        "\(entity.rawValue): declared but not in the catalog: \(declared.subtracting(catalog).sorted())")
            }
        }
    }

    @Test func everyCatalogFieldIsSupportedBySomeBackend() {
        for entity in LibraryEntity.allCases {
            for field in FieldCatalog.fields(for: entity) {
                let anywhere = BackendFieldSupport.spoolmanShaped.supports(field.id, in: entity)
                    || BackendFieldSupport.filaman.supports(field.id, in: entity)
                #expect(anywhere, "\(entity.rawValue).\(field.id) is supported by no backend")
            }
        }
    }

    /// Local and Spoolman share one table because `LocalSpool`/`LocalFilament`/
    /// `LocalVendor` mirror Spoolman's model field for field. If that stops
    /// being true, this is where it shows up.
    @Test func localAndSpoolmanResolveIdenticalSets() {
        for entity in LibraryEntity.allCases {
            #expect(BackendCapabilities.local.fieldSupport.supportedIDs(in: entity)
                    == BackendCapabilities.spoolman.fieldSupport.supportedIDs(in: entity))
        }
    }

    /// Measured against the owner's live FilaMan on 2026-08-28. Each of these
    /// is a field FilaMan does not have — either absent from its model, or
    /// accepted by PATCH and stored nowhere.
    @Test func filaManDoesNotDeclareFieldsItLacks() {
        let unsupported: [(LibraryEntity, String)] = [
            (.spool, "used_weight"),      // derived from the other weights
            (.spool, "comment"),          // no column; SpoolKid emulated it
            (.spool, "first_used"),       // PATCH 200s and stores nothing
            (.spool, "last_used"),        // same
            (.filament, "comment"),
            (.filament, "article_number"),
            (.filament, "settings_extruder_temp"),
            (.filament, "settings_bed_temp"),
            (.filament, "external_id"),
            (.vendor, "comment"),
            (.vendor, "external_id")
        ]
        for (entity, id) in unsupported {
            #expect(BackendFieldSupport.filaman.supports(id, in: entity) == false,
                    "FilaMan still declares \(entity.rawValue).\(id)")
        }
    }

    /// …and the fields it DOES have stay.
    @Test func filaManKeepsWhatItActuallyHas() {
        let supported: [(LibraryEntity, String)] = [
            (.spool, "filament_id"), (.spool, "initial_weight"), (.spool, "spool_weight"),
            (.spool, "remaining_weight"), (.spool, "price"), (.spool, "location"),
            (.spool, "lot_nr"),
            (.filament, "name"), (.filament, "vendor_id"), (.filament, "material"),
            (.filament, "color_hex"),
            (.filament, "density"), (.filament, "diameter"),
            (.filament, "price"), (.filament, "weight"), (.filament, "spool_weight"),
            (.vendor, "name"), (.vendor, "empty_spool_weight")
        ]
        for (entity, id) in supported {
            #expect(BackendFieldSupport.filaman.supports(id, in: entity),
                    "FilaMan lost \(entity.rawValue).\(id)")
        }
    }

    /// Spoolman keeps everything the catalogue still holds, except the three
    /// fields Task 7 adds that are native to FilaMan only (Spoolman has an
    /// archived boolean instead of a status, and no external id or purchase
    /// date on a spool).
    @Test func spoolmanStillSupportsTheWholeCatalog() {
        let filaManOnlySpoolFields: Set<String> = ["status", "external_id", "purchase_date"]
        for entity in LibraryEntity.allCases {
            for field in FieldCatalog.fields(for: entity) {
                guard !(entity == .spool && filaManOnlySpoolFields.contains(field.id)) else { continue }
                #expect(BackendFieldSupport.spoolmanShaped.supports(field.id, in: entity),
                        "Spoolman lost \(entity.rawValue).\(field.id)")
            }
        }
    }

    /// Every backend calls `vendor_id` "Manufacturer" now — the base label
    /// says it, and there is no per-backend label to disagree with it.
    ///
    /// `initial_weight` is NOT relabeled: `SpoolDraft.initialWeight` is NET
    /// filament on all three backends (`FilaManRepository.netInitialWeight`
    /// subtracts the basis on read, `FilaManPayloadBuilder.spoolWeightKeys`
    /// adds it back on write) — a "Total"/gross label here would print the
    /// wrong word on a field that never changed meaning. Fix round 1 review,
    /// 2026-08-28.
    @Test func everyBackendCallsTheVendorAManufacturer() {
        let vendor = FieldCatalog.fields(for: .filament).first { $0.id == "vendor_id" }!
        #expect(vendor.label == "Manufacturer")
        #expect(BackendFieldSupport.filaman.supports("vendor_id", in: .filament))
        #expect(BackendFieldSupport.spoolmanShaped.supports("vendor_id", in: .filament))
    }

    @Test func anUnknownFieldIsNotSupported() {
        #expect(BackendFieldSupport.filaman.supports("no_such_field", in: .spool) == false)
    }

    @Test func onlyFilaManOffersItsOwnThreeFields() {
        for id in ["status", "external_id", "purchase_date"] {
            #expect(BackendFieldSupport.filaman.supports(id, in: .spool),
                    "FilaMan should offer spool.\(id)")
            #expect(BackendFieldSupport.spoolmanShaped.supports(id, in: .spool) == false,
                    "Spoolman/Local should not offer spool.\(id)")
        }
    }

    /// Archived and Status are one piece of state. Exactly one control for it
    /// reaches the form on any backend, so they cannot contradict each other.
    @Test func exactlyOneArchiveControlPerBackend() {
        for support in [BackendFieldSupport.spoolmanShaped, BackendFieldSupport.filaman] {
            let hasToggle = support.supports("archived", in: .spool)
            let hasPicker = support.supports("status", in: .spool)
            #expect(hasToggle != hasPicker, "a backend offers both or neither archive control")
        }
    }
}
