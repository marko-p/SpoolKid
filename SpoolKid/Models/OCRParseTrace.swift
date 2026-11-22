import Foundation

/// One decision recorded during a single `OCRFilamentParserService.parse` pass. Steps are
/// appended in execution order — reading them top-to-bottom reconstructs how every field's
/// value (or its absence) was reached, including rejected attempts and which fallback fired.
nonisolated struct OCRParseStep: Codable, Sendable {
    /// The field this decision concerns. Real fields use `OCRParsedCandidate.Field.rawValue`;
    /// range-level temperature steps use `"nozzleTemp"` / `"bedTemp"`. Empty for cross-field steps.
    let field: String
    /// The method or branch that ran, e.g. `"exactVocab"`, `"labeledTemperature(print)"`, `"catalogueFallback"`.
    let decision: String
    /// `"accepted"` | `"rejected"` | `"inferred"` | `"fallback"` | `"notFound"` | `"info"`.
    let outcome: String
    /// The resulting value, when one was produced.
    let value: String?
    /// The text span / window the decision considered (truncated for readability).
    let input: String?
    /// Why — especially for `rejected` / `inferred` outcomes (e.g. an overlapping consumed range).
    let note: String?
}

/// Mutable recorder threaded through `OCRFilamentParserService.parse(lines:trace:)`.
///
/// Per-frame scanning passes `nil` (no allocation, no behavior change); the archive builder
/// passes a recorder and re-parses the stored `rawLines` once to capture full provenance.
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `parse` runs on
/// the Vision callback (non-isolated), so this type must be usable from non-isolated contexts.
nonisolated final class OCRParseTrace {
    private(set) var steps: [OCRParseStep] = []

    private static let maxInputLength = 160

    func record(
        field: String = "",
        decision: String,
        outcome: String,
        value: String? = nil,
        input: String? = nil,
        note: String? = nil
    ) {
        steps.append(
            OCRParseStep(
                field: field,
                decision: decision,
                outcome: outcome,
                value: value,
                input: input.map(Self.truncate),
                note: note
            )
        )
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxInputLength else { return text }
        return text.prefix(maxInputLength) + "…"
    }
}
