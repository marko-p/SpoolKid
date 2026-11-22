//
//  EmptySpoolEntry.swift
//  SpoolKid
//
//  Purpose: One empty spool in the device-local library — a name, the bare
//  spool's weight, and an optional photo to recognise it by. Belongs to the
//  device, not to a backend: none of the three backends has a "spool type"
//  record, and the library must survive a backend switch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData

@Model
final class EmptySpoolEntry {
    var uuid: UUID = UUID()
    /// Blank when there is none. Free text: the library is shared by every
    /// backend, and a backend's manufacturer list is not.
    var manufacturer: String = ""
    var name: String = ""
    /// Grams, finite and ≥ 0. Zero is valid: a refill weighed without a spool.
    var weight: Double = 0
    /// JPEG from `CameraCaptureView.encode`. Kept outside the store file.
    @Attribute(.externalStorage) var photo: Data?
    /// At most one entry is the default; `EmptySpoolLibrary` keeps it so.
    var isDefault: Bool = false
    /// At most one entry per `ManufacturerName.key(manufacturer)` has it, and
    /// never one with a blank manufacturer; `EmptySpoolLibrary` keeps it so.
    var isManufacturerDefault: Bool = false
    var createdAt: Date = Date()

    init(
        uuid: UUID = UUID(),
        manufacturer: String = "",
        name: String,
        weight: Double,
        photo: Data? = nil,
        isDefault: Bool = false,
        isManufacturerDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.uuid = uuid
        self.manufacturer = manufacturer
        self.name = name
        self.weight = weight
        self.photo = photo
        self.isDefault = isDefault
        self.isManufacturerDefault = isManufacturerDefault
        self.createdAt = createdAt
    }
}
