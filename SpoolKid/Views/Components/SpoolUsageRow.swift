//
//  SpoolUsageRow.swift
//  SpoolKid
//
//  Purpose: One spool in the grouped spool list. The row shows what its group
//  header does not: which spool it is, how much it holds, and when it was last
//  used. Views render these strings and the bar; the rules live in SpoolUsage
//  and DashboardStatsService (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolUsageRow: View {
    let spool: Spool
    var style: SpoolRowStyle = .withFilament
    /// Adds the spool's location to the usage text and the VoiceOver label, for a
    /// list that is not already grouped by location.
    var showsLocation = false

    /// A one-line spool row, and a fold row, is this tall (owner decision O18:
    /// spool rows much shorter than group headers). The lists that show them
    /// lower the List's minimum row height to it (`SpoolListLayout.usesCompactRows`),
    /// and give the rows `compactRowInsets`.
    static let compactRowHeight: CGFloat = 36

    /// Two-line rows are normal list rows (owner decision O25, 2026-10-25): the
    /// List's own insets and minimum height, plus this padding, which is what
    /// the spool row before the grouped lists had.
    static let twoLineRowVerticalPadding: CGFloat = 4

    /// No vertical inset from the List, so a one-line row is `compactRowHeight`.
    /// The 16 pt horizontal is the list's own default, so row content lines up
    /// with a group header's.
    static let compactRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

    /// The insets a list gives a row of `style`: compact under a filament, the
    /// List's own (nil) everywhere else (O25).
    static func rowInsets(for style: SpoolRowStyle) -> EdgeInsets? {
        style == .underFilament ? compactRowInsets : nil
    }

    /// The digit count of the widest `#id` in the list (`spoolIDDigits`).
    @Environment(\.spoolIDDigits) private var listIDDigits

    var body: some View {
        let grams = Self.gramsText(for: spool)
        return HStack(spacing: 10) {
            if style == .underFilament {
                // At least 44 pt so the ids of every row in a group line up, but not
                // fixed: a five-digit id grows the column instead of truncating.
                idText(minWidth: 44, alignment: .leading)

                // One line: usage, tags, bar, grams. A spool with no weight has
                // no grams and no bar, so it reserves neither column.
                usageAndTags
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let grams {
                    bar
                    gramsLabel(grams)
                        .frame(width: 64, alignment: .trailing)
                }
            } else {
                // The number starts at the row's leading edge and its column is
                // exactly as wide as the list's widest id, then 6 pt to the swatch:
                // the swatches line up, and no row keeps empty space for an id the
                // list does not have (owner, 2026-10-24: the room is for the text).
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        idLabel(Self.idColumnTemplate(digits: max(listIDDigits, String(spool.id).count)))
                            .hidden()
                        idLabel("#\(spool.id)")
                    }
                    swatch
                }
                // Two lines. The grams trail the title and the bar trails the usage
                // text, so each sits at the row's far edge. A row with no weight has
                // neither; one with a weight but no basis keeps the bar's width
                // empty, so the usage text ends at the same place as its neighbours'.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(Self.title(for: spool, style: style))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let grams { gramsLabel(grams) }
                    }
                    HStack(spacing: 8) {
                        usageAndTags
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if grams != nil { bar }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: style == .underFilament ? Self.compactRowHeight : nil)
        .padding(.vertical, style == .underFilament ? 0 : Self.twoLineRowVerticalPadding)
        // The whole row is the tap area, not just its text: a `.plain` button in
        // a picker would otherwise miss the gaps between the columns.
        .contentShape(Rectangle())
        // A Button in a List tints its label, and the hierarchical `.primary` and
        // `.secondary` resolve against that tint. Fixed colours stay neutral.
        .foregroundStyle(Color.primary)
        .opacity(spool.archived == true ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: spool, style: style, showsLocation: showsLocation))
    }

    /// The spool number, grey, in a column of at least `minWidth`. The column can
    /// grow past it, so a long id never truncates.
    private func idText(minWidth: CGFloat, alignment: Alignment) -> some View {
        idLabel("#\(spool.id)")
            .frame(minWidth: minWidth, alignment: alignment)
    }

    private func idLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
    }

    /// The digit count of the widest id among `spools`; 0 for none.
    static func idDigits(for spools: [Spool]) -> Int {
        spools.map { String($0.id).count }.max() ?? 0
    }

    /// "#" and `digits` eights. With monospaced digits it is exactly as wide as
    /// any id of that many digits, so it reserves the id column's width.
    static func idColumnTemplate(digits: Int) -> String {
        "#" + String(repeating: "8", count: max(digits, 1))
    }

    private func gramsLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var usageText: some View {
        Text(Self.usageLine(for: spool, style: style, showsLocation: showsLocation))
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
    }

    /// The usage text, with the tag badge on the same line when the spool has
    /// tags. The badge takes the text column's far side, next to the bar, so the
    /// badges of a group line up. At zero tags the line is the text alone.
    private var usageAndTags: some View {
        let tags = Self.tagCount(for: spool)
        return HStack(spacing: 0) {
            usageText
            if tags > 0 {
                Spacer(minLength: 6)
                tagBadge(tags)
            }
        }
    }

    /// A tag glyph and its count. Fixed size, so it never wraps or truncates;
    /// the usage text gives up the room instead.
    private func tagBadge(_ count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "tag")
            Text("\(count)")
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    private var swatch: some View {
        FilamentSwatch(colors: spool.filament.colors, size: 24)
    }

    /// The fill bar. Without a fraction it is still 56 pt wide, so the grams (in
    /// the one-line style) and the end of the usage text (in the two-line style)
    /// keep their place beside rows that do have a bar.
    private var bar: some View {
        Group {
            if let fraction = Self.barFraction(for: spool) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 56 * fraction)
                    }
            } else {
                Color.clear
            }
        }
        .frame(width: 56, height: 5)
    }

    // MARK: - Copy

    static func gramsText(for spool: Spool) -> String? {
        spool.remainingWeight.map(SpoolUsage.weightText)
    }

    /// The fill fraction, clamped to 0...1. Over-full spools (a remaining weight
    /// above the basis) show a full bar rather than overflowing the track.
    static func barFraction(for spool: Spool) -> Double? {
        DashboardStatsService.fillFraction(for: spool).map { min(max($0, 0), 1) }
    }

    /// Every tag that resolves to the spool: Spoolman's native tags, `card_uids`
    /// and FilaMan's `rfid_uid`. The same count the old row showed as "Tags: N".
    static func tagCount(for spool: Spool) -> Int {
        spool.mappedCardUIDs.count
    }

    /// The row's headline. In the name-only style the group header already names
    /// the brand, so the row carries the filament name alone.
    static func title(for spool: Spool, style: SpoolRowStyle) -> String {
        guard style == .withFilamentNameOnly else { return spool.listTitle }
        let name = spool.filament.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? spool.listTitle : name
    }

    /// Archived, then the material (omitted under a filament or material header,
    /// which already names it), then the usage text, then the location when asked.
    static func usageLine(for spool: Spool, style: SpoolRowStyle,
                          now: Date = Date(), locale: Locale = .current,
                          showsLocation: Bool = false) -> String {
        var parts: [String] = []
        if spool.archived == true { parts.append("Archived") }
        if style.showsMaterial, let material = material(of: spool.filament) { parts.append(material) }
        parts.append(SpoolUsage.text(for: spool, now: now, locale: locale))
        if showsLocation, let location = location(of: spool) { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    /// VoiceOver reads the spool as one element. Under a filament header the
    /// header has already said the title and material, so they are left out; under
    /// a material header only the material is. The weight is spelled out, since
    /// "g" and "kg" are read as letters. The location, when asked, comes last.
    static func accessibilityLabel(for spool: Spool, style: SpoolRowStyle,
                                   now: Date = Date(), locale: Locale = .current,
                                   showsLocation: Bool = false) -> String {
        var parts = ["Spool \(spool.id)"]
        if style != .underFilament {
            parts.append(title(for: spool, style: style))
            if style.showsMaterial, let material = material(of: spool.filament) { parts.append(material) }
        }
        parts.append(SpoolUsage.text(for: spool, now: now, locale: locale))
        let tags = tagCount(for: spool)
        if tags > 0 { parts.append(tags == 1 ? "1 tag" : "\(tags) tags") }
        if let remaining = spool.remainingWeight { parts.append("\(SpoolUsage.spokenWeight(remaining)) left") }
        if spool.archived == true { parts.append("archived") }
        if showsLocation, let location = location(of: spool) { parts.append(location) }
        return parts.joined(separator: ", ")
    }

    /// The material with blank values read as absent. Shared with the group
    /// header's material chip, so the two cannot disagree about what is blank.
    static func material(of filament: Filament) -> String? {
        guard let material = filament.material?.trimmingCharacters(in: .whitespacesAndNewlines),
              !material.isEmpty else { return nil }
        return material
    }

    /// The spool's location with a blank value read as absent, as `material(of:)` does.
    static func location(of spool: Spool) -> String? {
        guard let location = spool.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else { return nil }
        return location
    }
}

extension EnvironmentValues {
    /// Set once by a list of spool rows to `SpoolUsageRow.idDigits(for:)` of the
    /// spools it can show, so every two-line row's id column is the same width.
    /// 0 (unset) sizes each row's column to its own id.
    @Entry var spoolIDDigits: Int = 0
}
