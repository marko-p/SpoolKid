//
//  SpoolLinkSKU.swift
//  SpoolKid
//
//  Purpose: The `SM<id>` SKU convention that lets an Anycubic ACE tag name the
//  spool it belongs to.
//
//  multiACE resolves an ACE slot's spool from the tag SKU and books consumption
//  back through SpoolLink; `SM<id>` is the form it accepts. The ACE firmware
//  reports no tag UID to its host, so on that hardware the SKU is the only
//  identifier a tag has (issue #5, verified on real hardware 2026-09-12).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolLinkSKU {

    private static let prefix = "SM"

    static func sku(forSpoolID spoolID: Int) -> String {
        "\(prefix)\(spoolID)"
    }

    /// The spool ID an SKU names, or nil when it is anything but the exact
    /// convention. A factory SKU, a filament name, or a bare number stays a
    /// name: a tag misread as belonging to a spool is worse than a tag that
    /// belongs to none.
    static func spoolID(fromSKU sku: String) -> Int? {
        guard sku.hasPrefix(prefix) else { return nil }
        let digits = sku.dropFirst(prefix.count)
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let spoolID = Int(digits),
              spoolID > 0 else { return nil }
        return spoolID
    }
}
