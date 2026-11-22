//
//  LocationGroupHeader.swift
//  SpoolKid
//
//  Purpose: One shelf's row in the arrangement list. Body tap toggles the
//  group (`ManageLocationsView` owns that); `›` pushes the detail screen; the
//  grip arms a drag. Both trailing controls hide while dragging or selecting,
//  so the row never offers an action the current mode cannot honour.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationGroupHeader<Grip: View>: View {
    let name: String
    let isUnassigned: Bool
    let spoolCount: Int
    let selectedCount: Int
    let isMissingFromBackend: Bool
    let storageNoun: String
    let showsControls: Bool
    let onOpenDetail: () -> Void
    @ViewBuilder let grip: () -> Grip

    private var caption: String {
        var parts = [SpoolUsage.spoolCountText(spoolCount)]
        // Select All is scoped to the search filter, not to what is on screen,
        // so a collapsed shelf has to say what it is holding.
        if selectedCount > 0 { parts.append("\(selectedCount) selected") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isUnassigned ? LocationGrouping.unassignedTitle : name)
                    .font(.headline)
                    .italic(isUnassigned)
                    .foregroundStyle(isUnassigned ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isMissingFromBackend {
                    Label("Not in \(storageNoun)", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            // Unassigned is not a location: there is nothing to administer and
            // nothing to reorder. That one IS structural — Unassigned never
            // drags, so no gesture can live here.
            if !isUnassigned {
                // `showsControls` hides these by VALUE, never with an `if`.
                // The grip is where a shelf drag's gesture lives, and an `if`
                // that goes false the moment a drag starts (`grabbed == nil`
                // is exactly that) UN-MOUNTS the gesture's own host view
                // mid-flight. SwiftUI then delivers no further updates, and —
                // because a view that no longer exists cannot run its
                // `.onChange(of: isPressed)` — `DragGrip`'s cancel path never
                // fires either, so the drag is stranded with no `onEnd`, no
                // `onCancel` and no drop. Instrumented on the simulator
                // 2026-09-13: `BEGIN Reorder Bin C` → `GONE Reorder Bin C
                // drag=true`, exactly one `onChanged` delivered, lifted card
                // frozen until relaunch.
                //
                // Opacity + hit testing reads identically to the user and
                // keeps the header's layout from reflowing mid-drag, which the
                // drop geometry prefers anyway.
                Button(action: onOpenDetail) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(name)")
                .accessibilityIdentifier("location.open.\(name)")
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
                .accessibilityHidden(!showsControls)

                // Hit testing goes off with the opacity, so a second finger
                // still cannot arm a second drag on another shelf — the point
                // of hiding these at all. Turning it off does NOT disturb the
                // gesture already tracking this finger: the spool rows item 5
                // hides do exactly this, around the grip driving their drag,
                // and that drag tracks and commits.
                grip()
                    .opacity(showsControls ? 1 : 0)
                    .allowsHitTesting(showsControls)
                    .accessibilityHidden(!showsControls)
            }
        }
        .padding(.vertical, 4)
    }
}
