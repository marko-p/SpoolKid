//
//  FilamentColors.swift
//  SpoolKid
//
//  Purpose: The color(s) of a filament, as one value. A filament is either a
//  single color (`colorHex`) or a multi-color filament (`multiColorHexes` plus
//  `multiColorDirection`). This type reads both fields with one rule, holds
//  the editor's rows, and produces the draft fields each save path sends.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct FilamentColors: Equatable, Sendable {

    /// How a multi-color filament's colors are laid out. The raw value is the
    /// Spoolman `multi_color_direction` vocabulary; FilaMan uses different
    /// words for the same two layouts (see `filaManStyle`).
    nonisolated enum Pattern: String, CaseIterable, Sendable {
        case coextruded = "coaxial"
        case gradient = "longitudinal"

        var label: String {
            switch self {
            case .coextruded: "Coextruded"
            case .gradient: "Gradient"
            }
        }

        /// FilaMan's `multi_color_style` vocabulary for this layout.
        var filaManStyle: String {
            switch self {
            case .coextruded: "striped"
            case .gradient: "gradient"
            }
        }

        init?(filaManStyle: String?) {
            switch filaManStyle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "striped": self = .coextruded
            case "gradient": self = .gradient
            default: return nil
            }
        }
    }

    /// Spoolman's own limit on the number of colors the editor offers.
    static let maxEditableColors = 5

    /// Editor rows. While editing these may hold text that is not yet a valid
    /// hex; `isValid` and `draftFields` judge every row through `normalizedHex`.
    var hexes: [String]

    /// Meaningful only when `isMulti`.
    var pattern: Pattern

    init(hexes: [String], pattern: Pattern = .coextruded) {
        self.hexes = hexes.map { Self.trimmedUppercased($0) }
        self.pattern = pattern
    }

    /// The reading rule. Junk parts in `multiColorHexes` are dropped. Two or
    /// more valid parts make a multi-color filament. Otherwise the single
    /// color is `colorHex` when it is valid, else the one surviving part.
    init(colorHex: String?, multiColorHexes: String?, multiColorDirection: String?) {
        let parts = (multiColorHexes ?? "")
            .split(separator: ",")
            .compactMap { Self.normalizedHex(String($0)) }

        if parts.count >= 2 {
            let direction = multiColorDirection?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.init(hexes: parts, pattern: direction.flatMap(Pattern.init(rawValue:)) ?? .coextruded)
        } else if let color = colorHex.flatMap(Self.normalizedHex) {
            self.init(hexes: [color])
        } else {
            self.init(hexes: parts)
        }
    }

    var isMulti: Bool { hexes.count >= 2 }

    /// The first row that is a valid hex. The swatch and the single color
    /// shown in lists use this.
    var primaryHex: String? {
        hexes.lazy.compactMap(Self.normalizedHex).first
    }

    /// Every row is a valid hex, and the row count matches the mode: a single
    /// color has one row, a multi-color filament at least two.
    var isValid: Bool {
        hexes.allSatisfy { Self.normalizedHex($0) != nil }
            && (isMulti ? hexes.count >= 2 : hexes.count == 1)
    }

    var canAddColor: Bool { hexes.count < Self.maxEditableColors }

    /// Switching to multi-color keeps the existing color and adds blank rows
    /// until there are two.
    mutating func switchToMulti() {
        while hexes.count < 2 { hexes.append("") }
    }

    mutating func switchToSingle() {
        hexes = Array(hexes.prefix(1))
    }

    mutating func addColor() {
        guard canAddColor else { return }
        hexes.append("")
    }

    /// A multi-color filament keeps at least two colors. Removing below that
    /// is refused here, so the editor only has to hide the control.
    mutating func removeColor(at index: Int) {
        guard hexes.count > 2, hexes.indices.contains(index) else { return }
        hexes.remove(at: index)
    }

    /// A 6- or 8-digit hex (the 8-digit form carries alpha), after trimming,
    /// stripping a leading `#`, and uppercasing. `nil` for anything else.
    static func normalizedHex(_ raw: String) -> String? {
        let text = trimmedUppercased(raw)
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit) else { return nil }
        return text
    }

    /// These colors with the default color standing in when there are none, so
    /// a form never opens on an empty editor.
    func orDefault(_ hex: String) -> FilamentColors {
        hexes.isEmpty ? FilamentColors(hexes: [hex]) : self
    }

    /// What a tag write carries: the first valid color, and the other valid
    /// colors when there are any. Built from valid rows only, so a blank or
    /// junk row never reaches a tag. With no valid row, the default color.
    var tagColorFields: (colorHex: String, additionalColorHexes: [String]?) {
        let valid = hexes.compactMap(Self.normalizedHex)
        let rest = Array(valid.dropFirst())
        return (valid.first ?? AppConfig.Defaults.colorHex, rest.isEmpty ? nil : rest)
    }

    /// The draft fields a save sends for these colors, given the value the
    /// form loaded.
    ///
    /// An invalid editor state returns the no-op draft: `colorHex` is `nil`
    /// and both pair fields are `.ignore`. Nothing is written from a state
    /// `isValid` rejects.
    ///
    /// Multi-color: `colorHex` is `nil`, meaning set-only "don't touch", and the
    /// pair is sent only when the rows or the pattern differ from the loaded
    /// value, compared after normalization. The backends clear `color_hex`
    /// themselves when a multi pair is `.set`. Single color: the primary hex is
    /// returned, and the pair is cleared only when the loaded value was multi-color.
    func draftFields(loaded: FilamentColors?) -> (
        colorHex: String?,
        multiColorHexes: SpoolmanPatchValue<String>,
        multiColorDirection: SpoolmanPatchValue<String>
    ) {
        guard isValid else { return (nil, .ignore, .ignore) }
        let normalized = hexes.compactMap(Self.normalizedHex)
        if isMulti {
            let loadedNormalized = loaded.map { $0.hexes.compactMap(Self.normalizedHex) }
            if loaded?.isMulti == true, loadedNormalized == normalized, loaded?.pattern == pattern {
                return (nil, .ignore, .ignore)
            }
            return (nil, .set(normalized.joined(separator: ",")), .set(pattern.rawValue))
        }
        let clearsMulti = loaded?.isMulti == true
        return (primaryHex, clearsMulti ? .setNil : .ignore, clearsMulti ? .setNil : .ignore)
    }

    private static func trimmedUppercased(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        return text.uppercased()
    }
}

extension Filament {
    /// The color(s) this filament carries. Read through `FilamentColors`'s
    /// reading rule, so every surface agrees on what a multi-color value is.
    nonisolated var colors: FilamentColors {
        FilamentColors(colorHex: colorHex, multiColorHexes: multiColorHexes, multiColorDirection: multiColorDirection)
    }
}
