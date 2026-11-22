//
//  DestructiveFormButton.swift
//  SpoolKid
//
//  Purpose: A destructive button for a form footer (Archive Spool / Delete Vendor…). Honors
//  the confirm-before-delete preference: confirms when on, acts immediately when off.
//

import SwiftUI

/// A destructive button for a form footer (Archive Spool / Delete Vendor…). Honors
/// the confirm-before-delete preference: confirms when on, acts immediately when off.
struct DestructiveFormButton: View {
    let title: String
    let confirmTitle: String
    let confirmMessage: String
    let confirmBeforeDelete: Bool
    let action: () -> Void

    @State private var showConfirm = false

    var body: some View {
        Button(role: .destructive) {
            if confirmBeforeDelete { showConfirm = true } else { action() }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .confirmationDialog(confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
            Button(title, role: .destructive, action: action)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmMessage)
        }
    }
}
