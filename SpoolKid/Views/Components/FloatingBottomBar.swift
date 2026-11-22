//
//  FloatingBottomBar.swift
//  SpoolKid
//
//  Purpose: The Tags and Library tabs' floating bottom bar of icon-only glass
//  buttons, in thumb reach above the tab bar. A `.bottomBar` toolbar on a tab
//  root draws underneath iOS 26's floating tab bar (owner, 2026-10-29), so the
//  bar is a safe-area bar instead.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import UIKit

/// One icon of a floating bottom bar. The title is its accessibility label —
/// the button's old visible title — and the prominent one is the screen's
/// primary action.
struct BottomBarButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    /// 130% of the regular button with its title under it, for the Tags and
    /// Library tab roots (owner, 2026-11-04; 150% overlapped on device).
    /// Weigh Spools keeps the regular size: its four icons have to fit inside
    /// the tab bar's width.
    var large = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var scale: CGFloat { large ? 1.3 : 1 }

    var body: some View {
        if large {
            VStack(spacing: 4) {
                circle
                // Under the circle, not inside it: glass would wrap it into
                // the button. Tapping it taps the button.
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    // A halo in the background colour keeps the name
                    // readable over the rows scrolling under it, in light
                    // and dark alike (owner, 2026-11-04).
                    .shadow(color: Color(uiColor: .systemBackground), radius: 1)
                    .shadow(color: Color(uiColor: .systemBackground), radius: 3)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: action)
                    .allowsHitTesting(isEnabled)
            }
            // One element, the button: `accessibilityHidden` on the name
            // still left it in the tree as a second "Scan Tag".
            .accessibilityRepresentation {
                Button(title, action: action)
            }
            .accessibilityShowsLargeContentViewer {
                Label(title, systemImage: systemImage)
            }
        } else {
            circle
        }
    }

    private var circle: some View {
        Button(action: action) {
            // Capped at xxxLarge: past it the glyph outgrew the fixed circle.
            // Larger sizes get the title in the Large Content Viewer instead,
            // as the system tab bar does.
            BottomBarGlyph(systemImage: systemImage, scale: scale)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .modifier(BottomBarButtonStyle(prominent: prominent))
        // Plain icons in the label colour, white or black; only the prominent
        // one carries the accent, as its fill (owner, 2026-10-30). Glass draws
        // its label in the tint, so the tint is what has to change.
        .tint(prominent ? Color.accentColor : Color.primary)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }
}

/// The button's icon. Its own view so its scaled size reads the capped
/// Dynamic Type size the button sets on it.
private struct BottomBarGlyph: View {
    let systemImage: String
    let scale: CGFloat
    @ScaledMetric(relativeTo: .title3) private var title3Size: CGFloat = 20

    var body: some View {
        Image(systemName: systemImage)
            .font(scale == 1 ? .title3 : .system(size: title3Size * scale))
            // 26 pt: four regular buttons and their spacing fit inside the
            // 273-pt tab bar they line up with, each still over 44 pt. The
            // glass circle's own padding grows by the same factor.
            .frame(width: 26 * scale, height: 26 * scale)
            .padding(15 * (scale - 1))
    }
}

/// Glass on iOS 26, the bordered equivalents below it.
private struct BottomBarButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    /// A tab's action buttons float over the list instead of sitting below it. As a
    /// sibling in a VStack they cut the list off above a strip of plain
    /// window background — a white (or black) slab behind the buttons and the
    /// glass tab bar, with nothing ever scrolling under either. On iOS 26 a
    /// `safeAreaBar` lets rows pass underneath behind the system's scroll-edge
    /// effect, as they do under the navigation bar; below iOS 26 the inset
    /// carries the `.bar` material the system tab bar itself uses there.
    ///
    /// The bar's sides line up with the floating tab bar's (see
    /// `FloatingBottomBarMetrics`), so content gets vertical padding only.
    ///
    /// The bar steps aside while the keyboard is up: a safe-area bar would
    /// otherwise ride up on it, over the search results, where a system
    /// bottom toolbar stays behind it.
    ///
    /// `alignedToTabBar: false` gives the bar the screen's width less the
    /// standard margin instead, for the Tags and Library roots' large,
    /// centred buttons, which outgrow the tab bar (owner, 2026-11-04).
    @ViewBuilder
    func floatingBottomBar(alignedToTabBar: Bool = true, @ViewBuilder _ bar: () -> some View) -> some View {
        let content = bar()
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom) { HiddenUnderKeyboard(alignedToTabBar: alignedToTabBar) { content } }
        } else {
            safeAreaInset(edge: .bottom) { HiddenUnderKeyboard(alignedToTabBar: alignedToTabBar) { content }.background(.bar) }
        }
    }
}

/// Where the bar's sides go. iOS 26's tab bar floats as a 273-pt capsule,
/// centred on every iPhone (measured on the 17e, 17, 17 Pro and 17 Pro Max,
/// iOS 26.5 and 27); lined up with its edges, the outermost buttons sit under
/// the thumb instead of at the screen edges (owner, 2026-10-30). Four 56-pt
/// icons fit inside it. Below iOS 26 the tab bar runs edge to edge, so the
/// bar keeps the standard margin.
nonisolated enum FloatingBottomBarMetrics {
    static let floatingTabBarWidth: CGFloat = 273
    static let standardMargin: CGFloat = 16

    static func sideInset(containerWidth: CGFloat, floatingTabBar: Bool) -> CGFloat {
        guard floatingTabBar else { return standardMargin }
        return max(standardMargin, (containerWidth - floatingTabBarWidth) / 2)
    }

    /// Never negative: the first layout pass offers a zero-wide container,
    /// which would otherwise give the bar a width of minus both margins.
    static func barWidth(containerWidth: CGFloat, floatingTabBar: Bool) -> CGFloat {
        max(0, containerWidth - 2 * sideInset(containerWidth: containerWidth, floatingTabBar: floatingTabBar))
    }
}

/// Renders its content only while no keyboard is shown, its sides on the tab
/// bar's. The width comes from the container, not from measuring the
/// bar: the inset changes the bar's own width, so measuring it loops.
private struct HiddenUnderKeyboard<Content: View>: View {
    let alignedToTabBar: Bool
    @ViewBuilder let content: () -> Content
    @State private var keyboardIsUp = false

    private var floatingTabBar: Bool {
        guard alignedToTabBar else { return false }
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    var body: some View {
        Group {
            if !keyboardIsUp {
                content()
                    .containerRelativeFrame(.horizontal) { width, _ in
                        FloatingBottomBarMetrics.barWidth(containerWidth: width, floatingTabBar: floatingTabBar)
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsUp = false
        }
    }
}
