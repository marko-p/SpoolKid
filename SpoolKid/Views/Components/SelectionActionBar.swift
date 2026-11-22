//
//  SelectionActionBar.swift
//  SpoolKid
//
//  Purpose: Bottom bar shown while a Manage list is in edit mode: select-all toggle on the
//  left, a centered "<n> selected" count, and the destructive bulk action (verb only) on the right.
//

import SwiftUI

/// Bottom bar shown while a Manage list is in edit mode: select-all toggle on the
/// left, a centered "<n> selected" count, and the destructive bulk action (verb only) on the right.
struct SelectionActionBar: View {
    let verb: String
    let count: Int
    let totalCount: Int
    let allSelected: Bool
    /// Defaulted to `.destructive` because that is what the three delete/archive
    /// bars want. Assigning a location is not destructive and must not be red.
    var role: ButtonRole? = .destructive
    let onToggleSelectAll: () -> Void
    let onAction: () -> Void

    var body: some View {
        ZStack {
            Text("\(count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button(allSelected ? "Deselect All" : "Select All", action: onToggleSelectAll)
                    .disabled(totalCount == 0)
                Spacer()
                Button(role: role, action: onAction) {
                    Text(verb).fontWeight(.semibold)
                }
                .disabled(count == 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
