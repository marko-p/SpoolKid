//
//  WeighHistoryStore.swift
//  SpoolKid
//
//  Purpose: This device's own log of every weighing SpoolKid performed, so the
//  weigh loop can show what a spool weighed last time on backends that keep no
//  history of their own — which is all of them except FilaMan.
//
//  Mirrors `TagAssociationStore`: a serial queue guards the array and its
//  persistence, so a write from a non-@MainActor path is safe.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

final class WeighHistoryStore: @unchecked Sendable {
    nonisolated static let shared = WeighHistoryStore()

    /// Oldest entries are dropped past this. A bench session is tens of spools;
    /// this holds many sessions without letting a UserDefaults blob grow
    /// without bound.
    static let capacity = 500

    private let userDefaults: UserDefaults
    private let key: String
    private let queue = DispatchQueue(label: "com.spoolkid.weighhistory")
    private var records: [MeasurementRecord]

    init(userDefaults: UserDefaults = .standard, key: String = AppConfig.weighHistoryKey) {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MeasurementRecord].self, from: data) {
            self.records = decoded
        } else {
            self.records = []
        }
    }

    /// Files a weighing. Called on every successful write, and deliberately NOT
    /// on a failed one: this log is what the user is shown as history, and a
    /// reading the backend rejected is not history, it is a failure the session
    /// already reports.
    func record(spoolID: Int, grossWeight: Double, netWeight: Double?, at date: Date = Date()) {
        let entry = MeasurementRecord(
            id: UUID().uuidString,
            spoolID: spoolID,
            grossWeight: grossWeight,
            netWeight: netWeight,
            recordedAt: date,
            origin: .thisDevice
        )
        queue.sync {
            records.append(entry)
            if records.count > Self.capacity {
                records.removeFirst(records.count - Self.capacity)
            }
            persistLocked()
        }
    }

    /// Newest first. `spoolID` nil returns every spool's history.
    func history(spoolID: Int? = nil, limit: Int? = nil) -> [MeasurementRecord] {
        queue.sync {
            var result = records
            if let spoolID {
                result = result.filter { $0.spoolID == spoolID }
            }
            result.sort { $0.recordedAt > $1.recordedAt }
            if let limit {
                result = Array(result.prefix(limit))
            }
            return result
        }
    }

    func removeAll() {
        queue.sync {
            records = []
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: key)
    }
}
