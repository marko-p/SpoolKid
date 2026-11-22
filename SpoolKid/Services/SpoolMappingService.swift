//
//  SpoolMappingService.swift
//  SpoolKid
//
//  Purpose: Tag UID normalization and tag→spool resolution.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolMappingService {
    /// The spool a tag UID resolves to. A Spoolman native tag wins over every
    /// other source, so a stale `card_uids` copy on another spool can never
    /// beat the native holder by sitting earlier in the list; without one,
    /// the first spool claiming the UID through `mappedCardUIDs` answers, as
    /// before.
    static func spool(in spools: [Spool], claiming uid: String) -> Spool? {
        let normalized = normalizeUID(uid)
        guard !normalized.isEmpty, let id = resolvingSpoolIDs(in: spools)[normalized] else { return nil }
        return spools.first { $0.id == id }
    }

    /// The same answer for every UID at once — uid → id of the spool it
    /// resolves to — for callers that ask about many UIDs, where a lookup per
    /// UID turns quadratic on a large library. The ONE implementation of the
    /// precedence: the first native holder, else the first spool claiming the
    /// UID at all.
    static func resolvingSpoolIDs(in spools: [Spool]) -> [String: Int] {
        var owners: [String: Int] = [:]
        for spool in spools {
            for uid in spool.nativeTagUIDs where owners[uid] == nil { owners[uid] = spool.id }
        }
        var claimed: [String: Int] = [:]
        for spool in spools {
            for uid in spool.mappedCardUIDs where owners[uid] == nil && claimed[uid] == nil { claimed[uid] = spool.id }
        }
        return owners.merging(claimed) { native, _ in native }
    }

    static func normalizeUID(_ uid: String) -> String {
        uid
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }
}
