//
//  MessageView.swift
//  SpoolKid
//
//  Purpose: One owner-to-user message, large: image, title, text, and the
//  message's action. Renders and routes; `MessageService` decides the rest.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Swipe-down is disabled, so Close and the action are the only ways out —
/// which is why the caller records "seen" in `onClose` / `onAction`, with the
/// message this sheet was built for.
struct MessageView: View {
    let message: AppMessage
    let image: UIImage?
    /// The caller marks the message acted; the view then opens the link and closes.
    let onAction: () -> Void
    /// The caller marks the message seen (or nothing, when reopened from Home).
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                    Text(message.title)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message.formattedBody)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                        // Links in the text open in Safari and do nothing else;
                        // anything but https is dropped.
                        .environment(\.openURL, OpenURLAction { url in
                            url.scheme == "https" ? .systemAction : .discarded
                        })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) { buttonBar }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    private var buttonBar: some View {
        VStack(spacing: 8) {
            if let action = message.action {
                Button {
                    onAction()
                    openURL(action.url)
                    dismiss()
                } label: {
                    // The arrow after the label says "leaves the app".
                    HStack(spacing: 6) {
                        Text(action.label)
                        Image(systemName: "arrow.up.forward")
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                onClose()
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

#Preview {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            MessageView(
                message: AppMessage(
                    id: "preview",
                    title: "Help SpoolKid win the Snapmaker Innovation Fund",
                    body: "SpoolKid is entered in the **Innovation Fund**.\n\nIf it has helped you, a vote on the [forum](https://forum.snapmaker.com) would mean a lot.",
                    image: nil,
                    action: .init(label: "Vote on the Forum", url: URL(string: "https://forum.snapmaker.com")!),
                    start: .now, end: .now.addingTimeInterval(86_400),
                    reminder: nil
                ),
                image: nil,
                onAction: {},
                onClose: {}
            )
        }
}
