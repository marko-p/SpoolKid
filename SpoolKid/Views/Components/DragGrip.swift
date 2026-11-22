//
//  DragGrip.swift
//  SpoolKid
//
//  Purpose: The grip on the right of an arrangeable row, and the gesture that
//  arms a drag from it.
//
//  The gesture is a LONG PRESS followed by a drag, deliberately. A bare
//  `DragGesture` on the grip competes with the enclosing List's pan recogniser
//  for the same first movement — the arbitration that made `.onDelete` pop
//  navigation in this list (`ui-patterns.md`). A long press succeeds BEFORE any
//  movement, takes ownership of the touch, and the drag that follows is
//  uncontested; until it succeeds the List still owns the touch, so the list can
//  still be scrolled by a finger that starts on a grip.
//
//  It also settles "an accidental press must not reorder anything" structurally
//  rather than by a distance heuristic: a tap is too short to arm the gesture at
//  all.
//
//  KNOWN, MEASURED COST (Task 1 spike, 2026-09-12): the grip is a scroll dead
//  zone. `DragGesture(minimumDistance: 0)` wins the touch outright, so a pan
//  that STARTS on the grip does not scroll the list — the same pan a row's
//  width to the left does. Accepted: the grip is a 44pt strip at the trailing
//  edge, and the rest of every row scrolls normally.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct DragGrip: View {
    let accessibilityLabel: String
    let onBegin: () -> Void
    /// The finger's position in `ArrangeSpace`, for hit-testing.
    let onChange: (_ location: CGPoint) -> Void
    /// The finger was lifted deliberately: resolve a drop.
    let onEnd: () -> Void
    /// The SYSTEM took the touch away mid-drag — the row's context menu winning
    /// the same long press is the case that bites here. Separate from `onEnd`
    /// because the two mean opposite things to a write, and a single callback
    /// could not say which had happened.
    let onCancel: () -> Void

    @State private var isDragging = false
    /// Reset by SwiftUI when the gesture ends OR is cancelled — the cancel is
    /// the half a plain `@State` latch cannot observe, which is how a stolen
    /// touch used to leave the lifted card on screen until the app relaunched.
    @GestureState private var isPressed = false
    /// The grip's own on-screen centre, in `ArrangeSpace`, kept current by
    /// `onGeometryChange` below. A still finger generates no touch events at
    /// all, so at the instant a long press RECOGNISES there is no real drag
    /// value yet to report — but the finger is on the grip, so the grip's own
    /// centre at that instant IS the finger's position.
    @State private var gripCenter: CGPoint = .zero
    /// Where the finger was when the lift armed, captured from `gripCenter`.
    /// Every later drag value is measured against this, never against a
    /// header frame — see `travelled` below.
    @State private var armPoint: CGPoint = .zero
    /// Whether a real drag value has moved more than `travelThreshold` from
    /// `armPoint`. Arming now happens on recognition rather than on the first
    /// moved value, so a perfectly still hold-and-release reaches the
    /// sequence's `onEnded` with `isDragging == true` and no travel at all —
    /// and by then every OTHER group has already collapsed under the still
    /// finger, sliding a header (or shifting a reorder count) to wherever the
    /// point happens to sit. Resolving that point would silently move a spool
    /// or reorder a shelf from a press that never went anywhere, which is
    /// exactly what the owner ruled out: "Accidental presses (taps, no or
    /// negligible drag) on the drag icon should not change location order or
    /// move the spool." This latch is what still enforces that now that
    /// arming no longer requires movement.
    @State private var travelled = false

    /// Long enough that a tap or a scroll-start never arms it, short enough that
    /// a deliberate grab does not feel stuck.
    private static let armingDuration: TimeInterval = 0.28
    /// How far a real drag value must move from `armPoint` before a release
    /// is allowed to resolve a drop — see `travelled`.
    private static let travelThreshold: CGFloat = 10

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(isDragging ? 0.4 : 1)
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: ArrangeSpace.space)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { gripCenter = $0 }
            .gesture(gesture)
            // `isPressed` falling while a drag is still latched means the touch
            // was taken, not released. `onEnded` has already cleared the latch
            // on a normal finish, so exactly one of the two paths ever fires.
            .onChange(of: isPressed) { _, pressed in
                guard !pressed, isDragging else { return }
                isDragging = false
                travelled = false
                onCancel()
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    /// Arms the lift exactly once per gesture — at long-press RECOGNITION,
    /// stationary or not, rather than at the first moved drag value (which
    /// never arrives for a finger that never moves). Fires from the long
    /// press's own `.onEnded`, ahead of `.sequenced(before:)`, so a
    /// motionless 0.28s hold is enough.
    private func armed() {
        guard !isDragging else { return }
        isDragging = true
        travelled = false
        armPoint = gripCenter
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        onBegin()
        // No real drag value exists yet; later ones overwrite this via
        // `onChanged` below.
        onChange(gripCenter)
    }

    private var gesture: some Gesture {
        LongPressGesture(minimumDuration: Self.armingDuration)
            .onEnded { _ in armed() }
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: ArrangeSpace.space))
            .updating($isPressed) { _, state, _ in state = true }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !travelled, hypot(drag.location.x - armPoint.x, drag.location.y - armPoint.y) > Self.travelThreshold {
                    travelled = true
                }
                onChange(drag.location)
            }
            .onEnded { _ in
                guard isDragging else { return }
                isDragging = false
                let hasTravelled = travelled
                travelled = false
                // An untravelled release resolves nothing: see `travelled`.
                if hasTravelled {
                    onEnd()
                } else {
                    onCancel()
                }
            }
    }
}

/// The coordinate space every arrangement drag reports in, so a header frame
/// and a finger position are always measured against the same origin.
///
/// `.global`, not a named space, and that is the whole point. A NAMED space
/// does not resolve for a `DragGesture` that lives inside a `List` row:
/// SwiftUI silently hands back the gesture view's LOCAL point instead of
/// failing, while a `GeometryReader` in the same tree resolves the same name
/// correctly. The two therefore disagreed by the grip's own origin — measured
/// on screen 2026-09-12, a finger released at (269, 230) reported as
/// (21, -430) against header rects spanning x32–352, y137–779. A spool drop
/// needs `rect.contains(point)` and so missed every time; a location drop
/// clamps and so silently resolved `reorder(0)` on every drag, which looked
/// like it was working.
enum ArrangeSpace {
    static let space: CoordinateSpace = .global
}
