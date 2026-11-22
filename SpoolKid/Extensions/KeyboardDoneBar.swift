//
//  KeyboardDoneBar.swift
//  SpoolKid
//
//  Purpose: One app-wide way out of the keyboard — a floating "Done" capsule
//  that rides above it on every screen that can raise one.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import SwiftUI

extension View {
    /// Puts a "Done" capsule above the keyboard for as long as one is on screen.
    ///
    /// Apply it to a SCREEN — a form, a sheet's root, a tab's content — never to
    /// an individual field.
    ///
    /// **Why it exists.** `.decimalPad` and `.numberPad` have no return key, so
    /// without a bar there is no way to dismiss them: the keyboard covers the
    /// rest of the form until the user navigates away. That is what the weight
    /// fields did until 2026-08-24, and the rule the owner then set is app-wide
    /// — every keyboard SpoolKid raises has a way out.
    ///
    /// **Why it answers to the keyboard, not to focus.** An earlier version took
    /// a `FocusState` binding, which is more precise but only covers fields the
    /// screen has declared in a focus enum. Screens whose text fields live in
    /// child components (`SpoolmanConnectionForm`, `FilaManConnectionForm`,
    /// `CustomSearchBar`) could not use it at all without threading a binding
    /// through the component, and `WriteTagView`'s thirty fields would have
    /// needed thirty enum cases to state something that is true of all of them.
    /// A keyboard notification says exactly what the bar needs to know. Screens
    /// that track focus for their own reasons (`SpoolFormView` scrolls to the
    /// weight section) still do — the two concerns are simply not the same one.
    ///
    /// **Built as a `safeAreaInset`, NOT `ToolbarItemGroup(placement: .keyboard)`.**
    /// The toolbar form is the documented one and was tried first; it was
    /// verified on the simulator to render nothing at all in `SpoolFormView` —
    /// inside a `NavigationStack`, inside a sheet, which is exactly where it is
    /// supposed to work. SwiftUI insets the bottom safe area for the keyboard,
    /// so an inset bar rides above it wherever the view is presented, with no
    /// toolbar host to depend on.
    func keyboardDoneBar() -> some View {
        modifier(KeyboardDoneBarModifier())
    }
}

private struct KeyboardDoneBarModifier: ViewModifier {
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if isKeyboardVisible {
                    KeyboardDoneBar().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                isKeyboardVisible = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                isKeyboardVisible = false
            }
    }
}

/// A floating "Done" capsule above the keyboard. Deliberately NOT a full-width
/// opaque bar: the app is liquid glass throughout (`writeTagButtonStyle`), and
/// an opaque strip across the keyboard's top edge reads as a foreign control.
private struct KeyboardDoneBar: View {
    var body: some View {
        HStack {
            Spacer()
            // Untargeted sends are usually a guess about the responder chain;
            // here the bar is on screen only while a keyboard is, so there is
            // by construction something to resign.
            Button("Done") {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .glassCapsule()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

extension View {
    /// Liquid glass on iOS 26+, a material capsule below it — the same
    /// version split `writeTagButtonStyle` uses.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.thinMaterial, in: Capsule())
        }
    }
}
