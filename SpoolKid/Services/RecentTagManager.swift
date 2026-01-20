import Foundation
import Combine

struct RecentTag: Codable, Identifiable {
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
        
        // Keep only last 20
        if recentTags.count > 20 {
            recentTags = Array(recentTags.prefix(20))
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
    
    func refresh() {
        loadTags()
    }
}
