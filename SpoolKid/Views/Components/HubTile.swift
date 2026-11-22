//
//  HubTile.swift
//  SpoolKid
//
//  Purpose: One Scan Result Hub tile — icon over a label, a large tap target
//  for one-handed bench use. The one primary tile per screen is solid accent;
//  the rest are accent-tinted.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct HubTile: View {
    let action: HubAction
    var isBusy = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: action.systemImage)
                        .font(.title3)
                }
                Text(action.title)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let detail = action.detail {
                    Text(detail)
                        .font(.subheadline)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(HubTileStyle(isPrimary: action.isPrimary))
        .disabled(!action.isEnabled || isBusy)
    }
}

private struct HubTileStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .background(
                isPrimary ? Color.accentColor : Color.accentColor.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

#Preview {
    HStack {
        HubTile(action: HubAction(id: .weigh, title: "Weigh", systemImage: "scalemass")) {}
        HubTile(action: HubAction(id: .linkTag, title: "Link Tag…", systemImage: "link", detail: "SpoolLink off")) {}
        HubTile(action: HubAction(id: .createNewSpool, title: "Create New Spool", systemImage: "plus", isPrimary: true)) {}
    }
    .padding()
}
