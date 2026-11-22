//
//  RecentTagManager.swift
//  SpoolKid
//
//  Purpose: Manages a list of recently written NFC tags for quick re-use.
//  Persists recent tags in UserDefaults, limited by the "recent_tags_limit" setting.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftUI

struct RecentTag: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let data: FilamentTagData
    /// The format the tag was written in. Nil for entries saved before
    /// 2026-10-03, which did not record it.
    let format: TagFormat?
    let lastUsed: Date
}

class RecentTagManager: ObservableObject {
    @Published var recentTags: [RecentTag] = []
    
    private let saveKey = AppConfig.recentTagsKey
    
    init() {
        loadTags()
    }
    
    private var limit: Int {
        let val = UserDefaults.standard.integer(forKey: AppConfig.recentTagsLimitKey)
        return val > 0 ? val : 20
    }
    
    /// `superseded` is an entry this write replaces even though it differs —
    /// one whose stale spool ID the write dropped.
    func addTag(_ data: FilamentTagData, format: TagFormat?, replacing superseded: FilamentTagData? = nil) {
        recentTags = Self.adding(data, format: format, replacing: superseded, to: recentTags, limit: limit, at: Date())
        saveTags()
    }

    /// `tags` with `data` on top. One entry per filament per format: the same
    /// content in the same format is replaced, and so is an entry with no
    /// recorded format, since it may be that one. `superseded` goes in every
    /// format, because a stale spool ID is stale whatever the format.
    static func adding(
        _ data: FilamentTagData,
        format: TagFormat?,
        replacing superseded: FilamentTagData?,
        to tags: [RecentTag],
        limit: Int,
        at date: Date
    ) -> [RecentTag] {
        // Same content, ignoring the UUID
        func same(_ a: FilamentTagData, _ b: FilamentTagData) -> Bool {
            a.material == b.material &&
                a.brand == b.brand &&
                a.colorHex == b.colorHex &&
                a.spoolmanId == b.spoolmanId &&
                a.name == b.name
        }
        var kept = tags.filter { entry in
            let duplicate = same(entry.data, data) && (entry.format == nil || entry.format == format)
            return !duplicate && !(superseded.map { same(entry.data, $0) } ?? false)
        }
        // What a printer has used belongs to the spool the tag was written
        // for. A Recent Tag is usually reused for a new one, so it starts full.
        var stored = data
        stored.consumedWeight = nil
        kept.insert(RecentTag(data: stored, format: format, lastUsed: date), at: 0)
        return Array(kept.prefix(limit))
    }
    
    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(recentTags) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([RecentTag].self, from: data) {
            // Entries recorded from an ACE write before 2026-10-03 hold the
            // SKU as the name.
            recentTags = decoded.map {
                RecentTag(id: $0.id, data: $0.data.readingSpoolLinkSKU(), format: $0.format, lastUsed: $0.lastUsed)
            }
        }
    }
    
    func removeTag(at offsets: IndexSet) {
        recentTags.remove(atOffsets: offsets)
        saveTags()
    }

    func refresh() {
        loadTags()
    }
}
