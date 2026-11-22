import Foundation

/// A number lifted out of OCR label text, tagged with the unit printed next to it and the
/// nearest field label that precedes it. Attribution-by-label is what lets every numeric field
/// claim only the numbers that belong to it: a "330" carrying `.meter` after a "length" label is
/// a filament length, never a nozzle temperature — with no per-field character-window heuristics.
nonisolated struct OCRNumberToken: Equatable, Sendable {
    let value: Int
    let unit: OCRNumberUnit
    /// Digit-span location within the canonical string the tokenizer ran on (for the consumption
    /// tracker, so a number claimed by one field can't be reused by another).
    let range: NSRange
    /// Lowercased, whitespace-stripped field-label keyword immediately preceding the number, or
    /// nil if none precedes it.
    let label: String?
}

nonisolated enum OCRNumberUnit: Equatable, Sendable {
    case degree       // °C / °F / ° / a bare C or F directly after the digits
    case millimeter   // mm  (diameter, ± tolerance, mm/s speeds)
    case meter        // m   (filament length)
    case gram         // g
    case kilogram     // kg
    case percent      // %
    case none         // bare number, no recognised unit

    /// Unitless or degree-marked numbers can be temperatures; physical units never are.
    var isTemperatureCompatible: Bool { self == .degree || self == .none }
}
