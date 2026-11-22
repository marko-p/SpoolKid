//
//  FilamentManufacturerChange.swift
//  SpoolKid
//
//  Purpose: Changes a filament's manufacturer from the Filament page. Only
//  its vendor is written. A new name is created first, as the filament form
//  does at Save, and the outcome says what happened: nothing to change, the
//  change made, or the failure and its reason.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

@MainActor
enum FilamentManufacturerChange {
    enum Outcome: Equatable {
        case changed
        case unchanged
        case failed(String)
    }

    static func apply(
        _ choice: ManufacturerChoice,
        toFilament filament: Filament,
        store: SpoolDataStore
    ) async -> Outcome {
        // A filament's manufacturer cannot be cleared, as in the form.
        let vendorId: Int
        switch choice {
        case .none:
            return .unchanged
        case .existing(let id, _):
            vendorId = id
        case .new(let name):
            if store.vendors.isEmpty {
                await store.fetchVendors()
            }
            guard let vendor = await ManufacturerName.resolve(name, in: store.vendors, create: { newName in
                await store.addVendor(name: newName)
            }) else {
                let message = "\(name) could not be added as a manufacturer."
                    + (store.errorMessage.map { " \($0)" } ?? "")
                if let quota = store.lastQuotaError {
                    return .failed(quota.errorDescription ?? message)
                }
                return .failed(message)
            }
            vendorId = vendor.id
        }
        // A new name can resolve to the current manufacturer when it already
        // exists under that name.
        guard vendorId != filament.vendor?.id else { return .unchanged }

        guard await store.updateFilament(id: filament.id, draft: FilamentDraft(vendorId: .set(vendorId))) else {
            return .failed(store.errorMessage ?? "The manufacturer could not be changed.")
        }
        return .changed
    }
}
