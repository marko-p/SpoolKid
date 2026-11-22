//
//  SelectsTextOnFocus.swift
//  SpoolKid
//
//  Purpose: A form field that gains focus selects its whole value, so the
//  first keystroke replaces it instead of appending to it — no holding
//  backspace to clear "1000" before typing "750".
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import SwiftUI
import UIKit

extension View {
    /// Selects a single-line field's text when it gains focus, while
    /// `AppConfig.selectTextOnFocusKey` is on.
    ///
    /// Apply it to a SCREEN — a form's root — never to a field, for the reason
    /// `keyboardDoneBar()` gives: it answers to a UIKit notification, which
    /// reaches every field the screen holds, including those inside child
    /// components, with no focus enum to thread through.
    ///
    /// Multi-line fields (`TextField(axis: .vertical)`, the Comment rows) are
    /// UITextViews and post a different notification, so they keep a caret:
    /// typing over a selected comment would wipe it.
    func selectsTextOnFocus() -> some View {
        modifier(SelectsTextOnFocus())
    }
}

struct SelectsTextOnFocus: ViewModifier {
    @AppStorage(AppConfig.selectTextOnFocusKey) private var isEnabled = true
    /// The notification is app-wide; only fields begun while this screen is
    /// on top are its own. A screen pushed over it fires `onDisappear`.
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onReceive(
                NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
            ) { note in
                guard isEnabled, isOnScreen,
                      let field = note.object as? UITextField, Self.applies(to: field) else { return }
                // UIKit places the caret where the tap landed after editing
                // begins; selecting on the next turn of the run loop wins.
                DispatchQueue.main.async { Self.selectAllText(in: field) }
            }
    }

    /// Search fields keep their own behaviour: the field is for refining a
    /// query, not replacing a value.
    static func applies(to field: UITextField) -> Bool {
        !(field is UISearchTextField)
    }

    /// Selects through `selectedTextRange` rather than `selectAll(_:)`, which
    /// also opens the Cut/Copy/Paste menu on every tap.
    static func selectAllText(in field: UITextField) {
        field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
    }
}
