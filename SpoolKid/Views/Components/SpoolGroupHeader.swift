//
//  SpoolGroupHeader.swift
//  SpoolKid
//
//  Purpose: The header of one group in the grouped spool list. Its body opens
//  the group's subject (a filament, manufacturer, material, color family or location) and its
//  chevron collapses the group. The two are separate buttons so a List row keeps
//  both independently tappable. Header text is composed here from pure helpers;
//  the totals come from SpoolListGrouping (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolGroupHeader: View {
    let group: SpoolGroup
    let mode: SpoolGrouping
    let isCollapsed: Bool
    /// True while a search holds the group open (`SpoolGroup.forcedOpen`): the
    /// chevron is disabled, because toggling it would do nothing.
    let isForcedOpen: Bool
    /// Spools the user has selected inside this group. Shown in the caption so a
    /// collapsed group does not hide a selection.
    let selectedCount: Int
    /// Nil when the group has no screen of its own to open; the body then toggles
    /// the group, so the whole header still does something.
    let onOpen: (() -> Void)?
    let onToggle: () -> Void

    init(group: SpoolGroup, mode: SpoolGrouping, isCollapsed: Bool, isForcedOpen: Bool = false,
         selectedCount: Int = 0, onOpen: (() -> Void)?, onToggle: @escaping () -> Void) {
        self.group = group
        self.mode = mode
        self.isCollapsed = isCollapsed
        self.isForcedOpen = isForcedOpen
        self.selectedCount = selectedCount
        self.onOpen = onOpen
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen ?? onToggle) {
                HStack(spacing: 10) {
                    if mode == .filament, let filament = group.filament {
                        swatch(for: filament)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                // Leading: a title that wraps inside a Button label
                                // is centred otherwise.
                                Text(group.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let material = SpoolUsageRow.material(of: filament) {
                                    materialChip(material)
                                }
                            }
                            Text(Self.filamentSubtitle(filament))
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        if mode == .color, let family = group.colorFamily {
                            FilamentSwatch(colors: FilamentColors(hexes: family.swatchHexes), size: 30)
                        }
                        Text(group.title)
                            .font(.headline)
                            .italic(group.isNoneGroup)
                            .foregroundStyle(group.isNoneGroup ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.primary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        if let total = Self.totalText(for: group) {
                            Text(total)
                                .font(.subheadline)
                        }
                        Text(Self.caption(for: group, selectedCount: selectedCount))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    // The title gives up room before the total and count do.
                    .fixedSize()

                    if !Self.showsChevron(for: group) {
                        // Holds the chevron's slot, so "No spools" lines up with the
                        // other headers' counts. Inside the label, so the whole row
                        // still opens the page. 42: the chevron's 44 and the outer
                        // stack's 8 pt gap, less this stack's 10 pt gap.
                        Color.clear
                            .frame(width: 42, height: 44)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                // Fixed colours: a List button tints its label and the hierarchical
                // styles resolve against that tint.
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)

            if Self.showsChevron(for: group) {
                Button(action: onToggle) {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        // Fixed colours do not dim with `.disabled`, so say it.
                        .opacity(isForcedOpen ? 0.3 : 1)
                }
                .buttonStyle(.borderless)
                .disabled(isForcedOpen)
                .accessibilityLabel(Self.chevronLabel(for: group, isCollapsed: isCollapsed))
                .accessibilityHint(Self.chevronHint(isForcedOpen: isForcedOpen) ?? "")
            }
        }
    }

    private func swatch(for filament: Filament) -> some View {
        FilamentSwatch(colors: filament.colors, size: 30)
    }

    private func materialChip(_ material: String) -> some View {
        Text(material)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
    }

    // MARK: - Copy

    /// "Collapse Original WHITE" / "Expand Original WHITE": the chevron names its
    /// group, since a list of them reads as a row of identical buttons.
    static func chevronLabel(for group: SpoolGroup, isCollapsed: Bool) -> String {
        (isCollapsed ? "Expand " : "Collapse ") + group.title
    }

    /// A group with no rows (a filament or manufacturer with no spools) has
    /// nothing to collapse, so it shows no chevron at all rather than a control
    /// that does nothing (A6).
    static func showsChevron(for group: SpoolGroup) -> Bool {
        !group.entries.isEmpty
    }

    /// Why a disabled chevron is disabled; nil when it is not.
    static func chevronHint(isForcedOpen: Bool) -> String? {
        isForcedOpen ? "The group stays open while searching." : nil
    }

    /// "3 spools · 2 selected". With no active spool the caption says why: "No spools"
    /// when the group has no rows at all, "Archived only" when every spool is archived.
    static func caption(for group: SpoolGroup, selectedCount: Int) -> String {
        let noActiveSpoolsText = group.entries.isEmpty ? SpoolUsage.noSpoolsText : "Archived only"
        var text = group.spoolCount == 0 ? noActiveSpoolsText : SpoolUsage.spoolCountText(group.spoolCount)
        if selectedCount > 0 { text += " · \(selectedCount) selected" }
        return text
    }

    /// The group's remaining weight, or nil when no active spool is left to weigh
    /// or none of them states a weight.
    static func totalText(for group: SpoolGroup) -> String? {
        guard group.spoolCount > 0, let remaining = group.remaining else { return nil }
        return SpoolUsage.weightText(remaining)
    }

    /// "AzureFilm · 1.75 mm": the vendor and diameter, whichever are known.
    static func filamentSubtitle(_ filament: Filament) -> String {
        let vendor = filament.vendor?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return [vendor, filament.diameterText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
