//
//  BulkActionResult.swift
//  SpoolKid
//
//  Purpose: Outcome of a bulk archive/delete over a selection of list items.
//

import Foundation

nonisolated struct BulkActionResult {
    let succeeded: Int
    let failed: Int
    var isCompleteSuccess: Bool { failed == 0 }
    var total: Int { succeeded + failed }

    /// What to tell the user when some rows did not make it. `reason` is the
    /// backend's last message; without one the count has to speak alone.
    func partialFailureMessage(reason: String? = nil) -> String {
        let stated = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = "Deleted \(succeeded) of \(total). \(failed) could not be deleted"
        guard let stated, !stated.isEmpty else { return sentence + "." }
        return sentence + ": \(stated)"
    }
}
