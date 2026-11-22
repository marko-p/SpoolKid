//
//  CustomSearchBar.swift
//  SpoolKid
//
//  Purpose: A reusable custom search bar component that mimics the system style.
//

import SwiftUI

struct CustomSearchBar: View {
    @Binding var text: String
    var prompt: String = "Search..."
    /// Mirrors the field's focus both ways: true while it is editing, and
    /// setting it moves the keyboard. A binding rather than a caller's
    /// `.focused`, which does not follow a field inside a toolbar item.
    var isFocused: Binding<Bool> = .constant(false)

    @FocusState private var fieldFocused: Bool

    private let controlHeight: CGFloat = 52
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .imageScale(.medium)
                .foregroundStyle(Color.primary.opacity(0.6))
                .fixedSize()

            // `onEditingChanged` reports focus where `FocusState` cannot: inside a
            // toolbar item it never sees the field focused.
            TextField(prompt, text: $text, onEditingChanged: { editing in
                if isFocused.wrappedValue != editing { isFocused.wrappedValue = editing }
            })
                .font(.system(size: 17, weight: .regular))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.leading)
                .focused($fieldFocused)
                .onChange(of: isFocused.wrappedValue) { _, focused in
                    if fieldFocused != focused { fieldFocused = focused }
                }

            if !text.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .medium))
                        .imageScale(.medium)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: controlHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Capsule(style: .continuous)
                .fill(.bar)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.9)
                }
        }
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .contentShape(Capsule(style: .continuous))
    }
}
