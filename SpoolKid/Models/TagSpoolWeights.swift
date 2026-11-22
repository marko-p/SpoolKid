//
//  TagSpoolWeights.swift
//  SpoolKid
//

import Foundation

/// What a scanned tag says about the physical spool it is on, for a new spool
/// built from it (the Scan Result hub's Create New Spool). Tag values beat the
/// form's defaults (owner, 2026-10-21). Each is nil when the tag does not
/// state it.
nonisolated struct TagSpoolWeights: Equatable, Sendable {
    /// The empty spool (OpenPrintTag `empty_container_weight`).
    var empty: Double?
    /// NET filament on the full spool: an OpenPrintTag's actual net weight,
    /// else its nominal one; every other format's nominal. TigerTag's second
    /// weight is what is left, not the fill, so only OpenPrintTag's counts.
    var initial: Double?
    /// NET filament left, only when a printer recorded consumption on an
    /// OpenPrintTag (`consumedWeight` > 0), on the same basis as `initial`.
    var remaining: Double?

    init(empty: Double?, initial: Double?, remaining: Double?) {
        self.empty = empty
        self.initial = initial
        self.remaining = remaining
    }

    init(tagData: FilamentTagData, format: ScanResult.DetectedFormat?) {
        empty = FilamentTagData.statedMeasurement(tagData.emptyContainerWeight)
        if case .openPrintTag = format {
            initial = tagData.fullWeightOnTag
            remaining = FilamentTagData.statedMeasurement(tagData.consumedWeight) == nil ? nil : tagData.remainingOnTag
        } else {
            initial = FilamentTagData.statedMeasurement(tagData.nominalNetWeight)
            remaining = nil
        }
    }
}
