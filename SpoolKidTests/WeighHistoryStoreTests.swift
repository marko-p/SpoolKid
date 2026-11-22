import Testing
import Foundation
@testable import SpoolKid

struct WeighHistoryStoreTests {

    private func store(_ name: String = UUID().uuidString) -> WeighHistoryStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WeighHistoryStore(userDefaults: defaults, key: "test_weigh_history")
    }

    @Test func aWeighIsRecordedAndReadBack() {
        let subject = store()
        subject.record(spoolID: 7, grossWeight: 1238, netWeight: 1000)

        let history = subject.history(spoolID: 7)

        #expect(history.count == 1)
        #expect(history.first?.grossWeight == 1238)
        #expect(history.first?.netWeight == 1000)
        #expect(history.first?.origin == .thisDevice)
    }

    @Test func historyIsScopedToOneSpool() {
        let subject = store()
        subject.record(spoolID: 1, grossWeight: 100, netWeight: nil)
        subject.record(spoolID: 2, grossWeight: 200, netWeight: nil)

        #expect(subject.history(spoolID: 1).map(\.grossWeight) == [100])
        #expect(subject.history().count == 2)
    }

    @Test func historyComesBackNewestFirst() {
        let subject = store()
        let now = Date()
        subject.record(spoolID: 1, grossWeight: 1, netWeight: nil, at: now.addingTimeInterval(-100))
        subject.record(spoolID: 1, grossWeight: 2, netWeight: nil, at: now)
        subject.record(spoolID: 1, grossWeight: 3, netWeight: nil, at: now.addingTimeInterval(-50))

        #expect(subject.history(spoolID: 1).map(\.grossWeight) == [2, 3, 1])
    }

    @Test func theLimitTakesTheNewestNotTheFirstRecorded() {
        let subject = store()
        let now = Date()
        subject.record(spoolID: 1, grossWeight: 1, netWeight: nil, at: now.addingTimeInterval(-100))
        subject.record(spoolID: 1, grossWeight: 2, netWeight: nil, at: now)

        #expect(subject.history(spoolID: 1, limit: 1).map(\.grossWeight) == [2])
    }

    @Test func aSpoolNeverWeighedHasNoHistory() {
        let subject = store()
        subject.record(spoolID: 1, grossWeight: 100, netWeight: nil)
        #expect(subject.history(spoolID: 99).isEmpty)
    }

    @Test func theLogSurvivesARestart() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        WeighHistoryStore(userDefaults: defaults, key: "k")
            .record(spoolID: 4, grossWeight: 900, netWeight: 700)

        let reopened = WeighHistoryStore(userDefaults: defaults, key: "k")
        #expect(reopened.history(spoolID: 4).map(\.grossWeight) == [900])
    }

    @Test func theOldestEntriesFallOffPastCapacity() {
        let subject = store()
        let now = Date()
        for i in 0...WeighHistoryStore.capacity {
            subject.record(
                spoolID: 1, grossWeight: Double(i), netWeight: nil,
                at: now.addingTimeInterval(Double(i))
            )
        }
        let history = subject.history(spoolID: 1)
        #expect(history.count == WeighHistoryStore.capacity)
        // The first weighing is the one that went; the newest is still there.
        #expect(!history.contains { $0.grossWeight == 0 })
        #expect(history.first?.grossWeight == Double(WeighHistoryStore.capacity))
    }

    @Test func removeAllClearsTheLog() {
        let subject = store()
        subject.record(spoolID: 1, grossWeight: 100, netWeight: nil)
        subject.removeAll()
        #expect(subject.history().isEmpty)
    }
}
