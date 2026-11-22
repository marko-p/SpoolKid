import Testing
import Foundation
@testable import SpoolKid

struct TagAssociationStoreTests {
    private func makeStore() -> TagAssociationStore {
        let defaults = UserDefaults(suiteName: "tagledger.\(UUID().uuidString)")!
        return TagAssociationStore(userDefaults: defaults, key: "test_tag_ledger")
    }

    @Test func recordUpsertsNormalizedUID() {
        let s = makeStore()
        s.record(uid: "abcd12", spoolId: 7)
        #expect(s.snapshot() == ["ABCD12": 7])
    }

    @Test func rewriteReplacesSpoolId() {
        let s = makeStore()
        s.record(uid: "ABCD12", spoolId: 7)
        s.record(uid: "abcd12", spoolId: 9)   // same tag, new owner
        #expect(s.snapshot() == ["ABCD12": 9])
    }

    @Test func removeDeletesEntry() {
        let s = makeStore()
        s.record(uid: "ABCD12", spoolId: 7)
        s.remove(uid: "abcd12")
        #expect(s.snapshot().isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "tagledger.\(UUID().uuidString)")!
        let a = TagAssociationStore(userDefaults: defaults, key: "k")
        a.record(uid: "FF01", spoolId: 3)
        let b = TagAssociationStore(userDefaults: defaults, key: "k")
        #expect(b.snapshot() == ["FF01": 3])
    }
}

/// P-3: the ledger is keyed by backend (kind + server URL, or the Library).
struct TagAssociationStoreScopeTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tagledger.\(UUID().uuidString)")!
    }

    @Test func rowsStayWithTheBackendThatRecordedThem() {
        let d = makeDefaults()
        let s = TagAssociationStore(userDefaults: d, key: "k")
        s.activeBackend = .spoolman
        s.record(uid: "AA", spoolId: 42)
        s.activeBackend = .local
        #expect(s.snapshot().isEmpty)
        s.record(uid: "AA", spoolId: 7)
        s.activeBackend = .spoolman
        #expect(s.snapshot() == ["AA": 42])
    }

    @Test func anotherServerOfTheSameKindIsAnotherScope() {
        let d = makeDefaults()
        d.set("http://a:7912/", forKey: AppConfig.spoolmanUrlKey)
        let s = TagAssociationStore(userDefaults: d, key: "k")
        s.activeBackend = .spoolman
        s.record(uid: "AA", spoolId: 42)
        d.set("http://b:7912", forKey: AppConfig.spoolmanUrlKey)
        #expect(s.snapshot().isEmpty)
        d.set(" HTTP://A:7912 ", forKey: AppConfig.spoolmanUrlKey)
        #expect(s.snapshot() == ["AA": 42])
    }

    @Test func schemeLessAddressSharesTheSchemedScope() {
        let d = makeDefaults()
        d.set("10.0.0.5:7912", forKey: AppConfig.spoolmanUrlKey)
        let s = TagAssociationStore(userDefaults: d, key: "k")
        s.activeBackend = .spoolman
        s.record(uid: "AA", spoolId: 42)
        d.set("http://10.0.0.5:7912/", forKey: AppConfig.spoolmanUrlKey)
        #expect(s.snapshot() == ["AA": 42])
    }

    @Test func legacyGlobalMapIsAdoptedByTheFirstActiveBackend() throws {
        let d = makeDefaults()
        d.set(try JSONEncoder().encode(["FF01": 3]), forKey: "k")
        let s = TagAssociationStore(userDefaults: d, key: "k")
        s.activeBackend = .spoolman
        #expect(s.snapshot() == ["FF01": 3])
        #expect(d.data(forKey: "k") == nil)
        s.activeBackend = .local
        #expect(s.snapshot().isEmpty)
        let reloaded = TagAssociationStore(userDefaults: d, key: "k")
        reloaded.activeBackend = .spoolman
        #expect(reloaded.snapshot() == ["FF01": 3])
    }
}
