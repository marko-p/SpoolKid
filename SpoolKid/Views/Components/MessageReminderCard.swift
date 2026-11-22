//
//  MessageReminderCard.swift
//  SpoolKid
//
//  Purpose: The Home card for a message that was closed without its action —
//  a quiet way back to it until the message ends.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// No close control: the card goes when the action is taken or the message
/// ends (owner, 2026-11-21).
struct MessageReminderCard: View {
    let message: AppMessage
    let image: UIImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            DashboardCard {
                HStack(spacing: 12) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let action = message.action {
                            Text(action.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the message")
    }
}
