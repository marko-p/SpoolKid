//
//  RecentTagManager.swift
//  SpoolKid
//
//  Purpose: Manages a list of recently written NFC tags for quick re-use.
//  Persists recent tags in UserDefaults, limited by the "recent_tags_limit" setting.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftUI

struct RecentTag: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let data: FilamentTagData
    let lastUsed: Date
}

class RecentTagManager: ObservableObject {
    @Published var recentTags: [RecentTag] = []
    
    private let saveKey = "recent_tags"
    
    init() {
        loadTags()
    }
    
    private var limit: Int {
        let val = UserDefaults.standard.integer(forKey: "recent_tags_limit")
        return val > 0 ? val : 20
    }
    
    func addTag(_ data: FilamentTagData) {
        // Remove duplicates based on content (ignoring UUID)
        recentTags.removeAll { 
            $0.data.material == data.material &&
            $0.data.brand == data.brand &&
            $0.data.colorHex == data.colorHex &&
            $0.data.spoolmanId == data.spoolmanId &&
            $0.data.name == data.name
        }
        
        let newTag = RecentTag(data: data, lastUsed: Date())
        recentTags.insert(newTag, at: 0)
        
        // Keep only up to the configured limit
        if recentTags.count > limit {
            recentTags = Array(recentTags.prefix(limit))
        }
        
        saveTags()
    }
    
    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(recentTags) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([RecentTag].self, from: data) {
            recentTags = decoded
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
