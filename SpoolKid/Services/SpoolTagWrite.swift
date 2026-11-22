//
//  SpoolTagWrite.swift
//  SpoolKid
//
//  Purpose: What writing a spool onto a tag puts on it, in which format. One
//  answer for the spool form's Write Tag and the Spool page's.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

@MainActor
enum SpoolTagWrite {
    /// The tag data for `spool` in the user's chosen format, carrying its
    /// spool ID only where the identity mode writes one.
    static func spoolWrite(for spool: Spool, store: SpoolDataStore) -> (data: FilamentTagData, format: TagFormat) {
        let format = TagFormatService.shared.currentFormat
        let data = WriteTagFormAssembler.spoolWriteData(
            for: spool, format: format,
            writesSpoolID: store.tagIdentity.writesSpoolID,
            spoolIDsResolveViaSpoolLink: store.capabilities.spoolIDsResolveViaSpoolLink,
            writesOpacity: UserDefaults.standard.bool(forKey: AppConfig.writeOpacityToTagsKey)
        )
        return (data, format)
    }
}
