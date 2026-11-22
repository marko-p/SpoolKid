import Testing
import Foundation
@testable import SpoolKid

struct DashboardLayoutStoreTests {
    private func store() -> DashboardLayoutStore {
        DashboardLayoutStore(userDefaults: UserDefaults(suiteName: "dash.\(UUID().uuidString)")!)
    }
    @Test func defaultsMatchKindDefaults() {
        let s = store()
        #expect(s.isVisible(.colors) == true)
        #expect(s.isVisible(.totalValue) == false)
    }
    @Test func togglePersists() {
        let defaults = UserDefaults(suiteName: "dash.\(UUID().uuidString)")!
        let s = DashboardLayoutStore(userDefaults: defaults)
        s.setVisible(true, for: .totalValue)
        s.setVisible(false, for: .colors)
        let s2 = DashboardLayoutStore(userDefaults: defaults)
        #expect(s2.isVisible(.totalValue) == true)
        #expect(s2.isVisible(.colors) == false)
    }
}
