//
//  SpoolMappingService.swift
//  SpoolKid
//
//  Purpose: Helpers for storing NFC card UID mappings in Spoolman's lot_nr field.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

enum SpoolMappingService {
    static let maxCardUIDs = 2
    private static let cardUIDPrefix = "card_uid:"

    enum Slot: Equatable, Sendable {
        case first
        case second
    }

    enum UpdateResult: Equatable, Sendable {
        case updated(String)
        case needsSlotReplacement(existingUIDs: [String], newUID: String)
    }

    static func cardUIDs(in lotNumber: String?) -> [String] {
        guard let lotNumber, !lotNumber.isEmpty else { return [] }

        return lotNumber
            .split(separator: ",")
            .compactMap { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix(cardUIDPrefix) else { return nil }
                let uidStart = trimmed.index(trimmed.startIndex, offsetBy: cardUIDPrefix.count)
                return normalizeUID(String(trimmed[uidStart...]))
            }
            .filter { !$0.isEmpty }
    }

    static func lotNumber(for uids: [String]) -> String {
        let normalized = uniqueNormalizedUIDs(from: uids)
        return normalized
            .prefix(maxCardUIDs)
            .map { "\(cardUIDPrefix)\($0)" }
            .joined(separator: ",")
    }

    static func updatedLotNumber(existingLotNumber: String?, adding uid: String) -> UpdateResult {
        let newUID = normalizeUID(uid)
        var existing = cardUIDs(in: existingLotNumber)

        if existing.contains(newUID) {
            return .updated(lotNumber(for: existing))
        }

        guard existing.count < maxCardUIDs else {
            return .needsSlotReplacement(existingUIDs: Array(existing.prefix(maxCardUIDs)), newUID: newUID)
        }

        existing.append(newUID)
        return .updated(lotNumber(for: existing))
    }

    static func replacingUID(in existingLotNumber: String?, slot: Slot, with uid: String) -> String {
        var existing = cardUIDs(in: existingLotNumber)
        let index = slot == .first ? 0 : 1

        while existing.count <= index {
            existing.append("")
        }

        existing[index] = normalizeUID(uid)
        return Self.lotNumber(for: existing)
    }

    static func normalizeUID(_ uid: String) -> String {
        uid
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func uniqueNormalizedUIDs(from uids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for uid in uids {
            let normalized = normalizeUID(uid)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}
